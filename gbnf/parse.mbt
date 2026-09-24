///|
pub suberror GrammarError {
  GrammarError(pos~ : Int, msg~ : String)
}

///|
pub impl Show for GrammarError with fn output(self, logger) {
  match self {
    GrammarError(pos~, msg~) =>
      logger.write_string("grammar error at \{pos}: \{msg}")
  }
}

///|
pub extend GrammarError with Show::{output, to_string}

///|
priv enum Expr {
  Lit(Bytes)
  Alt(Array[Expr])
  Cat(Array[Expr])
  Repeat(Expr, Int, Int?)
  Ref(String)
}

///|
priv struct Parser {
  chars : Array[Char]
  mut pos : Int
}

///|
let max_repeat : Int = 1000

///|
fn parse_grammar(src : String) -> Array[(String, Expr)] raise GrammarError {
  let p : Parser = { chars: src.to_array(), pos: 0, }
  let rules : Array[(String, Expr)] = []
  p.skip()
  if p.peek() is None {
    p.fail("grammar is empty")
  }
  while p.peek() is Some(_) {
    let name = p.ident()
    p.skip()
    if !(p.chars.get(p.pos) is Some(':') &&
      p.chars.get(p.pos + 1) is Some(':') &&
      p.chars.get(p.pos + 2) is Some('=')) {
      p.fail("expected ::=")
    }
    p.pos += 3
    let body = p.alt()
    for rule in rules {
      let (prev, _) = rule
      if prev == name {
        p.fail("duplicate rule \{name}")
      }
    }
    rules.push((name, body))
    p.skip()
  }
  rules
}

///|
fn Parser::peek(self : Parser) -> Char? {
  self.chars.get(self.pos)
}

///|
fn[T] Parser::fail(self : Parser, msg : String) -> T raise GrammarError {
  raise GrammarError(pos=self.pos, msg~)
}

///|
fn Parser::skip(self : Parser) -> Unit {
  let mut moving = true
  while moving {
    match self.peek() {
      Some(' ' | '\t' | '\r' | '\n') => self.pos += 1
      Some('#') => {
        self.pos += 1
        let mut in_comment = true
        while in_comment {
          match self.peek() {
            Some('\n') | None => in_comment = false
            _ => self.pos += 1
          }
        }
      }
      _ => moving = false
    }
  }
}

