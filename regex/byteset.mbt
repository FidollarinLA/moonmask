///|
priv struct ByteSet {
  bits : FixedArray[Bool]
}

///|
fn ByteSet::empty() -> ByteSet {
  { bits: FixedArray::make(256, false), }
}

///|
fn ByteSet::of_range(lo : Int, hi : Int) -> ByteSet {
  let s = ByteSet::empty()
  for b in lo..<=hi {
    s.bits[b] = true
  }
  s
}

///|
fn ByteSet::contains(self : ByteSet, b : Int) -> Bool {
  self.bits[b]
}

///|
/// Bytes that JSON writes as themselves inside a string: printable ASCII except `"` and `\`.
fn ByteSet::json_literal_bytes(self : ByteSet) -> Bool {
  for b in 0..<256 {
    if self.bits[b] && (b < 0x20 || b > 0x7E || b == 0x22 || b == 0x5C) {
      return false
    }
  }
  true
}

///|
fn ByteSet::add_all(self : ByteSet, other : ByteSet) -> Unit {
  for b in 0..<256 {
    if other.bits[b] {
      self.bits[b] = true
    }
  }
}

///|
/// Complement within ASCII only, so negated classes never emit bytes >= 0x80.
fn ByteSet::ascii_complement(self : ByteSet) -> ByteSet {
  let s = ByteSet::empty()
  for b in 0..<128 {
    s.bits[b] = !self.bits[b]
  }
  s
}
