///|
fn check_pattern(ast : Ast) -> Unit raise ParseError {
  match ast {
    Empty => ()
    Set(set) =>
      if !set.json_literal_bytes() {
        raise ParseError(
          pos=0,
          msg="pattern contains a byte that is not a raw JSON string character",
        )
      }
    Concat(items) | Alt(items) =>
      for item in items {
        check_pattern(item)
      }
    Repeat(inner, _, _) => check_pattern(inner)
    JsonChars(_) => raise ParseError(pos=0, msg="unsupported pattern syntax")
  }
}

///|
/// Returns `pattern` grouped, after rejecting matches that are not raw JSON string bytes.
pub fn string_pattern(pattern : String) -> String raise ParseError {
  check_pattern(parse(pattern))
  "(?:" + pattern + ")"
}

///|
/// One decoded JSON string character. `\uXXXX` is a BMP code point; a surrogate
/// pair is one character. Lone surrogates and `\u{...}` are not alternatives.
let json_char : String =
  #|(?:[ !#-\[\]-~]|\\["\\/bfnrt]|[\xC2-\xDF][\x80-\xBF]|\xE0[\xA0-\xBF][\x80-\xBF]|[\xE1-\xEC][\x80-\xBF][\x80-\xBF]|\xED[\x80-\x9F][\x80-\xBF]|[\xEE-\xEF][\x80-\xBF][\x80-\xBF]|\xF0[\x90-\xBF][\x80-\xBF][\x80-\xBF]|[\xF1-\xF3][\x80-\xBF][\x80-\xBF][\x80-\xBF]|\xF4[\x80-\x8F][\x80-\xBF][\x80-\xBF]|\\u(?:[0-9a-ce-fA-CE-F][0-9a-fA-F]{3}|[dD][0-7][0-9a-fA-F]{2})|\\u[dD][89aAbB][0-9a-fA-F]{2}\\u[dD][c-fC-F][0-9a-fA-F]{2})

///|
pub fn json_unit() -> String {
  json_char
}

///|
fn json_alphabet() -> ByteSet {
  let set = ByteSet::empty()
  for b in 0x20..<=0x7E {
    if b != 0x22 && b != 0x5C {
      set.add_byte(b)
    }
  }
  set
}

///|
fn byte_set_of(bytes : Array[Int]) -> ByteSet {
  let set = ByteSet::empty()
  for b in bytes {
    set.add_byte(b)
  }
  set
}

///|
/// Unanchored search over the pattern alphabet. Accepting states stay accepting,
/// so a later character does not erase a match that already happened.
fn search_dfa(pattern : String) -> Dfa raise ParseError {
  check_pattern(parse(pattern))
  let nfa = Nfa::from_ast(parse(pattern))
  let old_start = nfa.start
  let old_accept = nfa.accept
  let skip = nfa.add_state()
  let sink = nfa.add_state()
  let alphabet = json_alphabet()
  nfa.moves[skip].push((alphabet, skip))
  nfa.moves[sink].push((alphabet, sink))
  nfa.eps[skip].push(old_start)
  nfa.eps[old_accept].push(sink)
  nfa.start = skip
  nfa.accept = sink
  Dfa::from_nfa(nfa)
}

///|
fn Nfa::move_literals(self : Nfa, from : Int, to : (Int) -> Int) -> Unit {
  let dests : Array[Int] = []
  let groups : Array[Array[Int]] = []
  for b in 0x20..<=0x7E {
    if b == 0x22 || b == 0x5C {
      continue
    }
    let dest = to(b)
    let mut found = -1
    for i, existing in dests {
      if existing == dest {
        found = i
      }
    }
    if found < 0 {
      dests.push(dest)
      groups.push([b])
    } else {
      groups[found].push(b)
    }
  }
  for i, dest in dests {
    self.moves[from].push((byte_set_of(groups[i]), dest))
  }
}

///|
fn Nfa::step_bytes(
  self : Nfa,
  from : Int,
  lo : Int,
  hi : Int,
) -> Int raise ParseError {
  let next = self.add_state()
  self.moves[from].push((ByteSet::of_range(lo, hi), next))
  next
}

///|
fn Nfa::finish_bytes(
  self : Nfa,
  from : Int,
  lo : Int,
  hi : Int,
  dest : Int,
) -> Unit {
  self.moves[from].push((ByteSet::of_range(lo, hi), dest))
}

