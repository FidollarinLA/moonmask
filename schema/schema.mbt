///|
pub suberror SchemaError {
  Unsupported(String)
  Invalid(String)
}

///|
pub impl Show for SchemaError with fn output(self, logger) {
  match self {
    Unsupported(what) =>
      logger.write_string("unsupported JSON Schema feature: \{what}")
    Invalid(what) => logger.write_string("invalid JSON Schema: \{what}")
  }
}

///|
pub extend SchemaError with Show::{to_string}

///|
let string_char : String = @regex.json_unit()

///|
/// Up to 15 digits, so every accepted integer survives `json.parse` as an exact number.
let integer_re : String = "-?(?:0|[1-9][0-9]{0,14})"

///|
let fraction_exponent_re : String =
  #|(?:\.[0-9]{1,15})?(?:[eE][+-]?[0-9]{1,2})?

///|
pub fn to_regex(schema : Json) -> String raise SchemaError {
  gen(schema)
}

///|
pub fn compile(schema : Json) -> @regex.Dfa raise SchemaError {
  let pattern = to_regex(schema)
  try @regex.compile(pattern) catch {
    @regex.ParseError(msg~, ..) => raise Invalid(msg)
  } noraise {
    dfa => dfa
  }
}

///|
fn is_annotation(key : String) -> Bool {
  match key {
    "title"
    | "description"
    | "$schema"
    | "$id"
    | "$comment"
    | "examples"
    | "default" => true
    _ => false
  }
}

///|
fn is_known(key : String) -> Bool {
  if is_annotation(key) {
    return true
  }
  match key {
    "type"
    | "properties"
    | "required"
    | "additionalProperties"
    | "items"
    | "minItems"
    | "maxItems"
    | "minLength"
    | "maxLength"
    | "pattern"
    | "enum"
    | "const"
    | "anyOf"
    | "minimum"
    | "maximum"
    | "exclusiveMinimum"
    | "exclusiveMaximum" => true
    _ => false
  }
}

///|
fn escape(text : String) -> String {
  let buf = StringBuilder()
  for c in text {
    match c {
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
      | '$' => buf.write_char('\\')
      _ => ()
    }
    buf.write_char(c)
  }
  buf.to_string()
}

///|
fn alt(parts : Array[String]) -> String raise SchemaError {
  if parts.is_empty() {
    raise Invalid("empty alternative")
  }
  if parts.length() == 1 {
    return parts[0]
  }
  let buf = StringBuilder()
  buf.write_string("(?:")
  for i, part in parts {
    if i > 0 {
      buf.write_char('|')
    }
    buf.write_string(part)
  }
  buf.write_char(')')
  buf.to_string()
}

///|
fn bound_of(fields : Map[String, Json], key : String) -> Int? raise SchemaError {
  match fields.get(key) {
    None => None
    Some(Number(n, ..)) =>
      if n < 0.0 || n != n.floor() {
        raise Invalid(key)
      } else if n > 1000.0 {
        raise Unsupported(key)
      } else {
        Some(n.to_int())
      }
    Some(_) => raise Invalid(key)
  }
}

///|
fn matches_type(value : Json, ty : String) -> Bool {
  match (ty, value) {
    ("string", String(_)) => true
    ("integer", Number(n, ..)) => n == n.floor()
    ("number", Number(_)) => true
    ("boolean", True | False) => true
    ("null", Null) => true
    ("object", Object(_)) => true
    ("array", Array(_)) => true
    _ => false
  }
}

///|
fn matches_types(value : Json, types : Array[String]) -> Bool {
  types.iter().any(ty => matches_type(value, ty))
}

///|
fn literal(value : Json) -> String {
  escape(value.stringify())
}

///|
fn reject_foreign(
  fields : Map[String, Json],
  allowed : Array[String],
) -> Unit raise SchemaError {
  for key in fields.keys() {
    if is_annotation(key) {
      continue
    }
    if !allowed.contains(key) {
      raise Unsupported(key)
    }
  }
}

