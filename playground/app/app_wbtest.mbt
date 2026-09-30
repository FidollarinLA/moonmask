///|
test "every preset compiles and the masked monkey finishes it" {
  let lexicon = { id: 0, vocab: toy_vocab(), }
  for mode in [Schema, Regex, Grammar] {
    for p in presets(mode) {
      guard compile(mode, p.source, lexicon, 1) is Ok(e) else {
        fail("\{mode.label()} preset \{p.name} does not compile")
      }
      let b = run_bench(e, 64, 10)
      assert_eq(b.masked_valid, 10)
    }
  }
}

///|
test "stepping a run by hand ends in a valid output" {
  let m = init_model()
  let mut m = { ..m, run: fresh_run(9, true, 7, m.engine), }
  for _ in 0..<200 {
    m = m.step(None)
  }
  assert_true(m.run.outcome is Complete(true))
}

///|
test "without the mask a run breaks or stops early" {
  let m = init_model()
  let mut m = { ..m, run: fresh_run(9, false, 7, m.engine), }
  for _ in 0..<200 {
    m = m.step(None)
  }
  assert_true(m.run.outcome is (Broke | Cut | Complete(false)))
}

///|
test "byte set labels" {
  let set = Array::make(256, false)
  for b = 48; b < 58; b = b + 1 {
    set[b] = true
  }
  assert_eq(byte_set_label(set), "[0-9]")
  let quote = Array::make(256, false)
  quote[34] = true
  assert_eq(byte_set_label(quote), "\"")
  let most = Array::make(256, true)
  most[34] = false
  most[92] = false
  assert_eq(byte_set_label(most), "[^\"\\\\]")
}

///|
test "number formatting" {
  assert_eq(fixed(3.14159, 2), "3.14")
  assert_eq(fixed(0.05, 1), "0.1")
  assert_eq(fixed(12.0, 0), "12")
  assert_eq(with_commas(50257), "50,257")
  assert_eq(with_commas(999), "999")
}

///|
test "schema presets finish with whitespace and independent validation" {
  let lexicon = { id: 0, vocab: toy_vocab(), }
  for p in presets(Schema) {
    guard compile(Schema, p.source, lexicon, 1, whitespace=true) is Ok(e) else {
      fail("whitespace preset \{p.name} does not compile")
    }
    assert_eq(run_bench(e, 64, 10).masked_valid, 10)
  }
}

///|
test "whitespace rebuild resets decoding and benchmark with mode preserved" {
  let m = init_model().step(None)
  let m = { ..m, whitespace: true, playing: true, }.rebuild()
  assert_true(m.whitespace)
  assert_false(m.playing)
  assert_true(m.bench is None)
  assert_eq(m.run.tokens.length(), 0)
  guard m.engine is Ok(e) else { fail("rebuild failed") }
  assert_true(e.guide.allowed(e.guide.start()).contains(token_for_space(e)))
  let mut m = { ..m, budget: 0, }
  for _ in 0..<200 {
    m = m.step(None)
  }
  assert_true(m.run.outcome is Complete(true))
  let compact = { ..m, whitespace: false, }.rebuild()
  guard compact.engine is Ok(e) else { fail("compact rebuild failed") }
  assert_false(e.guide.allowed(e.guide.start()).contains(token_for_space(e)))
}

///|
fn token_for_space(e : Engine) -> Int {
  for i, bytes in e.guide.vocab.tokens {
    if bytes == b" " {
      return i
    }
  }
  abort("missing space")
}

///|
test "editing immediately pauses the old engine until rebuild" {
  let m = { ..init_model().step(None), playing: true, }
  let edited = m.edit("{")
  assert_false(edited.playing)
  assert_true(edited.engine is Err(_))
  assert_true(edited.bench is None)
  assert_eq(edited.edits, m.edits + 1)
  let stopped = edited.step(None)
  assert_eq(stopped.run.tokens.length(), m.run.tokens.length())
  assert_true(edited.rebuild().engine is Err(_))
  let fixed = edited.edit(schema_presets[0].source).rebuild()
  assert_true(fixed.engine is Ok(_))
  assert_eq(fixed.run.tokens.length(), 0)
}

///|
test "restarting pauses playback and keeps the requested seed and mask" {
  let m = { ..init_model().step(None), playing: true, }
  let restarted = m.restart(masked=false, seed=123)
  assert_false(restarted.playing)
  assert_false(restarted.run.masked)
  assert_eq(restarted.run.seed, 123)
  assert_eq(restarted.run.tokens.length(), 0)
}

///|
test "JSON whitespace setting does not affect regex or grammar" {
  for mode in [Regex, Grammar] {
    let source = presets(mode)[0].source
    let (a, _, _) = build_dfa(mode, source)
    let (b, _, _) = build_dfa(mode, source, whitespace=true)
    assert_eq(a.state_count(), b.state_count())
    for text in ["", " ", "abc", "\n"] {
      assert_eq(a.accepts(text), b.accepts(text))
    }
  }
}
