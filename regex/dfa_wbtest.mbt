///|
fn compile_error(pattern : String) -> String? {
  try compile(pattern) catch {
    ParseError(msg~, ..) => Some(msg)
  } noraise {
    _ => None
  }
}

///|
test "nested repetitions do not leak partial iterations" {
  let d = compile("(?:b*c)*")
  assert_true(d.accepts(""))
  assert_true(d.accepts("bcbbcc"))
  assert_false(d.accepts("b"))
  assert_false(d.accepts("bcb"))
  let e = compile("(?:ab*)*c")
  assert_true(e.accepts("c"))
  assert_true(e.accepts("abbac"))
  assert_false(e.accepts("bc"))
  let f = compile("(?:a?){0,3}b")
  assert_true(f.accepts("b"))
  assert_true(f.accepts("aaab"))
  assert_false(f.accepts("aaaab"))
}

///|
test "zero-width repetitions and empty patterns" {
  let d = compile("a{0}b")
  assert_true(d.accepts("b"))
  assert_false(d.accepts("ab"))
  let e = compile("")
  assert_true(e.accepts(""))
  assert_false(e.accepts("a"))
  assert_eq(e.distance(e.start), 0)
}

///|
test "empty language collapses to one dead-end state" {
  let d = compile("a[^\u{00}-\u{7f}]")
  assert_eq(d.state_count(), 1)
  assert_false(d.is_accept(d.start))
  assert_eq(d.step(d.start, b'a'), -1)
  assert_eq(d.distance(d.start), no_accepting_path)
  assert_eq(d.sample(@random.Rand::chacha8(), max_len=10), None)
}

///|
test "every live state can reach acceptance" {
  let d = compile("(?:ab|ac)d{2,4}|x[0-9]+")
  for s in 0..<d.state_count() {
    assert_true(d.distance(s) >= 0)
    assert_eq(d.is_accept(s), d.distance(s) == 0)
  }
  assert_eq(d.distance(d.start), 2)
  assert_eq(d.step(-1, b'a'), -1)
  assert_eq(d.walk(-1, b""), -1)
}

///|
test "oversized automata are rejected" {
  assert_eq(compile_error("(?:a{1000}){1000}"), Some("automaton too large"))
  assert_eq(compile_error("[ab]*a[ab]{20}"), Some("automaton too large"))
}

///|
test "json-sized patterns stay small" {
  let d = compile(
    (
      #|\{"name":"(?:[^"\\]|\\["\\/bfnrt]){0,64}","age":(?:0|[1-9][0-9]{0,15}),"tags":\[(?:"[a-z]{1,20}"(?:,"[a-z]{1,20}"){0,9})?\]\}
    ),
  )
  assert_true(
    d.accepts(
      (
        #|{"name":"a\"b","age":42,"tags":["x","yz"]}
      ),
    ),
  )
  assert_false(
    d.accepts(
      (
        #|{"name":"a","age":042,"tags":[]}
      ),
    ),
  )
  let rand = @random.Rand::chacha8(seed=b"moonmask-regex-json-sample-seed!")
  for _ in 0..<50 {
    if d.sample(rand, max_len=2000) is Some(s) {
      assert_true(d.matches(s))
    }
  }
  assert_true(d.state_count() < 5000)
}