///|
fn is_name_start(c : Char) -> Bool {
  (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_'
}

///|
fn is_name_cont(c : Char) -> Bool {
  is_name_start(c) || (c >= '0' && c <= '9') || c == '-'
}

///|
fn Parser::ident(self : Parser) -> String raise GrammarError {
  self.skip()
  guard self.peek() is Some(c) && is_name_start(c) else {
    self.fail("expected a rule name")
  }
  let buf = StringBuilder()
  while self.peek() is Some(c) && is_name_cont(c) {
    buf.write_char(c)
    self.pos += 1
  }
  buf.to_string()
}

///|
/// True when the next tokens are `name ::=`, without consuming them.
fn Parser::starts_rule(self : Parser) -> Bool {
  let saved = self.pos
  self.skip()
  let mut yes = false
  if self.peek() is Some(c) && is_name_start(c) {
    self.pos += 1
    let mut more = true
    while more {
      match self.peek() {
        Some(c) if is_name_cont(c) => self.pos += 1
        _ => more = false
      }
    }
    self.skip()
    yes = self.chars.get(self.pos) is Some(':') &&
      self.chars.get(self.pos + 1) is Some(':') &&
      self.chars.get(self.pos + 2) is Some('=')
  }
  self.pos = saved
  yes
}

///|
fn Parser::alt(self : Parser) -> Expr raise GrammarError {
  let branches = [self.seq()]
  let mut more = true
  while more {
    self.skip()
    if self.peek() is Some('|') {
      self.pos += 1
      branches.push(self.seq())
    } else {
      more = false
    }
  }
  if branches.length() == 1 {
    branches[0]
  } else {
    Alt(branches)
  }
}

///|
fn Parser::seq(self : Parser) -> Expr raise GrammarError {
  let items : Array[Expr] = []
  let mut more = true
  while more {
    self.skip()
    if self.starts_atom() && !self.starts_rule() {
      items.push(self.repeat())
    } else {
      more = false
    }
  }
  if items.length() == 0 {
    self.fail("expected an expression")
  }
  if items.length() == 1 {
    items[0]
  } else {
    Cat(items)
  }
}

///|
fn Parser::starts_atom(self : Parser) -> Bool {
  match self.peek() {
    Some('"' | '(') => true
    Some(c) => is_name_start(c)
    None => false
  }
}

///|
fn Parser::repeat(self : Parser) -> Expr raise GrammarError {
  let mut expr = self.atom()
  let mut more = true
  while more {
    self.skip()
    match self.peek() {
      Some('*') => {
        self.pos += 1
        expr = Repeat(expr, 0, None)
      }
      Some('+') => {
        self.pos += 1
        expr = Repeat(expr, 1, None)
      }
      Some('?') => {
        self.pos += 1
        expr = Repeat(expr, 0, Some(1))
      }
      Some('{') => {
        let (min, max) = self.braces()
        expr = Repeat(expr, min, max)
      }
      _ => more = false
    }
  }
  expr
}

///|
fn Parser::braces(self : Parser) -> (Int, Int?) raise GrammarError {
  let open = self.pos
  self.pos += 1
  self.skip()
  let min = self.bound()
  self.skip()
  let max = if self.peek() is Some(',') {
    self.pos += 1
    self.skip()
    if self.peek() is Some('}') {
      None
    } else {
      Some(self.bound())
    }
  } else {
    Some(min)
  }
  self.skip()
  if !(self.peek() is Some('}')) {
    self.fail("expected } to close the quantifier")
  }
  self.pos += 1
  if max is Some(max) && min > max {
    raise GrammarError(pos=open, msg="quantifier has min > max")
  }
  (min, max)
}

///|
fn Parser::bound(self : Parser) -> Int raise GrammarError {
  let start = self.pos
  let mut n = 0
  let mut digits = false
  while self.peek() is Some(c) && c >= '0' && c <= '9' {
    digits = true
    if n <= max_repeat {
      n = n * 10 + (c.to_int() - '0'.to_int())
    }
    self.pos += 1
  }
  if !digits {
    self.fail("expected a number in the quantifier")
  }
  if n > max_repeat {
    raise GrammarError(pos=start, msg="repetition bound exceeds \{max_repeat}")
  }
  n
}

///|
fn Parser::atom(self : Parser) -> Expr raise GrammarError {
  self.skip()
  match self.peek() {
    Some('"') => Lit(self.string())
    Some('(') => {
      self.pos += 1
      let inner = self.alt()
      self.skip()
      if !(self.peek() is Some(')')) {
        self.fail("missing )")
      }
      self.pos += 1
      inner
    }
    Some('[') => self.fail("character classes are not supported")
    Some(c) if is_name_start(c) => Ref(self.ident())
    _ => self.fail("expected an expression")
  }
}

///|
fn Parser::string(self : Parser) -> Bytes raise GrammarError {
  self.pos += 1
  let raw : Array[Byte] = []
  let mut closed = false
  while !closed {
    match self.peek() {
      None => self.fail("unterminated string")
      Some('"') => {
        self.pos += 1
        closed = true
      }
      Some('\\') => {
        let start = self.pos
        self.pos += 1
        match self.peek() {
          Some('n') => raw.push('\n'.to_int().to_byte())
          Some('r') => raw.push('\r'.to_int().to_byte())
          Some('t') => raw.push('\t'.to_int().to_byte())
          Some('\\') => raw.push('\\'.to_int().to_byte())
          Some('"') => raw.push('"'.to_int().to_byte())
          Some(_) =>
            raise GrammarError(pos=start, msg="unsupported string escape")
          None => self.fail("unterminated string")
        }
        self.pos += 1
      }
      Some(c) => {
        for b in @utf8.encode(c.to_string()) {
          raw.push(b)
        }
        self.pos += 1
      }
    }
  }
  Bytes::from_array(raw)
}
