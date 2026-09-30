///|
pub suberror LogitsError {
  InvalidLogits(String)
}

///|
pub impl Show for LogitsError with fn output(self, logger) {
  match self {
    InvalidLogits(message) => logger.write_string("invalid logits: " + message)
  }
}

///|
pub extend LogitsError with Show::{to_string, output}

///|
/// Highest-scoring allowed token; ties choose the lowest token id.
/// The input is not modified. NaN/+infinity, invalid states and vocabulary
/// dimensions are errors. -infinity suppresses a token; no eligible score
/// returns None. EOS is eligible only in an accepting state.
/// With `finish=true`, only strictly distance-decreasing tokens are considered,
/// or EOS alone if already accepting. This is an explicit completion policy,
/// not model-only greedy decoding, and may be stuck with a sparse vocabulary.
pub fn Guide::greedy(
  self : Guide,
  state : Int,
  logits : Array[Double],
  finish? : Bool = false,
) -> Int? raise LogitsError {
  if state < 0 || state >= self.dfa.state_count() {
    raise InvalidLogits("state is outside the DFA")
  }
  if logits.length() != self.vocab.size() {
    raise InvalidLogits("logits length must equal vocabulary size")
  }
  if self.vocab.eos < 0 || self.vocab.eos >= self.vocab.size() {
    raise InvalidLogits("EOS id is outside the vocabulary")
  }
  for score in logits {
    if score != score || score == @double.infinity {
      raise InvalidLogits("logits must be finite or negative infinity")
    }
  }
  let accept = self.is_accept(state)
  if finish && accept {
    return if logits[self.vocab.eos] == @double.neg_infinity {
      None
    } else {
      Some(self.vocab.eos)
    }
  }
  let mut best : Int? = None
  let mut best_score = @double.neg_infinity
  for id in self.allowed(state) {
    if finish && id != self.vocab.eos {
      let next = self.dfa.walk(state, self.vocab.tokens[id])
      if self.dfa.distance(next) >= self.dfa.distance(state) {
        continue
      }
    }
    let score = logits[id]
    if score == @double.neg_infinity {
      continue
    }
    if score > best_score ||
      (score == best_score && best is Some(old) && id < old) {
      best = Some(id)
      best_score = score
    }
  }
  best
}
