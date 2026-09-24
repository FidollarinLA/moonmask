///|
fn tiny_vocab() -> @vocab.Vocab {
  let tokens : Array[Bytes] = []
  for b in 32..<127 {
    tokens.push(Bytes::make(1, b.to_byte()))
  }
  for t in ["ab", "a1", "a12", "cd", "tr", "true", "ue", "10", "\",", "},"] {
    tokens.push(@utf8.encode(t))
  }
  tokens.push(b"")
  @vocab.Vocab::new(tokens, eos=tokens.length() - 1)
}

///|
fn token_id(v : @vocab.Vocab, t : Bytes) -> Int {
  for i in 0..<v.size() {
    if v.tokens[i] == t && i != v.eos {
      return i
    }
  }
  abort("missing token")
}

///|
fn is_prefix(p : Bytes, s : Bytes) -> Bool {
  if p.length() > s.length() {
    return false
  }
  for i in 0..<p.length() {
    if p[i] != s[i] {
      return false
    }
  }
  true
}

///|
/// Brute force: every string over `alphabet` up to `max_len` accepted by the oracle.
fn accepted_strings(
  pattern : String,
  alphabet : Array[Char],
  max_len : Int,
) -> Array[Bytes] raise {
  let oracle = @regexp.compile("^(?:" + pattern + ")$")
  let out : Array[Bytes] = []
  let mut layer : Array[String] = [""]
  for _ in 0..<=max_len {
    let next : Array[String] = []
    for s in layer {
      if oracle.execute(s).matched() {
        out.push(@utf8.encode(s))
      }
      for c in alphabet {
        next.push(s + c.to_string())
      }
    }
    layer = next
  }
  out
}

///|
test "mask equals brute-force viability on a finite language" {
  let pattern = "(?:ab|a[0-2]{1,2}|cd?|true)"
  let v = tiny_vocab()
  let g = @mask.Guide::new(@regex.compile(pattern), v)
  let accepted = accepted_strings(
    pattern,
    ['a', 'b', 'c', 'd', 't', 'r', 'u', 'e', '0', '1', '2'],
    4,
  )
  guard g.advance(g.start(), token_id(v, b"a")) is Some(after_a) else {
    fail("token a must be allowed at the start")
  }
  for check in [(b"", g.start()), (b"a", after_a)] {
    let (prefix, state) = check
    let allowed = g.allowed(state)
    for id in 0..<v.size() {
      if id == v.eos {
        assert_eq(allowed.contains(id), accepted.contains(prefix))
        continue
      }
      let joined = prefix + v.tokens[id]
      let viable = v.tokens[id].length() > 0 &&
        accepted.iter().any(s => is_prefix(joined, s))
      if allowed.contains(id) != viable {
        fail(
          "token \{id} after \{prefix}: mask \{allowed.contains(id)}, brute force \{viable}",
        )
      }
    }
  }
}

///|
test "eos only in accepting states" {
  let v = tiny_vocab()
  let g = @mask.Guide::new(@regex.compile("ab"), v)
  assert_false(g.allowed(g.start()).contains(v.eos))
  guard g.advance(g.start(), token_id(v, b"ab")) is Some(done) else {
    fail("ab must be allowed")
  }
  assert_eq(g.allowed(done), [v.eos])
  assert_eq(g.advance(done, v.eos), None)
}

///|
test "monkey always finishes with an accepted output" {
  let v = tiny_vocab()
  let dfa = @schema.compile({
    "type": "object",
    "properties": {
      "n": { "type": "integer" },
      "s": { "type": "string", "maxLength": 3 },
    },
    "additionalProperties": false,
  })
  let g = @mask.Guide::new(dfa, v)
  let rand = @random.Rand::chacha8(seed=b"moonmask-monkey-test-seed-000000")
  for _ in 0..<200 {
    let out = @mask.monkey(g, rand, max_tokens=24)
    assert_true(out.finished)
    assert_true(dfa.matches(out.text))
    assert_eq(out.tokens[out.tokens.length() - 1], v.eos)
  }
}

///|
test "over budget the sampler heads straight for an accepting state" {
  let v = tiny_vocab()
  let dfa = @regex.compile("a*b")
  let g = @mask.Guide::new(dfa, v)
  let rand = @random.Rand::chacha8(seed=b"moonmask-budget-test-seed-000000")
  for _ in 0..<50 {
    let out = @mask.monkey(g, rand, max_tokens=3)
    assert_true(out.finished)
    assert_true(out.tokens.length() <= 5)
    assert_true(dfa.matches(out.text))
  }
}

///|
test "unmasked monkey respects the token budget" {
  let v = tiny_vocab()
  let rand = @random.Rand::chacha8(seed=b"moonmask-unmasked-seed-000000000")
  let out = @mask.monkey_unmasked(v, rand, max_tokens=10)
  assert_true(out.tokens.length() <= 10)
}

