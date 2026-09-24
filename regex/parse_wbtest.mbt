///|
fn parse_error_pos(pattern : String) -> Int? {
  try parse(pattern) catch {
    ParseError(pos~, ..) => Some(pos)
  } noraise {
    _ => None
  }
}

///|
test "parse builds the expected shapes" {
  assert_true(parse("abc") is Concat([Set(_), Set(_), Set(_)]))
  assert_true(parse("a|") is Alt([Set(_), Empty]))
  assert_true(parse("(?:a)") is Set(_))
  assert_true(parse("a*") is Repeat(Set(_), 0, None))
  assert_true(parse("a+") is Repeat(Set(_), 1, None))
  assert_true(parse("a?") is Repeat(Set(_), 0, Some(1)))
  assert_true(parse("a{2}") is Repeat(Set(_), 2, Some(2)))
  assert_true(parse("a{2,}") is Repeat(Set(_), 2, None))
  assert_true(parse("a{2,5}") is Repeat(Set(_), 2, Some(5)))
  assert_true(parse("月") is Concat([Set(_), Set(_), Set(_)]))
  assert_true(parse("😀") is Concat([Set(_), Set(_), Set(_), Set(_)]))
  assert_true(parse("") is Empty)
}

///|
test "parse builds the expected byte sets" {
  guard parse("[a-c0-9_]") is Set(set) else { fail("expected a set") }
  assert_true(set.contains('b'.to_int()))
  assert_true(set.contains('5'.to_int()))
  assert_true(set.contains('_'.to_int()))
  assert_false(set.contains('d'.to_int()))
  guard parse("[^\"\\\\]") is Set(neg) else { fail("expected a set") }
  assert_true(neg.contains('a'.to_int()))
  assert_false(neg.contains('"'.to_int()))
  assert_false(neg.contains('\\'.to_int()))
  assert_false(neg.contains(0x80))
  guard parse(".") is Set(dot) else { fail("expected a set") }
  assert_true(dot.contains(0))
  assert_false(dot.contains('\n'.to_int()))
  assert_false(dot.contains(0x80))
  guard parse("[-a-]") is Set(dashes) else { fail("expected a set") }
  assert_true(dashes.contains('-'.to_int()))
  assert_true(dashes.contains('a'.to_int()))
  guard parse("\\s") is Set(space) else { fail("expected a set") }
  for c in [' ', '\t', '\n', '\r', '\u{0b}', '\u{0c}'] {
    assert_true(space.contains(c.to_int()))
  }
}

///|
test "parse errors render position and message" {
  try parse("(ab") catch {
    err => inspect(err, content="regex error at 3: missing )")
  } noraise {
    _ => fail("expected a parse error")
  }
}

///|
test "parse reports error positions" {
  assert_eq(parse_error_pos("(ab"), Some(3))
  assert_eq(parse_error_pos("ab)"), Some(2))
  assert_eq(parse_error_pos("a{3,1}"), Some(1))
  assert_eq(parse_error_pos("a{2000}"), Some(2))
  assert_eq(parse_error_pos("a{99999999999}"), Some(2))
  assert_eq(parse_error_pos("a{2"), Some(3))
  assert_eq(parse_error_pos("a{,2}"), Some(2))
  assert_eq(parse_error_pos("[z-a]"), Some(1))
  assert_eq(parse_error_pos("[\\d-z]"), Some(1))
  assert_eq(parse_error_pos("[é]"), Some(1))
  assert_eq(parse_error_pos("[ab"), Some(3))
  assert_eq(parse_error_pos("[]"), Some(1))
  assert_eq(parse_error_pos("^a"), Some(0))
  assert_eq(parse_error_pos("a$"), Some(1))
  assert_eq(parse_error_pos("\\q"), Some(0))
  assert_eq(parse_error_pos("a\\"), Some(1))
  assert_eq(parse_error_pos("*a"), Some(0))
  assert_eq(parse_error_pos("(*)"), Some(1))
  assert_eq(parse_error_pos("a|+"), Some(2))
  assert_eq(parse_error_pos("(?=a)"), Some(2))
  assert_eq(parse_error_pos("a**"), None)
}