///|
fn gen(schema : Json) -> String raise SchemaError {
  guard schema is Object(fields) else { raise Unsupported("boolean schema") }
  for key in fields.keys() {
    if !is_known(key) {
      raise Unsupported(key)
    }
  }
  if fields.get("const") is Some(_) || fields.get("enum") is Some(_) {
    return gen_enum(fields)
  }
  if fields.get("anyOf") is Some(options) {
    reject_foreign(fields, ["anyOf"])
    guard options is Array(items) else { raise Invalid("anyOf") }
    let parts = []
    for item in items {
      parts.push(gen(item))
    }
    return alt(parts)
  }
  match fields.get("type") {
    None => raise Unsupported("schema without type")
    Some(Array(items)) => {
      let parts = []
      for item in items {
        guard item is String(ty) else { raise Invalid("type") }
        let kept : Array[(String, Json)] = []
        let allow = keys_for(ty)
        for key, value in fields {
          if allow.contains(key) {
            kept.push((key, value))
          }
        }
        parts.push(gen_typed(Map::from_array(kept), ty))
      }
      alt(parts)
    }
    Some(String(ty)) => gen_typed(fields, ty)
    Some(_) => raise Invalid("type")
  }
}

///|
fn gen_enum(fields : Map[String, Json]) -> String raise SchemaError {
  reject_foreign(fields, ["type", "const", "enum"])
  let types = match fields.get("type") {
    None => None
    Some(String(ty)) => Some([ty])
    Some(Array(items)) => {
      let names = []
      for item in items {
        guard item is String(ty) else { raise Invalid("type") }
        names.push(ty)
      }
      Some(names)
    }
    Some(_) => raise Invalid("type")
  }
  let values = match (fields.get("const"), fields.get("enum")) {
    (Some(_), Some(_)) => raise Unsupported("enum/const with other constraints")
    (Some(value), None) => [value]
    (None, Some(Array(items))) => items
    (None, Some(_)) => raise Invalid("enum")
    (None, None) => raise Invalid("enum")
  }
  let parts = []
  for value in values {
    if types is Some(types) && !matches_types(value, types) {
      continue
    }
    parts.push(literal(value))
  }
  if parts.is_empty() {
    raise Invalid("enum has no value of the declared type")
  }
  alt(parts)
}

///|
fn repeat_atom(
  atom : String,
  min : Int,
  max : Int?,
) -> String raise SchemaError {
  if min > 1000 {
    raise Unsupported("length bound")
  }
  match max {
    Some(max) =>
      if max > 1000 {
        raise Unsupported("length bound")
      } else if min > max {
        raise Invalid("minLength > maxLength")
      } else {
        atom + "{\{min},\{max}}"
      }
    None => if min == 0 { atom + "*" } else { atom + "{\{min},}" }
  }
}