///|
/// The pre-trie mask: walk every token byte string from `state`.
fn scan_transitions(
  dfa : @regex.Dfa,
  vocab : @vocab.Vocab,
  state : Int,
) -> Array[(Int, Int)] {
  let out : Array[(Int, Int)] = []
  for id in 0..<vocab.size() {
    let bytes = vocab.tokens[id]
    if id == vocab.eos || bytes.length() == 0 {
      continue
    }
    let next = dfa.walk(state, bytes)
    if next >= 0 {
      out.push((id, next))
    }
  }
  out
}

///|
fn assert_same_mask(dfa : @regex.Dfa, vocab : @vocab.Vocab) -> Unit raise {
  let guide = @mask.Guide::new(dfa, vocab)
  for state in 0..<dfa.state_count() {
    let got = guide.transitions(state)
    let expect = scan_transitions(dfa, vocab, state)
    assert_eq(got, expect)
    let allowed = guide.allowed(state)
    let want = expect.map(fn(pair) { pair.0 })
    if dfa.is_accept(state) {
      want.push(vocab.eos)
    }
    assert_eq(allowed, want)
    for id in 0..<vocab.size() {
      if vocab.tokens[id].length() == 0 {
        assert_false(allowed.contains(id) && id != vocab.eos)
      }
    }
  }
}

///|
fn vocab_with_shared_prefixes() -> @vocab.Vocab {
  let tokens : Array[Bytes] = [
    b"", b"a", b"ab", b"abc", b"ax", b"b", b"ba", b"true", b"tr", b"t", b"",
  ]
  @vocab.Vocab::new(tokens, eos=tokens.length() - 1)
}

///|
test "prefix tree matches a full scan on a small vocabulary" {
  let vocab = vocab_with_shared_prefixes()
  let patterns = [
    "ab", "a*b", "abc|ax", "(?:ab|a[0-2]{1,2}|cd?|true)", "true|false",
  ]
  for pattern in patterns {
    assert_same_mask(@regex.compile(pattern), vocab)
  }
  let dfa = @schema.compile({
    "type": "object",
    "properties": {
      "n": { "type": "integer" },
      "s": { "type": "string", "maxLength": 2 },
    },
    "additionalProperties": false,
  })
  assert_same_mask(dfa, tiny_vocab())
  assert_same_mask(dfa, vocab_with_shared_prefixes())
}

///|
fn open_gpt2() -> @tokenizer.Tokenizer {
  let paths = [
    "assets/gpt2/tokenizer.json", "../assets/gpt2/tokenizer.json", "../../assets/gpt2/tokenizer.json",
  ]
  for path in paths {
    let opened = try @tokenizer.from_file(path) catch {
      _ => None
    } noraise {
      tok => Some(tok)
    }
    match opened {
      Some(tok) => return tok
      None => ()
    }
  }
  abort("run ./scripts/fetch-gpt2.sh before the GPT-2 mask test")
}

///|
fn remember(states : Array[Int], state : Int) -> Unit {
  if state >= 0 && !states.contains(state) {
    states.push(state)
  }
}

///|
fn check_gpt2_states(
  dfa : @regex.Dfa,
  vocab : @vocab.Vocab,
  prefixes : Array[String],
) -> Unit raise {
  let guide = @mask.Guide::new(dfa, vocab)
  let states : Array[Int] = []
  remember(states, dfa.start)
  for prefix in prefixes {
    let mut walked = dfa.start
    for byte in @utf8.encode(prefix) {
      walked = dfa.step(walked, byte)
      remember(states, walked)
    }
    remember(states, dfa.walk(dfa.start, @utf8.encode(prefix)))
  }
  assert_true(states.length() >= 3)
  for state in states {
    let got = guide.transitions(state)
    let expect = scan_transitions(dfa, vocab, state)
    assert_eq(got, expect)
    let allowed = guide.allowed(state)
    if dfa.is_accept(state) {
      assert_true(allowed.contains(vocab.eos))
    } else {
      assert_false(allowed.contains(vocab.eos))
    }
    for id in 0..<vocab.size() {
      if vocab.tokens[id].length() == 0 {
        assert_false(got.iter().any(fn(pair) { pair.0 == id }))
      }
    }
  }
}

///|
test "prefix tree matches a full scan on several gpt-2 states" {
  let vocab = @vocab.from_tokenizer(open_gpt2(), eos_token="<|endoftext|>")
  check_gpt2_states(
    @schema.compile({
      "type": "object",
      "properties": { "a": { "type": "boolean" } },
      "additionalProperties": false,
    }),
    vocab,
    ["{", "{\"", "{\"a\"", "{\"a\":", "{\"a\":true}"],
  )
  check_gpt2_states(
    @schema.compile({ "enum": ["red", "green", "blue"] }),
    vocab,
    ["\"", "\"r", "\"re", "\"red\"", "\"g", "\"b", "\"blue\""],
  )
}
