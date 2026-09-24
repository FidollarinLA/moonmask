///|
fn[T] raises(f : () -> T raise) -> Bool {
  try f() catch {
    _ => true
  } noraise {
    _ => false
  }
}

///|
test "gpt2 byte-level strings decode to raw bytes" {
  assert_eq(@vocab.gpt2_token_bytes("Ġthe"), Some(b" the"))
  assert_eq(@vocab.gpt2_token_bytes("Ċ"), Some(b"\n"))
  assert_eq(@vocab.gpt2_token_bytes("abc"), Some(b"abc"))
  assert_eq(@vocab.gpt2_token_bytes("▁x"), None)
}

///|
test "every byte round-trips through the gpt2 alphabet" {
  for b in 0..<256 {
    let c = @vocab.gpt2_byte_to_char(b.to_byte())
    assert_eq(
      @vocab.gpt2_token_bytes(c.to_string()),
      Some(Bytes::make(1, b.to_byte())),
    )
  }
}

///|
let tiny_tokenizer_json : String =
  #|{"version":"1.0","truncation":null,"padding":null,
  #|"added_tokens":[{"id":2,"content":"<|endoftext|>","single_word":false,"lstrip":false,"rstrip":false,"normalized":false,"special":true}],
  #|"normalizer":null,"pre_tokenizer":null,"post_processor":null,"decoder":null,
  #|"model":{"type":"WordLevel","vocab":{"a":0,"Ġb":1,"<|endoftext|>":2},"unk_token":"a"}}

///|
test "from_tokenizer keeps ids and blanks out special tokens" {
  let tok = @tokenizer.from_buffer(@utf8.encode(tiny_tokenizer_json))
  let v = @vocab.from_tokenizer(tok, eos_token="<|endoftext|>")
  assert_eq(v.size(), 3)
  assert_eq(v.eos, 2)
  assert_eq(v.tokens[0], b"a")
  assert_eq(v.tokens[1], b" b")
  assert_eq(v.tokens[2], b"")
}

///|
test "non byte-level vocabularies and a missing eos are rejected" {
  let sentencepiece =
    #|{"version":"1.0","truncation":null,"padding":null,"added_tokens":[],
    #|"normalizer":null,"pre_tokenizer":null,"post_processor":null,"decoder":null,
    #|"model":{"type":"WordLevel","vocab":{"▁a":0,"b":1},"unk_token":"b"}}
  let sp = @tokenizer.from_buffer(@utf8.encode(sentencepiece))
  assert_true(raises(() => @vocab.from_tokenizer(sp, eos_token="b")))
  let ok = @tokenizer.from_buffer(@utf8.encode(tiny_tokenizer_json))
  assert_true(raises(() => @vocab.from_tokenizer(ok, eos_token="<|none|>")))
}
