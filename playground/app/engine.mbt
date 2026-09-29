///|
extern "js" fn now_ms() -> Double = "() => performance.now()"

///|
struct Lexicon {
  id : Int
  vocab : @vocab.Vocab
}

///|
impl Eq for Lexicon with fn equal(a, b) {
  a.id == b.id
}

///|
/// Printable ASCII, a newline, the UTF-8 bytes of a few CJK words and a set of
/// multi-byte fragments that show up in the presets. The fragments make the mask
/// interesting: at most states several tokens of different lengths fit.
fn toy_vocab() -> @vocab.Vocab {
  let tokens : Array[Bytes] = [b""]
  for c = 32; c < 127; c = c + 1 {
    tokens.push(Bytes::make(1, c.to_byte()))
  }
  tokens.push(b"\n")
  let words = [
    "{\"", "\"}", "\":", "\",", "\",\"", "\":\"", ", ", "\": ", "},{", "[{", "}]",
    "true", "false", "null", "name", "age", "role", "admin", "editor", "viewer",
    "active", "id", "title", "done", "tag", "work", "home", "tool", "args", "city",
    "unit", "search", "query", "top_k", "get_weather", "order", "_id", "items", "sku",
    "qty", "note", "12", "42", "100", "2026", "-0", "-1", "com", "org", "SELECT ",
    " FROM ", " WHERE ", "users", "orders", "INFO", "WARN", "ERROR", "the", "ing",
    "er", "an", "moon", "bit", "mask", "北京", "上海", "你好",
  ]
  for w in words {
    tokens.push(@utf8.encode(w))
  }
  @vocab.Vocab::new(tokens, eos=0)
}

///|
struct Engine {
  id : Int
  dfa : @regex.Dfa
  guide : @mask.Guide
  validator : @moonschema.Schema?
  pattern : String?
  millis : Double
}

///|
impl Eq for Engine with fn equal(a, b) {
  a.id == b.id
}

///|
fn build_dfa(
  mode : Mode,
  source : String,
) -> (@regex.Dfa, @moonschema.Schema?, String?) raise {
  match mode {
    Schema => {
      let json = @json.parse(source)
      let validator = try @moonschema.Schema::new(json) catch {
        _ => None
      } noraise {
        s => Some(s)
      }
      let pattern = @schema.to_regex(json)
      (@regex.compile(pattern), validator, Some(pattern))
    }
    Regex => (@regex.compile(source), None, None)
    Grammar => (@gbnf.compile(source), None, None)
  }
}

///|
fn compile(
  mode : Mode,
  source : String,
  lexicon : Lexicon,
  id : Int,
) -> Result[Engine, String] {
  let t0 = now_ms()
  try build_dfa(mode, source) catch {
    e => Err(e.to_string())
  } noraise {
    (dfa, validator, pattern) => {
      let guide = @mask.Guide::new(dfa, lexicon.vocab)
      if guide.allowed(guide.start()).length() == 0 {
        return Err("the constraint accepts nothing this vocabulary can spell")
      }
      Ok({ id, dfa, guide, validator, pattern, millis: now_ms() - t0, })
    }
  }
}

///|
/// Whether `text` is a complete, valid output. Schema mode asks moonschema, an
/// independent validator, rather than the DFA that produced the text.
fn Engine::check(self : Engine, text : Bytes) -> Bool {
  match self.validator {
    Some(v) =>
      try @json.parse(@utf8.decode(text)) catch {
        _ => false
      } noraise {
        json => v.valid(json)
      }
    None => self.dfa.matches(text)
  }
}

///|
fn Engine::judge(self : Engine) -> String {
  match self.validator {
    Some(_) => "moonschema"
    None => "DFA"
  }
}

