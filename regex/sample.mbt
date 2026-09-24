///|
pub fn Dfa::sample(self : Dfa, rand : @random.Rand, max_len~ : Int) -> Bytes? {
  let out : Array[Byte] = []
  let mut state = self.start
  while out.length() <= max_len {
    let options : Array[Int] = []
    for b in 0..<256 {
      if self.trans[state][b] >= 0 {
        options.push(b)
      }
    }
    let n = options.length() + (if self.accept[state] { 1 } else { 0 })
    if n == 0 {
      return None
    }
    let k = rand.int(limit=n)
    if k == options.length() {
      return Some(Bytes::from_array(out))
    }
    out.push(options[k].to_byte())
    state = self.trans[state][options[k]]
  }
  None
}
