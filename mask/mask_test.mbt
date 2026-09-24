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
