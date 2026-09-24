///|
priv struct Nfa {
  eps : Array[Array[Int]]
  moves : Array[Array[(ByteSet, Int)]]
  mut start : Int
  mut accept : Int
}

///|
let max_nfa_states : Int = 200_000

///|
fn Nfa::from_ast(ast : Ast) -> Nfa raise ParseError {
  let nfa : Nfa = { eps: [], moves: [], start: 0, accept: 0, }
  let (entry, exit) = nfa.build(ast)
  nfa.start = entry
  nfa.accept = exit
  nfa
}

///|
fn Nfa::add_state(self : Nfa) -> Int raise ParseError {
  if self.eps.length() >= max_nfa_states {
    raise ParseError(pos=0, msg="automaton too large")
  }
  self.eps.push([])
  self.moves.push([])
  self.eps.length() - 1
}

///|
/// Builds `ast` as a fragment reached by an ε edge from `from`; returns its exit.
fn Nfa::append(self : Nfa, from : Int, ast : Ast) -> Int raise ParseError {
  let (entry, exit) = self.build(ast)
  self.eps[from].push(entry)
  exit
}

///|
/// Returns the (entry, exit) of a fresh fragment. Callers only add edges into
/// an entry and out of an exit, which keeps nested repetitions sound.
fn Nfa::build(self : Nfa, ast : Ast) -> (Int, Int) raise ParseError {
  match ast {
    Empty => {
      let entry = self.add_state()
      let exit = self.add_state()
      self.eps[entry].push(exit)
      (entry, exit)
    }
    Set(bytes) => {
      let entry = self.add_state()
      let exit = self.add_state()
      self.moves[entry].push((bytes, exit))
      (entry, exit)
    }
    Concat(items) => {
      let entry = self.add_state()
      let mut exit = entry
      for item in items {
        exit = self.append(exit, item)
      }
      (entry, exit)
    }
    Alt(branches) => {
      let entry = self.add_state()
      let exit = self.add_state()
      for branch in branches {
        let (e, x) = self.build(branch)
        self.eps[entry].push(e)
        self.eps[x].push(exit)
      }
      (entry, exit)
    }
    JsonChars(pattern, min, max) => self.json_chars(pattern, min, max)
    Repeat(inner, min, max) => {
      let entry = self.add_state()
      let mut exit = entry
      for _ in 0..<min {
        exit = self.append(exit, inner)
      }
      match max {
        None => {
          let hub = self.add_state()
          self.eps[exit].push(hub)
          self.eps[self.append(hub, inner)].push(hub)
          exit = hub
        }
        Some(max) => {
          let end = self.add_state()
          for _ in min..<max {
            self.eps[exit].push(end)
            exit = self.append(exit, inner)
          }
          self.eps[exit].push(end)
          exit = end
        }
      }
      (entry, exit)
    }
  }
}
