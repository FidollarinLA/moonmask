///|
/// A deterministic integration example: no model or tokenizer download.
fn main raise {
  let schema : Json = { "enum": ["ok"] }
  let dfa = @schema.compile(schema)
  assert_true(dfa.accepts("\"ok\""))
  assert_false(dfa.accepts("\"no\""))
  let vocab = @vocab.Vocab::new([b"\"ok\"", b"\"no\"", b""], eos=2)
  let guide = @mask.Guide::new(dfa, vocab)
  let start = guide.start()
  // The illegal token has the highest score, but the guide excludes it.
  let token = guide.greedy(start, [0.0, 100.0, 0.0])
  assert_eq(token, Some(0))
  guard guide.advance(start, 0) is Some(next) else {
    abort("expected a legal transition")
  }
  assert_true(guide.is_accept(next))
  assert_eq(guide.greedy(next, [0.0, 100.0, 0.0]), Some(vocab.eos))
  println("\"ok\"")
  println(
    "PASS: illegal high-score token blocked; EOS selected only after acceptance.",
  )
}
