///|
pub struct Vocab {
  tokens : Array[Bytes]
  eos : Int
}

///|
pub fn Vocab::new(tokens : Array[Bytes], eos~ : Int) -> Vocab {
  { tokens, eos, }
}

///|
pub fn Vocab::size(self : Vocab) -> Int {
  self.tokens.length()
}

///|
pub suberror VocabError {
  NotByteLevel(id~ : Int, token~ : String)
  MissingEos(String)
}

///|
pub impl Show for VocabError with fn output(self, logger) {
  match self {
    NotByteLevel(id~, token~) =>
      logger.write_string(
        "token \{id} (\{token}) is not a GPT-2 byte-level token",
      )
    MissingEos(name) => logger.write_string("eos token \{name} not found")
  }
}

///|
pub extend VocabError with Show::{to_string}

///|
pub fn from_tokenizer(
  tok : @tokenizer.Tokenizer,
  eos_token~ : String,
) -> Vocab raise VocabError {
  guard tok.convert_token_to_id(eos_token) is Some(eos) else {
    raise MissingEos(eos_token)
  }
  let special = tok.all_special_ids()
  let tokens : Array[Bytes] = []
  for id in 0..<tok.get_vocab_size() {
    if special.contains(id) {
      tokens.push(b"")
      continue
    }
    guard tok.id_to_token(id) is Some(text) else {
      tokens.push(b"")
      continue
    }
    guard gpt2_token_bytes(text) is Some(bytes) else {
      raise NotByteLevel(id~, token=text)
    }
    tokens.push(bytes)
  }
  { tokens, eos, }
}
