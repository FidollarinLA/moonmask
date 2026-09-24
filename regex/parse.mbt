///|
pub suberror ParseError {
  ParseError(pos~ : Int, msg~ : String)
}

///|
pub impl Show for ParseError with fn output(self, logger) {
  match self {
    ParseError(pos~, msg~) =>
      logger.write_string("regex error at \{pos}: \{msg}")
  }
}

///|
pub extend ParseError with Show::{to_string}

///|
priv enum Ast {
  Empty
  Set(ByteSet)
  Concat(Array[Ast])
  Alt(Array[Ast])
  Repeat(Ast, Int, Int?)
  /// Pattern plus decoded-character bounds. `max` is `None` when unbounded.
  JsonChars(String, Int, Int?)
}

///|
let max_repeat : Int = 1000

///|
priv struct Parser {
  chars : Array[Char]
  mut pos : Int
}

///|
/// A class member: a single byte (usable as a range endpoint) or a shorthand set.
priv enum ClassItem {
  One(Int)
  Many(ByteSet)
}

///|
fn ClassItem::to_set(self : ClassItem) -> ByteSet {
  match self {
    One(b) => ByteSet::of_range(b, b)
    Many(set) => set
  }
}

///|
fn parse(pattern : String) -> Ast raise ParseError {
  let p : Parser = { chars: pattern.to_array(), pos: 0, }
  let ast = p.alt()
  if p.pos < p.chars.length() {
    p.fail("unbalanced )")
  }
  ast
}

///|
fn Parser::peek(self : Parser) -> Char? {
  self.chars.get(self.pos)
}

///|
fn[T] Parser::fail(self : Parser, msg : String) -> T raise ParseError {
  raise ParseError(pos=self.pos, msg~)
}

///|
fn Parser::alt(self : Parser) -> Ast raise ParseError {
  let branches = [self.concat()]
  while self.peek() is Some('|') {
    self.pos += 1
    branches.push(self.concat())
  }
  if branches.length() == 1 {
    branches[0]
  } else {
    Alt(branches)
  }
}

///|
fn Parser::concat(self : Parser) -> Ast raise ParseError {
  let items = []
  while self.peek() is Some(c) && c != '|' && c != ')' {
    items.push(self.repeat())
  }
  match items.length() {
    0 => Empty
    1 => items[0]
    _ => Concat(items)
  }
}

///|
fn Parser::repeat(self : Parser) -> Ast raise ParseError {
  let mut ast = self.atom()
  while self.quantifier() is Some((min, max)) {
    ast = Repeat(ast, min, max)
  }
  ast
}

///|
fn Parser::quantifier(self : Parser) -> (Int, Int?)? raise ParseError {
  let bounds = match self.peek() {
    Some('*') => (0, None)
    Some('+') => (1, None)
    Some('?') => (0, Some(1))
    Some('{') => return Some(self.braces())
    _ => return None
  }
  self.pos += 1
  Some(bounds)
}

///|
fn Parser::braces(self : Parser) -> (Int, Int?) raise ParseError {
  let open = self.pos
  self.pos += 1
  let min = self.bound()
  let max = if self.peek() is Some(',') {
    self.pos += 1
    if self.peek() is Some('}') {
      None
    } else {
      Some(self.bound())
    }
  } else {
    Some(min)
  }
  if !(self.peek() is Some('}')) {
    self.fail("expected } to close the quantifier")
  }
  self.pos += 1
  if max is Some(max) && min > max {
    raise ParseError(pos=open, msg="quantifier {\{min},\{max}} has min > max")
  }
  (min, max)
}

///|
fn Parser::bound(self : Parser) -> Int raise ParseError {
  let start = self.pos
  let mut n = 0
  while self.peek() is Some(c) && c >= '0' && c <= '9' {
    if n <= max_repeat {
      n = n * 10 + (c.to_int() - '0'.to_int())
    }
    self.pos += 1
  }
  if self.pos == start {
    self.fail("expected a number in the quantifier")
  }
  if n > max_repeat {
    raise ParseError(pos=start, msg="repetition bound exceeds \{max_repeat}")
  }
  n
}

///|
fn Parser::atom(self : Parser) -> Ast raise ParseError {
  match self.peek() {
    Some('(') => self.group()
    Some('[') => self.class()
    Some('.') => {
      // Match moonbitlang/regexp: '.' skips U+000A through U+0010, not only LF.
      self.pos += 1
      let set = ByteSet::of_range(0, '\t'.to_int())
      set.add_all(ByteSet::of_range('\u{11}'.to_int(), 0x7F))
      Set(set)
    }
    Some('\\') => Set(self.escape().to_set())
    Some('^' | '$') =>
      self.fail(
        "anchors are not supported: patterns always match the whole output",
      )
    Some('*' | '+' | '?' | '{') => self.fail("nothing to repeat")
    Some(c) => {
      self.pos += 1
      let code = c.to_int()
      if code < 0x80 {
        Set(ByteSet::of_range(code, code))
      } else {
        Concat(
          @utf8.encode(c.to_string())
          .iter()
          .map(b => Set(ByteSet::of_range(b.to_int(), b.to_int())))
          .collect(),
        )
      }
    }
    None => self.fail("unexpected end of pattern")
  }
}

