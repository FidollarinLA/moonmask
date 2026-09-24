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
    | "exclusiveMaximum"
    | "$ref" => true
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
fn read_defs(fields : Map[String, Json]) -> Map[String, Json] raise SchemaError {
  match fields.get("$defs") {
    None => Map::from_array([])
    Some(Object(defs)) => defs
    Some(_) => raise Invalid("$defs")
  }
}

///|
fn drop_defs(fields : Map[String, Json]) -> Map[String, Json] {
  let kept : Array[(String, Json)] = []
  for key, value in fields {
    if key != "$defs" {
      kept.push((key, value))
    }
  }
  Map::from_array(kept)
}

///|
fn push_ref(stack : Array[String], name : String) -> Array[String] {
  let next = []
  for item in stack {
    next.push(item)
  }
  next.push(name)
  next
}

///|
/// `#/$defs/<token>`, one JSON Pointer segment. `~0` is `~` and `~1` is `/`.
fn ref_name(target : String) -> String raise SchemaError {
  let prefix = "#/$defs/".to_array()
  let chars = target.to_array()
  if chars.length() <= prefix.length() {
    raise Unsupported("$ref")
  }
  for i, c in prefix {
    if chars[i] != c {
      raise Unsupported("$ref")
    }
  }
  let buf = StringBuilder()
  let mut i = prefix.length()
  while i < chars.length() {
    let c = chars[i]
    if c == '/' {
      raise Unsupported("$ref")
    } else if c == '~' {
      if i + 1 >= chars.length() {
        raise Unsupported("$ref")
      }
      match chars[i + 1] {
        '0' => buf.write_char('~')
        '1' => buf.write_char('/')
        _ => raise Unsupported("$ref")
      }
      i += 2
    } else {
      buf.write_char(c)
      i += 1
    }
  }
  let name = buf.to_string()
  if name.length() == 0 {
    raise Unsupported("$ref")
  }
  name
}

///|
fn gen(schema : Json) -> String raise SchemaError {
  guard schema is Object(fields) else { raise Unsupported("boolean schema") }
  let defs = read_defs(fields)
  for name, body in defs {
    let _ = expand(body, defs, [name])
  }
  expand_fields(drop_defs(fields), defs, [])
}

///|
/// `type`, `enum`, and `const` beside `$ref` narrow the referenced schema.
/// Any other sibling keyword is rejected. A sibling that cannot overlap the
/// reference is rejected rather than ignored.
fn ref_siblings(
  fields : Map[String, Json],
) -> (Json?, Json?, Json?) raise SchemaError {
  let mut sib_type : Json? = None
  let mut sib_enum : Json? = None
  let mut sib_const : Json? = None
  for key in fields.keys() {
    if key == "$ref" || is_annotation(key) {
      continue
    }
    match key {
      "type" => sib_type = fields.get("type")
      "enum" => sib_enum = fields.get("enum")
      "const" => sib_const = fields.get("const")
      _ => raise Unsupported("$ref")
    }
  }
  (sib_type, sib_enum, sib_const)
}

///|
fn apply_ref_siblings(
  body : Json,
  sib_type : Json?,
  sib_enum : Json?,
  sib_const : Json?,
  defs : Map[String, Json],
  stack : Array[String],
) -> String raise SchemaError {
  if sib_enum is Some(_) && sib_const is Some(_) {
    raise Unsupported("enum/const with other constraints")
  }
  if sib_enum is Some(_) || sib_const is Some(_) {
    ref_enum(body, sib_type, sib_enum, sib_const, defs, stack)
  } else {
    guard sib_type is Some(ty) else { raise Invalid("$ref") }
    ref_type(body, ty, defs, stack)
  }
}

///|
fn ref_enum(
  body : Json,
  sib_type : Json?,
  sib_enum : Json?,
  sib_const : Json?,
  defs : Map[String, Json],
  stack : Array[String],
) -> String raise SchemaError {
  let values = match (sib_const, sib_enum) {
    (Some(value), None) => [value]
    (None, Some(Array(items))) => items
    (None, Some(_)) => raise Invalid("enum")
    _ => raise Invalid("$ref")
  }
  let types = match sib_type {
    None => None
    Some(ty) => Some(type_names(ty))
  }
  let pattern = expand(body, defs, stack)
  let dfa = try @regex.compile(pattern) catch {
    @regex.ParseError(msg~, ..) => raise Invalid(msg)
  } noraise {
    dfa => dfa
  }
  let parts : Array[String] = []
  for value in values {
    if types is Some(types) && !matches_types(value, types) {
      continue
    }
    if dfa.accepts(value.stringify()) && !parts.contains(literal(value)) {
      parts.push(literal(value))
    }
  }
  if parts.is_empty() {
    raise Invalid("$ref")
  }
  alt(parts)
}

///|
fn ref_type(
  body : Json,
  sib_type : Json,
  defs : Map[String, Json],
  stack : Array[String],
) -> String raise SchemaError {
  let want = type_names(sib_type)
  let core = follow_pure(body, defs, stack)
  match core.get("type") {
    Some(ty) => {
      let both = intersect_types(type_names(ty), want)
      if both.is_empty() {
        raise Invalid("$ref")
      }
      if same_types(both, type_names(ty)) {
        expand_fields(core, defs, stack)
      } else {
        expand_fields(with_type(core, both, type_json(both)), defs, stack)
      }
    }
    None =>
      if core.get("enum") is Some(_) || core.get("const") is Some(_) {
        expand_fields(with_type(core, want, type_json(want)), defs, stack)
      } else {
        raise Unsupported("$ref")
      }
  }
}

