///|
fn whitespace_vocab() -> @vocab.Vocab {
  let tokens : Array[Bytes] = [b""]
  for b in 0..<256 {
    tokens.push(Bytes::make(1, b.to_byte()))
  }
  for t in [" \n{ \"x\" : [ ", "1 ,\t", "2 ] }\r\n", "1 2", "1, ]}", "\n\t"] {
    tokens.push(@utf8.encode(t))
  }
  @vocab.Vocab::new(tokens, eos=0)
}

///|
test "whitespace mask matches byte walking and gates EOS at each prefix" {
  let dfa = @schema.compile(
    {
      "type": "object",
      "properties": {
        "x": {
          "type": "array",
          "items": { "type": "integer" },
          "minItems": 2,
          "maxItems": 2,
        },
      },
      "required": ["x"],
    },
    whitespace=true,
  )
  let vocab = whitespace_vocab()
  let guide = @mask.Guide::new(dfa, vocab)
  let mut state = guide.start()
  assert_false(guide.allowed(state).contains(vocab.eos))
  for piece in [" \n{ \"x\" : [ ", "1 ,\t", "2 ] }\r\n", "\n\t"] {
    let allowed = guide.allowed(state)
    for id in 1..<vocab.size() {
      assert_eq(allowed.contains(id), dfa.walk(state, vocab.tokens[id]) >= 0)
    }
    assert_eq(allowed.contains(vocab.eos), dfa.is_accept(state))
    let id = token_id(vocab, @utf8.encode(piece))
    assert_true(allowed.contains(id))
    state = guide.advance(state, id).unwrap()
  }
  assert_true(guide.allowed(state).contains(vocab.eos))
  for bad in [b"1", b",", b"}", b"\x0b", b"\x0c"] {
    assert_false(guide.allowed(state).contains(token_id(vocab, bad)))
  }
}

///|
test "budget exhaustion cannot keep sampling whitespace loops" {
  let dfa = @schema.compile(
    {
      "type": "array",
      "items": { "type": "integer" },
      "minItems": 2,
      "maxItems": 2,
    },
    whitespace=true,
  )
  let vocab = whitespace_vocab()
  let guide = @mask.Guide::new(dfa, vocab)
  let rand = @random.Rand::chacha8(seed=b"moonmask-whitespace-budget-00042")
  for prefix in ["", " \t", "[", "[ ", "[ 1", "[ 1 ,\n", "[1,2]", "[1,2] \r\n"] {
    let mut state = dfa.walk(guide.start(), @utf8.encode(prefix))
    assert_true(state >= 0)
    let distance = dfa.distance(state)
    let mut ended = false
    for step in 0..<=distance {
      let id = @mask.monkey_step(guide, rand, state, step~, max_tokens=0).unwrap()
      if id == vocab.eos {
        assert_true(dfa.is_accept(state))
        ended = true
        break
      }
      let next = guide.advance(state, id).unwrap()
      assert_true(dfa.distance(next) < dfa.distance(state))
      state = next
    }
    assert_true(ended)
  }
  for budget in [0, 1, 8, 32] {
    for _ in 0..<30 {
      let sample = @mask.monkey(guide, rand, max_tokens=budget)
      assert_true(sample.finished)
      assert_true(dfa.matches(sample.text))
      assert_eq(sample.tokens[sample.tokens.length() - 1], vocab.eos)
    }
  }
}

///|
test "sparse vocabulary reports stuck instead of accepting whitespace" {
  let dfa = @schema.compile({ "const": true }, whitespace=true)
  let vocab = @vocab.Vocab::new([b"", b" ", b"\t"], eos=0)
  let guide = @mask.Guide::new(dfa, vocab)
  let rand = @random.Rand::chacha8(seed=b"moonmask-whitespace-sparse-00042")
  assert_false(guide.allowed(guide.start()).contains(vocab.eos))
  assert_true(
    @mask.monkey_step(guide, rand, guide.start(), step=0, max_tokens=0) is None,
  )
  assert_false(@mask.monkey(guide, rand, max_tokens=4).finished)
}
