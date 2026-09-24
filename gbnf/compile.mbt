///|
fn resolve(rules : Array[(String, Expr)]) -> Expr raise GrammarError {
  if rules.length() == 0 {
    raise GrammarError(pos=0, msg="grammar is empty")
  }
  let (start, _) = rules[0]
  let stack : Array[String] = []
  resolve_ref(rules, start, stack)
}

///|
fn resolve_ref(
  rules : Array[(String, Expr)],
  name : String,
  stack : Array[String],
) -> Expr raise GrammarError {
  if stack.contains(name) {
    raise GrammarError(pos=0, msg="recursive rule \{name}")
  }
  let mut found : Expr? = None
  for rule in rules {
    let (rule_name, body) = rule
    if rule_name == name {
      found = Some(body)
    }
  }
  guard found is Some(body) else {
    raise GrammarError(pos=0, msg="undefined rule \{name}")
  }
  stack.push(name)
  let resolved = resolve_expr(rules, body, stack)
  let _ = stack.pop()
  resolved
}

///|
fn resolve_expr(
  rules : Array[(String, Expr)],
  expr : Expr,
  stack : Array[String],
) -> Expr raise GrammarError {
  match expr {
    Lit(_) | Class(_) => expr
    Ref(name) => resolve_ref(rules, name, stack)
    Alt(branches) => {
      let resolved : Array[Expr] = []
      for branch in branches {
        resolved.push(resolve_expr(rules, branch, stack))
      }
      Alt(resolved)
    }
    Cat(items) => {
      let resolved : Array[Expr] = []
      for item in items {
        resolved.push(resolve_expr(rules, item, stack))
      }
      Cat(resolved)
    }
    Repeat(inner, min, max) =>
      Repeat(resolve_expr(rules, inner, stack), min, max)
  }
}

///|
fn emit(expr : Expr) -> String raise GrammarError {
  match expr {
    Ref(_) => raise GrammarError(pos=0, msg="unresolved rule")
    Lit(bytes) => emit_lit(bytes)
    Class(bits) => emit_class(bits)
    Cat(items) => {
      let buf = StringBuilder()
      for item in items {
        buf.write_string(emit_piece(item))
      }
      buf.to_string()
    }
    Alt(branches) => {
      let buf = StringBuilder()
      buf.write_string("(?:")
      for i, branch in branches {
        if i > 0 {
          buf.write_string("|")
        }
        buf.write_string(emit_piece(branch))
      }
      buf.write_string(")")
      buf.to_string()
    }
    Repeat(inner, min, max) => emit_piece(inner) + quantifier(min, max)
  }
}

///|
fn emit_piece(expr : Expr) -> String raise GrammarError {
  let text = emit(expr)
  if text.length() == 0 {
    "(?:)"
  } else {
    match expr {
      Lit(_) => text
      _ => "(?:" + text + ")"
    }
  }
}

///|
fn quantifier(min : Int, max : Int?) -> String {
  match (min, max) {
    (0, None) => "*"
    (1, None) => "+"
    (0, Some(1)) => "?"
    (n, Some(m)) => if n == m { "{\{n}}" } else { "{\{n},\{m}}" }
    (n, None) => "{\{n},}"
  }
}

///|
fn emit_lit(bytes : Bytes) -> String {
  let buf = StringBuilder()
  for b in bytes {
    let n = b.to_int()
    if n == '\n'.to_int() {
      buf.write_string("\\n")
    } else if n == '\r'.to_int() {
      buf.write_string("\\r")
    } else if n == '\t'.to_int() {
      buf.write_string("\\t")
    } else if n == '\\'.to_int() ||
      n == '.'.to_int() ||
      n == '*'.to_int() ||
      n == '+'.to_int() ||
      n == '?'.to_int() ||
      n == '('.to_int() ||
      n == ')'.to_int() ||
      n == '['.to_int() ||
      n == ']'.to_int() ||
      n == '{'.to_int() ||
      n == '}'.to_int() ||
      n == '|'.to_int() ||
      n == '^'.to_int() ||
      n == '$'.to_int() {
      buf.write_char('\\')
      buf.write_char(n.unsafe_to_char())
    } else if n >= 32 && n < 127 {
      buf.write_char(n.unsafe_to_char())
    } else {
      buf.write_string("\\x")
      buf.write_char(hex_digit(n / 16))
      buf.write_char(hex_digit(n % 16))
    }
  }
  buf.to_string()
}