///|
fn Parser::group(self : Parser) -> Ast raise ParseError {
  self.pos += 1
  if self.peek() is Some('?') {
    self.pos += 1
    match self.peek() {
      Some(':') => self.pos += 1
      Some('@') => return self.json_chars()
      _ => self.fail("only (?:...) groups are supported")
    }
  }
  let inner = self.alt()
  if !(self.peek() is Some(')')) {
    self.fail("missing )")
  }
  self.pos += 1
  inner
}

///|
fn Parser::read_int(self : Parser) -> Int raise ParseError {
  let mut sign = 1
  if self.peek() is Some('-') {
    sign = -1
    self.pos += 1
  }
  let mut n = 0
  let mut digits = 0
  while self.peek() is Some(c) && c >= '0' && c <= '9' {
    n = n * 10 + (c.to_int() - '0'.to_int())
    digits += 1
    self.pos += 1
  }
  if digits == 0 {
    self.fail("expected a number")
  }
  n * sign
}

///|
/// `(?@min,max,len:pattern)` where `max` is `-1` when there is no maximum.
fn Parser::json_chars(self : Parser) -> Ast raise ParseError {
  self.pos += 1
  let min = self.read_int()
  if !(self.peek() is Some(',')) {
    self.fail("expected ,")
  }
  self.pos += 1
  let max_n = self.read_int()
  if !(self.peek() is Some(',')) {
    self.fail("expected ,")
  }
  self.pos += 1
  let plen = self.read_int()
  if !(self.peek() is Some(':')) {
    self.fail("expected :")
  }
  self.pos += 1
  if plen < 0 || self.pos + plen > self.chars.length() {
    self.fail("pattern length exceeds the group")
  }
  let buf = StringBuilder()
  for _ in 0..<plen {
    buf.write_char(self.chars[self.pos])
    self.pos += 1
  }
  if !(self.peek() is Some(')')) {
    self.fail("missing )")
  }
  self.pos += 1
  let max = if max_n < 0 { None } else { Some(max_n) }
  JsonChars(buf.to_string(), min, max)
}

///|
fn Parser::class(self : Parser) -> Ast raise ParseError {
  self.pos += 1
  let negated = self.peek() is Some('^')
  if negated {
    self.pos += 1
  }
  if self.peek() is Some(']') {
    self.fail("empty character class (write \\] for a literal ])")
  }
  let set = ByteSet::empty()
  while !(self.peek() is Some(']')) {
    let item_pos = self.pos
    let lo = self.class_item()
    if self.peek() is Some('-') &&
      self.chars.get(self.pos + 1) is Some(next) &&
      next != ']' {
      self.pos += 1
      match (lo, self.class_item()) {
        (One(lo), One(hi)) => {
          if lo > hi {
            raise ParseError(pos=item_pos, msg="reversed range in class")
          }
          set.add_all(ByteSet::of_range(lo, hi))
        }
        _ =>
          raise ParseError(
            pos=item_pos,
            msg="class shorthands cannot be range endpoints",
          )
      }
    } else {
      set.add_all(lo.to_set())
    }
  }
  self.pos += 1
  Set(if negated { set.ascii_complement() } else { set })
}

///|
fn Parser::class_item(self : Parser) -> ClassItem raise ParseError {
  match self.peek() {
    None => self.fail("missing ]")
    Some('\\') => self.escape()
    Some(c) => {
      if c.to_int() >= 0x80 {
        self.fail("non-ASCII characters are not supported in classes")
      }
      self.pos += 1
      One(c.to_int())
    }
  }
}

///|
fn Parser::escape(self : Parser) -> ClassItem raise ParseError {
  let start = self.pos
  self.pos += 1
  guard self.peek() is Some(c) else {
    raise ParseError(pos=start, msg="trailing backslash")
  }
  self.pos += 1
  match c {
    'd' => Many(ByteSet::of_range('0'.to_int(), '9'.to_int()))
    'w' => {
      let set = ByteSet::of_range('a'.to_int(), 'z'.to_int())
      set.add_all(ByteSet::of_range('A'.to_int(), 'Z'.to_int()))
      set.add_all(ByteSet::of_range('0'.to_int(), '9'.to_int()))
      set.add_all(ByteSet::of_range('_'.to_int(), '_'.to_int()))
      Many(set)
    }
    's' => {
      let set = ByteSet::of_range('\t'.to_int(), '\r'.to_int())
      set.add_all(ByteSet::of_range(' '.to_int(), ' '.to_int()))
      Many(set)
    }
    'n' => One('\n'.to_int())
    't' => One('\t'.to_int())
    'r' => One('\r'.to_int())
    '\\'
    | '.'
    | '*'
    | '+'
    | '?'
    | '('
    | ')'
    | '['
    | ']'
    | '{'
    | '}'
    | '|'
    | '^'
    | '$'
    | '/'
    | '-'
    | '"' => One(c.to_int())
    _ => raise ParseError(pos=start, msg="unsupported escape \\\{c}")
  }
}
