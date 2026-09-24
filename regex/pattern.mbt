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
  }
}

///|
/// Returns `pattern` grouped, after rejecting matches that are not raw JSON string bytes.
pub fn string_pattern(pattern : String) -> String raise ParseError {
  check_pattern(parse(pattern))
  "(?:" + pattern + ")"
}
