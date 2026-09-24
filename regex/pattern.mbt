///|
fn check_pattern(ast : Ast) -> Unit raise ParseError {
  match ast {
    Empty => ()
    Set(set) =>
      if !set.json_literal_bytes() {
        raise ParseError(
          pos=0,
          msg="pattern contains a byte that is not a raw JSON string character",
        )
      }
    Concat(items) | Alt(items) =>
      for item in items {
        check_pattern(item)
      }
    Repeat(inner, _, _) => check_pattern(inner)
    JsonChars(_) => raise ParseError(pos=0, msg="unsupported pattern syntax")
  }
}

///|
/// Returns `pattern` grouped, after rejecting matches that are not raw JSON string bytes.
pub fn string_pattern(pattern : String) -> String raise ParseError {
  check_pattern(parse(pattern))
  "(?:" + pattern + ")"
}

///|
/// One decoded JSON string character: a raw byte, or a two-byte escape.
let json_char : String =
  #|(?:[ !#-\[\]-~]|\\["\\/bfnrt])

///|
fn json_alphabet() -> ByteSet {
  let set = ByteSet::empty()
  for b in 0x20..<=0x7E {
    if b != 0x22 && b != 0x5C {
      set.add_byte(b)
    }
  }
  set
}

///|
fn byte_set_of(bytes : Array[Int]) -> ByteSet {
  let set = ByteSet::empty()
  for b in bytes {
    set.add_byte(b)
  }
  set
}

///|
/// Unanchored search over the pattern alphabet. Accepting states stay accepting,
/// so a later character does not erase a match that already happened.
fn search_dfa(pattern : String) -> Dfa raise ParseError {
  check_pattern(parse(pattern))
  let nfa = Nfa::from_ast(parse(pattern))
  let old_start = nfa.start
  let old_accept = nfa.accept
  let skip = nfa.add_state()
  let sink = nfa.add_state()
  let alphabet = json_alphabet()
  nfa.moves[skip].push((alphabet, skip))
  nfa.moves[sink].push((alphabet, sink))
  nfa.eps[skip].push(old_start)
  nfa.eps[old_accept].push(sink)
  nfa.start = skip
  nfa.accept = sink
  Dfa::from_nfa(nfa)
}

///|
fn Nfa::move_literals(self : Nfa, from : Int, to : (Int) -> Int) -> Unit {
  let dests : Array[Int] = []
  let groups : Array[Array[Int]] = []
  for b in 0x20..<=0x7E {
    if b == 0x22 || b == 0x5C {
      continue
    }
    let dest = to(b)
    let mut found = -1
    for i, existing in dests {
      if existing == dest {
        found = i
      }
    }
    if found < 0 {
      dests.push(dest)
      groups.push([b])
    } else {
      groups[found].push(b)
    }
  }
  for i, dest in dests {
    self.moves[from].push((byte_set_of(groups[i]), dest))
  }
}

///|
/// `(?@min,max,len:pattern)` counts decoded characters. `\` starts an escape and
/// does not increment the length; the second byte does. `\/` is the character `/`.
fn Nfa::json_chars(
  self : Nfa,
  pattern : String,
  min : Int,
  max : Int?,
) -> (Int, Int) raise ParseError {
  let search = search_dfa(pattern)
  if search.is_accept(search.start) {
    return self.build(Repeat(parse(json_char), min, max))
  }
  let scount = search.state_count()
  let last = match max {
    None => min
    Some(bound) => bound
  }
  let layers = last + 1
  let boundary : Array[Int] = []
  let escaping : Array[Int] = []
  for _ in 0..<(layers * scount) {
    boundary.push(self.add_state())
    escaping.push(self.add_state())
  }
  let exit = self.add_state()
  let backslash = byte_set_of([0x5C])
  let slash = byte_set_of(['/'.to_int()])
  let hidden = byte_set_of([
    0x22,
    0x5C,
    'b'.to_int(),
    'f'.to_int(),
    'n'.to_int(),
    'r'.to_int(),
    't'.to_int(),
  ])
  fn at(i : Int, p : Int) -> Int {
    i * scount + p
  }

  fn advance(p : Int, b : Int) -> Int {
    let t = search.step(p, b.to_byte())
    if t >= 0 {
      t
    } else {
      search.start
    }
  }

  for i in 0..<=last {
    for p in 0..<scount {
      let from = boundary[at(i, p)]
      if i >= min && search.is_accept(p) {
        self.eps[from].push(exit)
      }
      let next = match max {
        None => if i < min { Some(i + 1) } else { Some(i) }
        Some(bound) => if i < bound { Some(i + 1) } else { None }
      }
      guard next is Some(next_i) else { continue }
      self.move_literals(from, b => boundary[at(next_i, advance(p, b))])
      let mid = escaping[at(i, p)]
      self.moves[from].push((backslash, mid))
      let reset = if search.is_accept(p) { p } else { search.start }
      self.moves[mid].push((hidden, boundary[at(next_i, reset)]))
      self.moves[mid].push(
        (slash, boundary[at(next_i, advance(p, '/'.to_int()))]),
      )
    }
  }
  (boundary[at(0, search.start)], exit)
}