///|
fn follow_pure(
  schema : Json,
  defs : Map[String, Json],
  stack : Array[String],
) -> Map[String, Json] raise SchemaError {
  guard schema is Object(fields) else { raise Unsupported("boolean schema") }
  match fields.get("$ref") {
    None => fields
    Some(target) => {
      for key in fields.keys() {
        if key != "$ref" && !is_annotation(key) {
          raise Unsupported("$ref")
        }
      }
      guard target is String(pointer) else { raise Invalid("$ref") }
      let name = ref_name(pointer)
      if stack.contains(name) {
        raise Invalid("$ref cycle")
      }
      match defs.get(name) {
        None => raise Invalid("$ref")
        Some(body) => follow_pure(body, defs, push_ref(stack, name))
      }
    }
  }
}

///|
fn type_names(value : Json) -> Array[String] raise SchemaError {
  let names = match value {
    String(ty) => [ty]
    Array(items) => {
      let names : Array[String] = []
      for item in items {
        guard item is String(ty) else { raise Invalid("type") }
        names.push(ty)
      }
      names
    }
    _ => raise Invalid("type")
  }
  if names.is_empty() {
    raise Invalid("type")
  }
  for name in names {
    match name {
      "string"
      | "integer"
      | "number"
      | "boolean"
      | "null"
      | "object"
      | "array" => ()
      _ => raise Invalid("type")
    }
  }
  names
}

///|
fn intersect_types(have : Array[String], want : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for name in have {
    if want.contains(name) && !out.contains(name) {
      out.push(name)
    }
  }
  out
}

///|
fn same_types(left : Array[String], right : Array[String]) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for name in left {
    if !right.contains(name) {
      return false
    }
  }
  true
}

///|
fn with_type(
  fields : Map[String, Json],
  types : Array[String],
  type_value : Json,
) -> Map[String, Json] {
  let allow : Array[String] = []
  for ty in types {
    for key in keys_for(ty) {
      if !allow.contains(key) {
        allow.push(key)
      }
    }
  }
  let kept : Array[(String, Json)] = []
  for key, value in fields {
    if key == "type" {
      continue
    }
    if is_annotation(key) ||
      key == "enum" ||
      key == "const" ||
      allow.contains(key) {
      kept.push((key, value))
    }
  }
  kept.push(("type", type_value))
  Map::from_array(kept)
}

///|
fn type_json(types : Array[String]) -> Json raise SchemaError {
  let buf = StringBuilder()
  if types.length() == 1 {
    buf.write_string("\"")
    buf.write_string(types[0])
    buf.write_string("\"")
  } else {
    buf.write_string("[")
    for i, name in types {
      if i > 0 {
        buf.write_string(",")
      }
      buf.write_string("\"")
      buf.write_string(name)
      buf.write_string("\"")
    }
    buf.write_string("]")
  }
  try @json.parse(buf.to_string()) catch {
    _ => raise Invalid("type")
  } noraise {
    value => value
  }
}

///|
fn expand(
  schema : Json,
  defs : Map[String, Json],
  stack : Array[String],
) -> String raise SchemaError {
  guard schema is Object(fields) else { raise Unsupported("boolean schema") }
  expand_fields(fields, defs, stack)
}

///|
fn expand_fields(
  fields : Map[String, Json],
  defs : Map[String, Json],
  stack : Array[String],
) -> String raise SchemaError {
  for key in fields.keys() {
    if !is_known(key) {
      raise Unsupported(key)
    }
  }
  if fields.get("$ref") is Some(target) {
    let (sib_type, sib_enum, sib_const) = ref_siblings(fields)
    guard target is String(pointer) else { raise Invalid("$ref") }
    let name = ref_name(pointer)
    if stack.contains(name) {
      raise Invalid("$ref cycle")
    }
    match defs.get(name) {
      None => raise Invalid("$ref")
      Some(body) => {
        let next = push_ref(stack, name)
        if sib_type is None && sib_enum is None && sib_const is None {
          return expand(body, defs, next)
        }
        return apply_ref_siblings(
          body, sib_type, sib_enum, sib_const, defs, next,
        )
      }
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
      parts.push(expand(item, defs, stack))
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
        parts.push(gen_typed(Map::from_array(kept), ty, defs, stack))
      }
      alt(parts)
    }
    Some(String(ty)) => gen_typed(fields, ty, defs, stack)
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
      try @regex.string_pattern(pattern) catch {
        @regex.ParseError(_) => raise Unsupported("pattern")
      } noraise {
        _ => ()
      }
      if max is Some(bound) && min > bound {
        raise Invalid("minLength > maxLength")
      }
      let max_n = match max {
        None => -1
        Some(bound) => bound
      }
      let plen = pattern.to_array().length()
      "(?@\{min},\{max_n},\{plen}:\{pattern})"
    }
    Some(_) => raise Invalid("pattern")
  }
  "\"" + body + "\""
}

///|
fn gen_typed(
  fields : Map[String, Json],
  ty : String,
  defs : Map[String, Json],
  stack : Array[String],
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
    "object" => gen_object(fields, defs, stack)
    "array" => gen_array(fields, defs, stack)
    _ => raise Unsupported(ty)
  }
}

///|
fn gen_object(
  fields : Map[String, Json],
  defs : Map[String, Json],
  stack : Array[String],
) -> String raise SchemaError {
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
      pieces.push(
        escape(key.to_json().stringify()) + ":" + expand(child, defs, stack),
      )
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
fn gen_array(
  fields : Map[String, Json],
  defs : Map[String, Json],
  stack : Array[String],
) -> String raise SchemaError {
  reject_foreign(fields, ["type", "items", "minItems", "maxItems"])
  guard fields.get("items") is Some(items) else {
    raise Unsupported("array without items")
  }
  let item = expand(items, defs, stack)
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