///|
fn numeric_keys() -> Array[String] {
  ["type", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum"]
}

///|
fn keys_for(ty : String) -> Array[String] {
  match ty {
    "string" => ["type", "minLength", "maxLength", "pattern"]
    "integer" | "number" => numeric_keys()
    "object" => ["type", "properties", "required", "additionalProperties"]
    "array" => ["type", "items", "minItems", "maxItems"]
    _ => ["type"]
  }
}

///|
fn gen_string(fields : Map[String, Json]) -> String raise SchemaError {
  reject_foreign(fields, ["type", "minLength", "maxLength", "pattern"])
  let min = bound_of(fields, "minLength").unwrap_or(0)
  let max = bound_of(fields, "maxLength")
  let body = match fields.get("pattern") {
    None => repeat_atom(string_char, min, max)
    Some(String("")) => repeat_atom(string_char, min, max)
    Some(String(pattern)) => {
      let wrapped = try @regex.string_pattern(pattern) catch {
        @regex.ParseError(_) => raise Unsupported("pattern")
      } noraise {
        wrapped => wrapped
      }
      if min == 0 && max is None {
        "(?:" + string_char + ")*" + wrapped + "(?:" + string_char + ")*"
      } else if max is Some(bound) && min > bound {
        raise Invalid("minLength > maxLength")
      } else {
        let max_n = match max {
          None => -1
          Some(bound) => bound
        }
        let plen = pattern.to_array().length()
        "(?@\{min},\{max_n},\{plen}:\{pattern})"
      }
    }
    Some(_) => raise Invalid("pattern")
  }
  "\"" + body + "\""
}

///|
fn gen_typed(
  fields : Map[String, Json],
  ty : String,
) -> String raise SchemaError {
  match ty {
    "string" => gen_string(fields)
    "integer" => {
      reject_foreign(fields, numeric_keys())
      let (low, high) = read_ends(fields)
      match (low, high) {
        (None, None) => integer_re
        _ => integer_bounds_regex(low, high)
      }
    }
    "number" => {
      reject_foreign(fields, numeric_keys())
      let (low, high) = read_ends(fields)
      match (low, high) {
        (None, None) => integer_re + fraction_exponent_re
        _ => bounded_number(low, high)
      }
    }
    "boolean" => {
      reject_foreign(fields, ["type"])
      "(?:true|false)"
    }
    "null" => {
      reject_foreign(fields, ["type"])
      "null"
    }
    "object" => gen_object(fields)
    "array" => gen_array(fields)
    _ => raise Unsupported(ty)
  }
}

///|
fn gen_object(fields : Map[String, Json]) -> String raise SchemaError {
  reject_foreign(fields, [
    "type", "properties", "required", "additionalProperties",
  ])
  match fields.get("additionalProperties") {
    None | Some(True | False) => ()
    Some(_) => raise Unsupported("additionalProperties")
  }
  let props = match fields.get("properties") {
    None | Some(Object(_)) as found => found
    Some(_) => raise Invalid("properties")
  }
  if fields.get("required") is Some(Array(names)) {
    for name in names {
      guard name is String(key) else { raise Invalid("required") }
      let present = match props {
        Some(Object(props)) => props.get(key) is Some(_)
        _ => false
      }
      if !present {
        raise Invalid("required property is not declared")
      }
    }
  } else if fields.get("required") is Some(_) {
    raise Invalid("required")
  }
  let pieces = []
  if props is Some(Object(props)) {
    for key, child in props {
      pieces.push(escape(key.to_json().stringify()) + ":" + gen(child))
    }
  }
  if pieces.is_empty() {
    return "\\{\\}"
  }
  let buf = StringBuilder()
  buf.write_string("\\{")
  for i, piece in pieces {
    if i > 0 {
      buf.write_char(',')
    }
    buf.write_string(piece)
  }
  buf.write_string("\\}")
  buf.to_string()
}

///|
fn gen_array(fields : Map[String, Json]) -> String raise SchemaError {
  reject_foreign(fields, ["type", "items", "minItems", "maxItems"])
  guard fields.get("items") is Some(items) else {
    raise Unsupported("array without items")
  }
  let item = gen(items)
  let min = bound_of(fields, "minItems").unwrap_or(0)
  let max = bound_of(fields, "maxItems")
  if max is Some(max) && min > max {
    raise Invalid("minItems > maxItems")
  }
  if max is Some(0) {
    return "\\[\\]"
  }
  let extra = item + "(?:," + item + ")"
  if min == 0 {
    match max {
      None => "\\[(?:" + extra + "*)?\\]"
      Some(max) => "\\[(?:" + extra + "{0,\{max - 1}})?\\]"
    }
  } else {
    match max {
      None => "\\[" + extra + "{\{min - 1},}\\]"
      Some(max) => "\\[" + extra + "{\{min - 1},\{max - 1}}\\]"
    }
  }
}
