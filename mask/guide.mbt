///|
pub struct Guide {
  dfa : @regex.Dfa
  vocab : @vocab.Vocab
  cache : Map[Int, Array[(Int, Int)]]
}

///|
pub fn Guide::new(dfa : @regex.Dfa, vocab : @vocab.Vocab) -> Guide {
  { dfa, vocab, cache: Map::from_array([]), }
}

///|
pub fn Guide::start(self : Guide) -> Int {
  self.dfa.start
}

///|
pub fn Guide::is_accept(self : Guide, state : Int) -> Bool {
  self.dfa.is_accept(state)
}

///|
/// Every non-eos token that keeps the output completable, paired with the next state.
pub fn Guide::transitions(self : Guide, state : Int) -> Array[(Int, Int)] {
  match self.cache.get(state) {
    Some(t) => t
    None => {
      let t : Array[(Int, Int)] = []
      for id in 0..<self.vocab.size() {
        let bytes = self.vocab.tokens[id]
        if id == self.vocab.eos || bytes.length() == 0 {
          continue
        }
        let next = self.dfa.walk(state, bytes)
        if next >= 0 {
          t.push((id, next))
        }
      }
      self.cache[state] = t
      t
    }
  }
}

///|
pub fn Guide::allowed(self : Guide, state : Int) -> Array[Int] {
  let ids = self.transitions(state).map(p => p.0)
  if self.is_accept(state) {
    ids.push(self.vocab.eos)
  }
  ids
}

///|
pub fn Guide::advance(self : Guide, state : Int, token : Int) -> Int? {
  if token == self.vocab.eos || self.vocab.tokens[token].length() == 0 {
    return None
  }
  let next = self.dfa.walk(state, self.vocab.tokens[token])
  if next >= 0 {
    Some(next)
  } else {
    None
  }
}