///|
fn token_text(v : @vocab.Vocab, id : Int) -> String {
  if id == v.eos {
    return "⏎eos"
  }
  let s = @utf8.decode_lossy(v.tokens[id])
  let out = StringBuilder()
  for c in s {
    match c {
      ' ' => out.write_char('·')
      '\n' => out.write_char('↵')
      '\t' => out.write_char('⇥')
      c => out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn text_of(v : @vocab.Vocab, ids : Array[Int]) -> Bytes {
  let buf = Buffer()
  for id in ids {
    if id != v.eos {
      buf.write_bytes(v.tokens[id])
    }
  }
  buf.to_bytes()
}

///|
fn byte_name(b : Int) -> String {
  if b == 32 {
    "␣"
  } else if b == 92 {
    "\\\\"
  } else if b > 32 && b < 127 {
    b.unsafe_to_char().to_string()
  } else {
    let hex = "0123456789ABCDEF"
    "\\x" +
    hex[b / 16:b / 16 + 1].to_owned() +
    hex[b % 16:b % 16 + 1].to_owned()
  }
}

///|
/// A compact, regex-like name for a set of bytes, e.g. `[0-9]`, `"` or `[^"\\]`.
fn byte_set_label(set : Array[Bool]) -> String {
  let count = set.fold(init=0, (n, x) => if x { n + 1 } else { n })
  if count == 256 {
    return "any"
  }
  let negate = count > 128
  let ranges = StringBuilder()
  let mut parts = 0
  let mut b = 0
  while b < 256 {
    if set[b] != negate {
      let lo = b
      while b + 1 < 256 && set[b + 1] != negate {
        b = b + 1
      }
      parts = parts + 1
      ranges.write_string(byte_name(lo))
      if b > lo {
        ranges.write_string(if b > lo + 1 { "-" } else { "" })
        ranges.write_string(byte_name(b))
      }
    }
    b = b + 1
  }
  let body = ranges.to_string()
  if !negate && parts == 1 && count == 1 {
    body
  } else if negate {
    "[^" + body + "]"
  } else {
    "[" + body + "]"
  }
}

///|
fn clip(s : String, n : Int) -> String {
  if s.length() <= n {
    s
  } else {
    s[:n - 1].to_owned() + "…"
  }
}

///|
/// Outgoing edges of `state`, one per target, labelled with the bytes that lead there.
fn out_edges(dfa : @regex.Dfa, state : Int) -> Array[(Int, String)] {
  let sets : Map[Int, Array[Bool]] = Map::from_array([])
  let order = []
  for b = 0; b < 256; b = b + 1 {
    let t = dfa.step(state, b.to_byte())
    if t < 0 {
      continue
    }
    match sets.get(t) {
      Some(set) => set[b] = true
      None => {
        let set = Array::make(256, false)
        set[b] = true
        sets[t] = set
        order.push(t)
      }
    }
  }
  order.map(t => (t, byte_set_label(sets[t])))
}

///|
struct GNode {
  state : Int
  layer : Int
  hidden : Int
  loop_label : String?
}

///|
struct GEdge {
  src : Int
  dst : Int
  label : String
}

///|
/// Breadth-first neighbourhood of `focus`, `per_layer` states wide at most.
fn neighbourhood(
  dfa : @regex.Dfa,
  focus : Int,
  depth~ : Int,
  per_layer~ : Int,
) -> (Array[GNode], Array[GEdge]) {
  let layer_of : Map[Int, Int] = Map::from_array([(focus, 0)])
  let layers = [[focus]]
  for d = 0; d < depth; d = d + 1 {
    let next = []
    for s in layers[d] {
      for e in out_edges(dfa, s) {
        if next.length() < per_layer && !layer_of.contains(e.0) {
          layer_of[e.0] = d + 1
          next.push(e.0)
        }
      }
    }
    if next.length() == 0 {
      break
    }
    layers.push(next)
  }
  let nodes = []
  let edges = []
  for d, layer in layers {
    for s in layer {
      let mut hidden = 0
      let mut loop_label = None
      for e in out_edges(dfa, s) {
        let (t, label) = e
        if t == s {
          loop_label = Some(label)
        } else if layer_of.get(t) is Some(lt) && lt == d + 1 {
          edges.push({ src: s, dst: t, label, })
        } else {
          hidden = hidden + 1
        }
      }
      nodes.push({ state: s, layer: d, hidden, loop_label, })
    }
  }
  (nodes, edges)
}

///|
fn fixed(x : Double, digits : Int) -> String {
  let mut scale = 1
  for _ in 0..<digits {
    scale = scale * 10
  }
  let n = (x * scale.to_double() + 0.5).to_int()
  if digits == 0 {
    return n.to_string()
  }
  let frac = (n % scale).to_string()
  (n / scale).to_string() + "." + "0".repeat(digits - frac.length()) + frac
}

///|
fn seed_bytes(seed : Int) -> Bytes {
  let s = "moonmask-playground-" + seed.to_string()
  @utf8.encode(s + "0".repeat(32 - s.length()))
}