///|
fn emit_class(bits : FixedArray[Bool]) -> String {
  let buf = StringBuilder()
  let mut first = true
  for b in 0..<256 {
    if bits[b] {
      if !first {
        buf.write_string("|")
      }
      first = false
      buf.write_string(emit_lit(Bytes::make(1, b.to_byte())))
    }
  }
  buf.to_string()
}

///|
fn hex_digit(n : Int) -> Char {
  if n < 10 {
    (48 + n).unsafe_to_char()
  } else {
    (87 + n).unsafe_to_char()
  }
}

///|
pub fn compile(grammar : String) -> @regex.Dfa raise GrammarError {
  let pattern = emit(resolve(parse_grammar(grammar)))
  try @regex.compile(pattern) catch {
    @regex.ParseError(msg~, ..) => raise GrammarError(pos=0, msg~)
  } noraise {
    dfa => dfa
  }
}

///|
/// Backtracking matcher for the same non-recursive grammar `compile` lowers.
pub fn accepts(grammar : String, text : Bytes) -> Bool raise GrammarError {
  let expr = resolve(parse_grammar(grammar))
  ends(expr, text, 0).contains(text.length())
}

///|
fn has_prefix(input : Bytes, at : Int, lit : Bytes) -> Bool {
  if at + lit.length() > input.length() {
    return false
  }
  for j in 0..<lit.length() {
    if input[at + j] != lit[j] {
      return false
    }
  }
  true
}

///|
fn push_unique(out : Array[Int], value : Int) -> Unit {
  if !out.contains(value) {
    out.push(value)
  }
}

///|
fn ends(expr : Expr, input : Bytes, at : Int) -> Array[Int] {
  match expr {
    Lit(lit) =>
      if has_prefix(input, at, lit) {
        [at + lit.length()]
      } else {
        []
      }
    Class(bits) =>
      if at < input.length() && bits[input[at].to_int()] {
        [at + 1]
      } else {
        []
      }
    Ref(_) => []
    Cat(items) => {
      let mut positions = [at]
      for item in items {
        let next : Array[Int] = []
        for pos in positions {
          for reached in ends(item, input, pos) {
            push_unique(next, reached)
          }
        }
        positions = next
      }
      positions
    }
    Alt(branches) => {
      let out : Array[Int] = []
      for branch in branches {
        for reached in ends(branch, input, at) {
          push_unique(out, reached)
        }
      }
      out
    }
    Repeat(inner, min, max) => repeat_ends(inner, min, max, input, at)
  }
}

///|
fn repeat_ends(
  inner : Expr,
  min : Int,
  max : Int?,
  input : Bytes,
  at : Int,
) -> Array[Int] {
  let cap = match max {
    Some(m) => m
    None => input.length() + 1
  }
  let acc : Array[Int] = []
  if min == 0 {
    acc.push(at)
  }
  let mut prev = [at]
  let mut count = 0
  while count < cap {
    let next : Array[Int] = []
    let mut saw_empty = false
    for pos in prev {
      for reached in ends(inner, input, pos) {
        if reached == pos {
          saw_empty = true
        } else {
          push_unique(next, reached)
        }
      }
    }
    count += 1
    if count >= min {
      if saw_empty {
        for pos in prev {
          push_unique(acc, pos)
        }
      }
      for pos in next {
        push_unique(acc, pos)
      }
    }
    if next.length() == 0 {
      if saw_empty {
        let mut more = count
        while more < cap {
          more += 1
          if more >= min {
            for pos in prev {
              push_unique(acc, pos)
            }
          }
        }
      }
      break
    }
    prev = next
  }
  acc
}
