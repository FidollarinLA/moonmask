///|
pub struct Dfa {
  start : Int
  priv trans : Array[FixedArray[Int]]
  priv accept : Array[Bool]
  priv dist : Array[Int]
}

///|
/// A length bound of 1000 crossed with one UTF-8 sequence is tens of thousands of
/// states. The cap stays finite so a pathological pattern still fails loudly.
let max_dfa_states : Int = 100_000

///|
/// Distance of the single state of an empty-language DFA; large but safe to add to.
let no_accepting_path : Int = 1 << 30

///|
pub fn compile(pattern : String) -> Dfa raise ParseError {
  Dfa::from_nfa(Nfa::from_ast(parse(pattern)))
}

///|
fn Dfa::from_nfa(nfa : Nfa) -> Dfa raise ParseError {
  let (start, trans, accept) = nfa.determinize()
  prune(start, trans, accept)
}

///|
/// Partitions bytes into classes that no move distinguishes, numbered in order
/// of their smallest byte.
fn Nfa::byte_classes(self : Nfa) -> FixedArray[Int] {
  let classes = FixedArray::make(256, 0)
  let remap = FixedArray::make(512, -1)
  for edges in self.moves {
    for edge in edges {
      let (bytes, _) = edge
      remap.fill(-1)
      let mut count = 0
      for b in 0..<256 {
        let key = classes[b] * 2 + (if bytes.contains(b) { 1 } else { 0 })
        if remap[key] < 0 {
          remap[key] = count
          count += 1
        }
        classes[b] = remap[key]
      }
    }
  }
  classes
}

///|
/// Subset construction. A DFA state is keyed by the sorted NFA states of its
/// ε-closure that have byte moves or accept; the others cannot affect matching.
fn Nfa::determinize(
  self : Nfa,
) -> (Int, Array[FixedArray[Int]], Array[Bool]) raise ParseError {
  let classes = self.byte_classes()
  let reps : Array[Int] = []
  for b in 0..<256 {
    if classes[b] == reps.length() {
      reps.push(b)
    }
  }
  let mark = FixedArray::make(self.eps.length(), -1)
  let mut stamp = 0
  let stack : Array[Int] = []
  fn closure(seeds : Array[Int]) -> Array[Int] {
    stamp += 1
    for s in seeds {
      if mark[s] != stamp {
        mark[s] = stamp
        stack.push(s)
      }
    }
    let states = []
    while stack.pop() is Some(s) {
      if s == self.accept || !self.moves[s].is_empty() {
        states.push(s)
      }
      for t in self.eps[s] {
        if mark[t] != stamp {
          mark[t] = stamp
          stack.push(t)
        }
      }
    }
    states.sort()
    states
  }

  let ids : Map[Array[Int], Int] = Map([])
  let sets : Array[Array[Int]] = []
  fn intern(states : Array[Int]) -> Int raise ParseError {
    if ids.get(states) is Some(id) {
      return id
    }
    if sets.length() >= max_dfa_states {
      raise ParseError(pos=0, msg="automaton too large")
    }
    ids[states] = sets.length()
    sets.push(states)
    sets.length() - 1
  }

  let start = intern(closure([self.start]))
  let targets : Map[Array[Int], Int] = Map([])
  let trans : Array[FixedArray[Int]] = []
  let accept : Array[Bool] = []
  while trans.length() < sets.length() {
    let states = sets[trans.length()]
    let next = FixedArray::make(reps.length(), -1)
    for c, b in reps {
      let key = []
      for s in states {
        for edge in self.moves[s] {
          let (bytes, target) = edge
          if bytes.contains(b) {
            key.push(target)
          }
        }
      }
      if key.is_empty() {
        continue
      }
      key.sort()
      key.dedup()
      next[c] = match targets.get(key) {
        Some(id) => id
        None => {
          let id = intern(closure(key))
          targets[key] = id
          id
        }
      }
    }
    trans.push(FixedArray::makei(256, b => next[classes[b]]))
    accept.push(states.contains(self.accept))
  }
  (start, trans, accept)
}

///|
/// Drops states that cannot reach acceptance and renumbers the rest; `dist` is
/// the BFS depth from the accepting states over reversed transitions.
fn prune(
  start : Int,
  trans : Array[FixedArray[Int]],
  accept : Array[Bool],
) -> Dfa {
  let n = trans.length()
  let preds : Array[Array[Int]] = Array::makei(n, _ => [])
  let last_pred = FixedArray::make(n, -1)
  for s, row in trans {
    for t in row {
      if t >= 0 && last_pred[t] != s {
        last_pred[t] = s
        preds[t].push(s)
      }
    }
  }
  let dist = FixedArray::make(n, -1)
  let queue = []
  for s in 0..<n {
    if accept[s] {
      dist[s] = 0
      queue.push(s)
    }
  }
  let mut head = 0
  while head < queue.length() {
    let t = queue[head]
    head += 1
    for s in preds[t] {
      if dist[s] < 0 {
        dist[s] = dist[t] + 1
        queue.push(s)
      }
    }
  }
  if dist[start] < 0 {
    return {
      start: 0,
      trans: [FixedArray::make(256, -1)],
      accept: [false],
      dist: [no_accepting_path],
    }
  }
  let renumber = FixedArray::make(n, -1)
  let mut live = 0
  for s in 0..<n {
    if dist[s] >= 0 {
      renumber[s] = live
      live += 1
    }
  }
  let dfa : Dfa = { start: renumber[start], trans: [], accept: [], dist: [], }
  for s in 0..<n {
    if dist[s] >= 0 {
      let row = trans[s]
      dfa.trans.push(
        FixedArray::makei(256, b => {
          if row[b] < 0 {
            -1
          } else {
            renumber[row[b]]
          }
        }),
      )
      dfa.accept.push(accept[s])
      dfa.dist.push(dist[s])
    }
  }
  dfa
}

///|
pub fn Dfa::step(self : Dfa, state : Int, b : Byte) -> Int {
  if state < 0 {
    return -1
  }
  self.trans[state][b.to_int()]
}

///|
pub fn Dfa::walk(self : Dfa, state : Int, bytes : Bytes) -> Int {
  let mut s = state
  for b in bytes {
    s = self.step(s, b)
    if s < 0 {
      return -1
    }
  }
  s
}

///|
pub fn Dfa::is_accept(self : Dfa, state : Int) -> Bool {
  state >= 0 && self.accept[state]
}

///|
pub fn Dfa::matches(self : Dfa, bytes : Bytes) -> Bool {
  self.is_accept(self.walk(self.start, bytes))
}

///|
pub fn Dfa::accepts(self : Dfa, text : String) -> Bool {
  self.matches(@utf8.encode(text))
}

///|
/// Shortest number of bytes from `state` to an accepting state.
pub fn Dfa::distance(self : Dfa, state : Int) -> Int {
  self.dist[state]
}

///|
pub fn Dfa::state_count(self : Dfa) -> Int {
  self.trans.length()
}
