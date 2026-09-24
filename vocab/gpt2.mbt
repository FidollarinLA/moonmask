///|
fn gpt2_is_printable(b : Int) -> Bool {
  (b >= 33 && b <= 126) || (b >= 161 && b <= 172) || (b >= 174 && b <= 255)
}

///|
let gpt2_forward : FixedArray[Char] = {
  let table = FixedArray::make(256, ' ')
  let mut n = 0
  for b in 0..<256 {
    if gpt2_is_printable(b) {
      table[b] = b.unsafe_to_char()
    } else {
      table[b] = (256 + n).unsafe_to_char()
      n += 1
    }
  }
  table
}

///|
let gpt2_backward : Map[Char, Byte] = {
  let entries : Array[(Char, Byte)] = []
  for b in 0..<256 {
    entries.push((gpt2_forward[b], b.to_byte()))
  }
  Map::from_array(entries)
}

///|
pub fn gpt2_byte_to_char(b : Byte) -> Char {
  gpt2_forward[b.to_int()]
}

///|
/// Decodes a GPT-2 byte-level token string. Returns `None` when a character is
/// outside that alphabet.
pub fn gpt2_token_bytes(token : String) -> Bytes? {
  let out : Array[Byte] = []
  for c in token {
    match gpt2_backward.get(c) {
      Some(b) => out.push(b)
      None => return None
    }
  }
  Some(Bytes::from_array(out))
}
