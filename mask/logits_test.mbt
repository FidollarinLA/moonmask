///|
test "greedy suppresses illegal high logits without modifying scores" {
  let v = @vocab.Vocab::new([b"", b"x", b"a", b"b", b"ab"], eos=0)
  let g = @mask.Guide::new(@regex.compile("ab"), v)
  let scores = [999.0, 888.0, 2.0, 777.0, 3.0]
  assert_eq(g.greedy(g.start(), scores), Some(4))
  assert_eq(scores, [999.0, 888.0, 2.0, 777.0, 3.0])
  let next = g.advance(g.start(), 4).unwrap()
  assert_eq(g.greedy(next, scores), Some(0))
}

///|
test "greedy ties use the lowest token id including EOS" {
  let v = @vocab.Vocab::new([b"a", b"", b"a", b"aa"], eos=1)
  let g = @mask.Guide::new(@regex.compile("a*"), v)
  assert_eq(g.greedy(g.start(), [1.0, 1.0, 1.0, 1.0]), Some(0))
  assert_eq(g.greedy(g.start(), [0.0, 1.0, 1.0, 1.0]), Some(1))
}

///|
test "greedy validates scores and never invents an all-suppressed token" {
  let v = @vocab.Vocab::new([b"", b"a", b"x"], eos=0)
  let g = @mask.Guide::new(@regex.compile("a"), v)
  let neg = @double.neg_infinity
  assert_true(g.greedy(g.start(), [100.0, neg, 100.0]) is None)
  let cases = [
    [0.0],
    [0.0, @double.infinity, 0.0],
    [0.0, 0.0, @double.not_a_number],
  ]
  for scores in cases {
    let rejected = try g.greedy(g.start(), scores) catch {
      @mask.InvalidLogits(_) => true
    } noraise {
      _ => false
    }
    assert_true(rejected)
  }
  for state in [-1, g.dfa.state_count()] {
    let rejected = try g.greedy(state, [0.0, 0.0, 0.0]) catch {
      @mask.InvalidLogits(_) => true
    } noraise {
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "greedy explicit finishing policy excludes whitespace loops" {
  let v = @vocab.Vocab::new([b"", b" ", b"true", b"tr", b"ue"], eos=0)
  let g = @mask.Guide::new(
    @schema.compile({ "const": true }, whitespace=true),
    v,
  )
  let scores = [0.0, 100.0, 2.0, 3.0, 4.0]
  assert_eq(g.greedy(g.start(), scores), Some(1))
  assert_eq(g.greedy(g.start(), scores, finish=true), Some(3))
  let state = g.advance(g.start(), 3).unwrap()
  assert_eq(g.greedy(state, scores, finish=true), Some(4))
  let state = g.advance(state, 4).unwrap()
  assert_eq(g.greedy(state, scores), Some(1))
  assert_eq(g.greedy(state, scores, finish=true), Some(0))
  assert_true(
    g.greedy(state, [@double.neg_infinity, 100.0, 2.0, 3.0, 4.0], finish=true)
    is None,
  )
}

///|
test "greedy rejects invalid EOS and reports sparse-vocabulary dead ends" {
  let dfa = @regex.compile("ab")
  let invalid = @mask.Guide::new(dfa, @vocab.Vocab::new([b"a"], eos=9))
  let rejected = try invalid.greedy(invalid.start(), [1.0]) catch {
    @mask.InvalidLogits(_) => true
  } noraise {
    _ => false
  }
  assert_true(rejected)
  let sparse = @mask.Guide::new(dfa, @vocab.Vocab::new([b"", b"a"], eos=0))
  let state = sparse.advance(sparse.start(), 1).unwrap()
  assert_true(sparse.greedy(state, [100.0, 1.0], finish=true) is None)
}