///|
fn hex_digits() -> ByteSet {
  let set = ByteSet::of_range('0'.to_int(), '9'.to_int())
  set.add_all(ByteSet::of_range('a'.to_int(), 'f'.to_int()))
  set.add_all(ByteSet::of_range('A'.to_int(), 'F'.to_int()))
  set
}

///|
fn nibble_digits(n : Int) -> ByteSet {
  if n < 10 {
    ByteSet::of_range('0'.to_int() + n, '0'.to_int() + n)
  } else {
    let set = ByteSet::of_range('a'.to_int() + n - 10, 'a'.to_int() + n - 10)
    set.add_byte('A'.to_int() + n - 10)
    set
  }
}

///|
fn nibbles_set(lo : Int, hi : Int) -> ByteSet {
  let set = ByteSet::empty()
  for n in lo..<=hi {
    set.add_all(nibble_digits(n))
  }
  set
}

///|
fn pattern_byte(b : Int) -> Bool {
  b >= 0x20 && b <= 0x7E && b != 0x22 && b != 0x5C
}

///|
/// Entry of a run of `n` hex digits that then arrives at `dest`.
fn Nfa::hex_run(self : Nfa, n : Int, dest : Int) -> Int raise ParseError {
  let digits = hex_digits()
  let entry = self.add_state()
  let mut cur = entry
  for _ in 1..<n {
    let nxt = self.add_state()
    self.moves[cur].push((digits, nxt))
    cur = nxt
  }
  self.moves[cur].push((digits, dest))
  entry
}

///|
/// From a state that has just read `\`, accept `\uXXXX`. A surrogate pair counts
/// once and lands on `reset_at`. A BMP code point in the pattern alphabet lands on
/// `ascii_at`. Lone surrogates and `\u{...}` have no edge.
fn Nfa::link_u(
  self : Nfa,
  mid : Int,
  reset_at : Int,
  ascii_at : (Int) -> Int,
) -> Unit raise ParseError {
  let ustart = self.add_state()
  self.moves[mid].push((byte_set_of(['u'.to_int()]), ustart))
  let any3 = self.hex_run(3, reset_at)
  let any2 = self.hex_run(2, reset_at)
  let one_hex = self.hex_run(1, reset_at)
  let not_d = nibbles_set(1, 12)
  not_d.add_all(nibbles_set(14, 15))
  self.moves[ustart].push((not_d, any3))
  let s0 = self.add_state()
  self.moves[ustart].push((nibble_digits(0), s0))
  let sd = self.add_state()
  self.moves[ustart].push((nibble_digits(13), sd))
  let s00 = self.add_state()
  self.moves[s0].push((nibble_digits(0), s00))
  self.moves[s0].push((nibbles_set(1, 15), any2))
  self.moves[sd].push((nibbles_set(0, 7), any2))
  let broad = nibbles_set(0, 1)
  broad.add_all(nibbles_set(8, 15))
  self.moves[s00].push((broad, one_hex))
  for hi in 2..<=7 {
    let st = self.add_state()
    self.moves[s00].push((nibble_digits(hi), st))
    for lo in 0..<16 {
      let byte = hi * 16 + lo
      let dest = if pattern_byte(byte) { ascii_at(byte) } else { reset_at }
      self.moves[st].push((nibble_digits(lo), dest))
    }
  }
  let tail = self.add_state()
  let high_entry = self.hex_run(2, tail)
  self.moves[sd].push((nibbles_set(8, 11), high_entry))
  let u2 = self.add_state()
  self.moves[tail].push((byte_set_of([0x5C]), u2))
  let dstate = self.add_state()
  self.moves[u2].push((byte_set_of(['u'.to_int()]), dstate))
  let after_d = self.add_state()
  self.moves[dstate].push((nibble_digits(13), after_d))
  let low_entry = self.hex_run(2, reset_at)
  self.moves[after_d].push((nibbles_set(12, 15), low_entry))
}

