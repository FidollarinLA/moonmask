///|
let diff_patterns : Array[String] = [
  "abc", "a|b|c", "(?:ab|c)*", "a*b+c?", "[a-c]+x?", "[^abc]*", "x{2,4}", "(?:a|bc){1,3}d",
  "\\d+", "\\w*_", "\\s?a", "(?:0|[1-9][0-9]*)", "-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?",
  "(?:true|false|null)", "\\[(?:1(?:,1)*)?\\]", "\\{\"a\":(?:0|1)\\}", "a(?:b|)c",
  "(?:a*)*b", "(?:a?){3}", "[.]+", "a.c", "[a-]+", "[-a]b", "(?:ab){0,2}c?", "[0-9]{2,3}-[a-z]",
  "\"(?:[a-c]|\\\\n){0,3}\"", "(?:x|y|z){2}", "[^\\d]", "(?:\\.|,)+", "_*(?:-_)*",
]

///|
let diff_alphabet : Array[Char] = [
  'a', 'b', 'c', 'd', 'x', 'y', 'z', 'n', '0', '1', '9', '_', '-', '.', ',', ' ',
  '"', '\\', '[', ']', '{', '}', ':',
]

///|
test "differential: agrees with moonbitlang/regexp" {
  let rand = @random.Rand::chacha8(seed=b"moonmask-regex-diff-seed-0000000")
  let mut checks = 0
  for p in diff_patterns {
    let ours = @regex.compile(p)
    let oracle = @regexp.compile("^(?:" + p + ")$")
    for _ in 0..<300 {
      let buf = StringBuilder()
      for _ in 0..<rand.int(limit=9) {
        buf.write_char(diff_alphabet[rand.int(limit=diff_alphabet.length())])
      }
      let s = buf.to_string()
      if ours.accepts(s) != oracle.execute(s).matched() {
        fail("pattern \{p} disagrees on \{s}")
      }
      checks += 1
    }
    for _ in 0..<100 {
      if ours.sample(rand, max_len=16) is Some(bytes) {
        let s = @utf8.decode(bytes)
        if !oracle.execute(s).matched() {
          fail("pattern \{p}: oracle rejects sampled \{s}")
        }
        checks += 1
      }
    }
  }
  assert_true(checks >= 9000)
}
