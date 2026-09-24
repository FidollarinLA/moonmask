///|
fn[T] raises(f : () -> T raise) -> Bool {
  try f() catch {
    _ => true
  } noraise {
    _ => false
  }
}

///|
fn both(grammar : String, text : String, want : Bool) -> Unit raise {
  let bytes = @utf8.encode(text)
  let dfa = @gbnf.compile(grammar)
  assert_eq(dfa.matches(bytes), want)
  assert_eq(@gbnf.accepts(grammar, bytes), want)
}

///|
test "literals choices groups and quantifiers agree with the interpreter" {
  both("root ::= \"ab\"", "ab", true)
  both("root ::= \"ab\"", "a", false)
  both("root ::= \"a\" | \"ab\"", "ab", true)
  both("root ::= \"a\" | \"ab\"", "b", false)
  both("root ::= (\"xy\" | \"z\"){1,2}", "xyz", true)
  both("root ::= (\"xy\" | \"z\"){1,2}", "xyxyxy", false)
  both("root ::= \"a\"? \"b\"* \"c\"", "c", true)
  both("root ::= \"a\"? \"b\"* \"c\"", "abbbc", true)
  both("root ::= \"a\"? \"b\"* \"c\"", "ab", false)
  both("root ::= \"\" | \"ok\"", "", true)
  both("root ::= \"say \\\"hi\\\"\"", "say \"hi\"", true)
  both("root ::= \"\\n\"", "\n", true)
}

///|
test "rules inline until a cycle" {
  both("item ::= \"0\" | \"1\"\nroot ::= item+", "0110", false)
  // The first rule is the start rule.
  both("root ::= item+\nitem ::= \"0\" | \"1\"", "0110", true)
  both("root ::= item+\nitem ::= \"0\" | \"1\"", "", false)
  assert_true(raises(() => @gbnf.compile("root ::= \"a\" root | \"b\"")))
  assert_true(raises(() => @gbnf.compile("a ::= b\nb ::= a | \"z\"")))
  assert_true(raises(() => @gbnf.compile("root ::= missing")))
  assert_true(raises(() => @gbnf.compile("root ::= [abc]")))
  assert_true(raises(() => @gbnf.compile("root ::= \"a\"\nroot ::= \"b\"")))
}

///|
test "sampled strings from fixed grammars pass the interpreter" {
  let grammars = [
    "root ::= \"ab\" | \"a\"+", "root ::= (\"xy\" | \"z\"){0,3}", "root ::= item+\nitem ::= \"0\" | \"1\"",
    "# comment\nroot ::= \"a\"? \"b\"* \"c\"", "root ::= word (\" \" word)*\nword ::= \"x\" | \"yy\"",
  ]
  let rand = @random.Rand::chacha8(seed=b"moonmask-gbnf-diff-seed-00000000")
  for grammar in grammars {
    let dfa = @gbnf.compile(grammar)
    let mut produced = 0
    for _ in 0..<30 {
      match dfa.sample(rand, max_len=16) {
        None => ()
        Some(text) => {
          produced += 1
          assert_true(@gbnf.accepts(grammar, text))
        }
      }
    }
    assert_true(produced > 10)
  }
}
