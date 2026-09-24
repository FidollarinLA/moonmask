///|
fn[T] raises(f : () -> T raise) -> Bool {
  try f() catch {
    _ => true
  } noraise {
    _ => false
  }
}

///|
test "literals and concatenation" {
  let d = @regex.compile("abc")
  assert_true(d.accepts("abc"))
  assert_false(d.accepts("ab"))
  assert_false(d.accepts("abcd"))
}

///|
test "alternation, groups and empty branches" {
  let d = @regex.compile("(?:ab|c)d")
  assert_true(d.accepts("abd"))
  assert_true(d.accepts("cd"))
  assert_false(d.accepts("abcd"))
  let e = @regex.compile("a(b|)c")
  assert_true(e.accepts("ac"))
  assert_true(e.accepts("abc"))
}

///|
test "quantifiers" {
  let d = @regex.compile("a*b+c?")
  assert_true(d.accepts("b"))
  assert_true(d.accepts("aabbc"))
  assert_false(d.accepts("ac"))
  let bounded = @regex.compile("x{2,3}")
  assert_false(bounded.accepts("x"))
  assert_true(bounded.accepts("xx"))
  assert_true(bounded.accepts("xxx"))
  assert_false(bounded.accepts("xxxx"))
  let exact = @regex.compile("y{2}")
  assert_true(exact.accepts("yy"))
  assert_false(exact.accepts("yyy"))
  let open = @regex.compile("z{2,}")
  assert_true(open.accepts("zzzzz"))
  assert_false(open.accepts("z"))
}

///|
test "classes, negation and escapes" {
  let d = @regex.compile("[a-c0-9_]+")
  assert_true(d.accepts("a9_c"))
  assert_false(d.accepts("d"))
  let neg = @regex.compile(
    (
      #|[^"\\]*
    ),
  )
  assert_true(neg.accepts("hello world"))
  assert_false(neg.accepts("a\"b"))
  let esc = @regex.compile(
    (
      #|\{\}\[\]\.\|\*
    ),
  )
  assert_true(esc.accepts("{}[].|*"))
  let short = @regex.compile(
    (
      #|\d\w\s[\d-]
    ),
  )
  assert_true(short.accepts("7z -"))
  assert_true(short.accepts("7z 5"))
}

///|
test "dot matches any ascii byte except newline" {
  let d = @regex.compile("a.c")
  assert_true(d.accepts("a-c"))
  assert_false(d.accepts("a\nc"))
  assert_false(d.accepts("a\rc"))
  assert_false(d.accepts("a月c"))
}

///|
test "non-ascii literals are matched as utf-8 bytes" {
  let d = @regex.compile("月+")
  assert_true(d.accepts("月月"))
  assert_false(d.accepts("日"))
}

///|
test "parse errors carry the position" {
  try @regex.compile("(ab") catch {
    @regex.ParseError(pos~, ..) => assert_eq(pos, 3)
  } noraise {
    _ => fail("expected a parse error")
  }
  assert_true(raises(() => @regex.compile("a{3,1}")))
  assert_true(raises(() => @regex.compile("[z-a]")))
  assert_true(raises(() => @regex.compile("[é]")))
  assert_true(raises(() => @regex.compile("^a$")))
  assert_true(raises(() => @regex.compile("a{2000}")))
  assert_true(raises(() => @regex.compile("\\q")))
  assert_true(raises(() => @regex.compile("*a")))
}

///|
test "dead states are pruned" {
  let d = @regex.compile("ab|ac")
  let a = d.step(d.start, b'a')
  assert_true(a >= 0)
  assert_eq(d.step(a, b'x'), -1)
  assert_true(d.is_accept(d.step(a, b'b')))
  assert_eq(d.walk(d.start, b"ax"), -1)
}

///|
test "distance counts bytes to the nearest accepting state" {
  let d = @regex.compile("abc|x")
  assert_eq(d.distance(d.start), 1)
  assert_eq(d.distance(d.step(d.start, b'a')), 2)
}

///|
test "unicode escapes are four hex digits or a surrogate pair" {
  let unit = @regex.compile(@regex.json_unit())
  assert_true(unit.accepts("\\u0061"))
  assert_true(unit.accepts("\\u4E2D"))
  assert_true(unit.accepts("\\uD83D\\uDE00"))
  assert_false(unit.accepts("\\uD800"))
  assert_false(unit.accepts("\\uDE00"))
  assert_false(unit.accepts("\\u12"))
  assert_false(unit.accepts("\\u006G"))
  assert_false(unit.accepts("\\u{0061}"))
  assert_false(unit.accepts("\\uD800\\uD800"))
}

///|
test "hex escapes are bytes and utf-8 sequences stay well formed" {
  let d = @regex.compile("\\x61\\x62")
  assert_true(d.accepts("ab"))
  assert_false(d.accepts("a"))
  let unit = @regex.compile(@regex.json_unit())
  assert_true(unit.accepts("é"))
  assert_true(unit.accepts("中"))
  assert_true(unit.accepts("😀"))
  assert_false(unit.accepts("ab"))
  assert_false(unit.matches(Bytes::from_array([0x80])))
  assert_false(unit.matches(Bytes::from_array([0xC0, 0x80])))
  assert_false(unit.matches(Bytes::from_array([0xED, 0xA0, 0x80])))
  assert_false(unit.matches(Bytes::from_array([0xC2])))
}

///|
test "length-bounded json characters keep pattern overlaps" {
  let d = @regex.compile("\"(?@4,4,3:aab)\"")
  assert_true(d.accepts("\"aaab\""))
  assert_false(d.accepts("\"aaaa\""))
  assert_false(d.accepts("\"aab\""))
  let escaped = @regex.compile("\"(?@2,2,1:a)\"")
  assert_true(escaped.accepts("\"\\na\""))
  assert_false(escaped.accepts("\"\\n\\n\""))
  assert_false(escaped.accepts("\"a\""))
}

///|
test "string patterns keep only raw JSON bytes" {
  assert_eq(@regex.string_pattern("a+"), "(?:a+)")
  assert_eq(@regex.string_pattern("[0-9]{2}"), "(?:[0-9]{2})")
  assert_true(raises(() => @regex.string_pattern(".")))
  assert_true(raises(() => @regex.string_pattern("\\s")))
  assert_true(raises(() => @regex.string_pattern("\\n")))
  assert_true(raises(() => @regex.string_pattern("[^a]")))
}

///|
test "sampling only yields accepted strings" {
  let d = @regex.compile("(?:ab|c)+d?")
  let rand = @random.Rand::chacha8(seed=b"moonmask-regex-sample-seed-00000")
  let mut produced = 0
  for _ in 0..<200 {
    if d.sample(rand, max_len=20) is Some(s) {
      assert_true(d.matches(s))
      produced += 1
    }
  }
  assert_true(produced > 100)
}
