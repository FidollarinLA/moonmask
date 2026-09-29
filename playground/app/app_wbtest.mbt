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