///|
/// Lead state of one non-ASCII code point. Every complete sequence ends at `dest`.
fn Nfa::utf8_lead(self : Nfa, dest : Int) -> Int raise ParseError {
  let entry = self.add_state()
  let two = self.step_bytes(entry, 0xC2, 0xDF)
  self.finish_bytes(two, 0x80, 0xBF, dest)
  let e0 = self.step_bytes(entry, 0xE0, 0xE0)
  let e0b = self.step_bytes(e0, 0xA0, 0xBF)
  self.finish_bytes(e0b, 0x80, 0xBF, dest)
  let e1 = self.step_bytes(entry, 0xE1, 0xEC)
  let e1b = self.step_bytes(e1, 0x80, 0xBF)
  self.finish_bytes(e1b, 0x80, 0xBF, dest)
  let ed = self.step_bytes(entry, 0xED, 0xED)
  let edb = self.step_bytes(ed, 0x80, 0x9F)
  self.finish_bytes(edb, 0x80, 0xBF, dest)
  let ee = self.step_bytes(entry, 0xEE, 0xEF)
  let eeb = self.step_bytes(ee, 0x80, 0xBF)
  self.finish_bytes(eeb, 0x80, 0xBF, dest)
  let f0 = self.step_bytes(entry, 0xF0, 0xF0)
  let f0b = self.step_bytes(f0, 0x90, 0xBF)
  let f0c = self.step_bytes(f0b, 0x80, 0xBF)
  self.finish_bytes(f0c, 0x80, 0xBF, dest)
  let f1 = self.step_bytes(entry, 0xF1, 0xF3)
  let f1b = self.step_bytes(f1, 0x80, 0xBF)
  let f1c = self.step_bytes(f1b, 0x80, 0xBF)
  self.finish_bytes(f1c, 0x80, 0xBF, dest)
  let f4 = self.step_bytes(entry, 0xF4, 0xF4)
  let f4b = self.step_bytes(f4, 0x80, 0x8F)
  let f4c = self.step_bytes(f4b, 0x80, 0xBF)
  self.finish_bytes(f4c, 0x80, 0xBF, dest)
  entry
}

///|
/// `(?@min,max,len:pattern)` counts decoded characters. `\` starts an escape and
/// does not increment the length; the second byte does. `\/` is the character `/`.
/// A non-ASCII code point counts as one character and cannot continue an ASCII pattern.
fn Nfa::json_chars(
  self : Nfa,
  pattern : String,
  min : Int,
  max : Int?,
) -> (Int, Int) raise ParseError {
  let search = search_dfa(pattern)
  if search.is_accept(search.start) {
    return self.build(Repeat(parse(json_char), min, max))
  }
  let scount = search.state_count()
  let last = match max {
    None => min
    Some(bound) => bound
  }
  let layers = last + 1
  let boundary : Array[Int] = []
  let escaping : Array[Int] = []
  for _ in 0..<(layers * scount) {
    boundary.push(self.add_state())
    escaping.push(self.add_state())
  }
  let exit = self.add_state()
  let backslash = byte_set_of([0x5C])
  let slash = byte_set_of(['/'.to_int()])
  let hidden = byte_set_of([
    0x22,
    0x5C,
    'b'.to_int(),
    'f'.to_int(),
    'n'.to_int(),
    'r'.to_int(),
    't'.to_int(),
  ])
  fn at(i : Int, p : Int) -> Int {
    i * scount + p
  }

  fn advance(p : Int, b : Int) -> Int {
    let t = search.step(p, b.to_byte())
    if t >= 0 {
      t
    } else {
      search.start
    }
  }

  let utf8_cache : Map[Int, Int] = Map([])
  for i in 0..<=last {
    for p in 0..<scount {
      let from = boundary[at(i, p)]
      if i >= min && search.is_accept(p) {
        self.eps[from].push(exit)
      }
      let next = match max {
        None => if i < min { Some(i + 1) } else { Some(i) }
        Some(bound) => if i < bound { Some(i + 1) } else { None }
      }
      guard next is Some(next_i) else { continue }
      self.move_literals(from, b => boundary[at(next_i, advance(p, b))])
      let reset = if search.is_accept(p) { p } else { search.start }
      let dest = boundary[at(next_i, reset)]
      let lead = match utf8_cache.get(dest) {
        Some(entry) => entry
        None => {
          let entry = self.utf8_lead(dest)
          utf8_cache[dest] = entry
          entry
        }
      }
      self.eps[from].push(lead)
      let mid = escaping[at(i, p)]
      self.moves[from].push((backslash, mid))
      let reset = if search.is_accept(p) { p } else { search.start }
      self.moves[mid].push((hidden, boundary[at(next_i, reset)]))
      self.moves[mid].push(
        (slash, boundary[at(next_i, advance(p, '/'.to_int()))]),
      )
      self.link_u(mid, dest, b => boundary[at(next_i, advance(p, b))])
    }
  }
  (boundary[at(0, search.start)], exit)
}
