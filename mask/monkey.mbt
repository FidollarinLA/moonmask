///|
pub(all) struct Sampled {
  tokens : Array[Int]
  text : Bytes
  finished : Bool
} derive(Debug)

///|
/// Uniformly random tokens under the mask. After `max_tokens`, only tokens that
/// move strictly closer to an accepting state are chosen, so the output always
/// terminates when the vocabulary contains every single-byte token.
pub fn monkey(g : Guide, rand : @random.Rand, max_tokens~ : Int) -> Sampled {
  let tokens : Array[Int] = []
  let text : Array[Byte] = []
  let hard_cap = max_tokens * 4 + 64
  let mut state = g.start()
  while tokens.length() < hard_cap {
    let trans = g.transitions(state)
    let accept = g.is_accept(state)
    let over_budget = tokens.length() >= max_tokens
    if over_budget && accept {
      tokens.push(g.vocab.eos)
      return { tokens, text: Bytes::from_array(text), finished: true, }
    }
    let candidates = if over_budget {
      let here = g.dfa.distance(state)
      trans.filter(p => g.dfa.distance(p.1) < here)
    } else {
      trans
    }
    let n = candidates.length() + (if accept && !over_budget { 1 } else { 0 })
    if n == 0 {
      return { tokens, text: Bytes::from_array(text), finished: false, }
    }
    let k = rand.int(limit=n)
    if k == candidates.length() {
      tokens.push(g.vocab.eos)
      return { tokens, text: Bytes::from_array(text), finished: true, }
    }
    let (id, next) = candidates[k]
    tokens.push(id)
    for b in g.vocab.tokens[id] {
      text.push(b)
    }
    state = next
  }
  { tokens, text: Bytes::from_array(text), finished: false, }
}

///|
/// Baseline without the mask: uniformly random token ids until eos or the budget.
pub fn monkey_unmasked(
  v : @vocab.Vocab,
  rand : @random.Rand,
  max_tokens~ : Int,
) -> Sampled {
  let tokens : Array[Int] = []
  let text : Array[Byte] = []
  while tokens.length() < max_tokens {
    let id = rand.int(limit=v.size())
    tokens.push(id)
    if id == v.eos {
      return { tokens, text: Bytes::from_array(text), finished: true, }
    }
    for b in v.tokens[id] {
      text.push(b)
    }
  }
  { tokens, text: Bytes::from_array(text), finished: false, }
}
