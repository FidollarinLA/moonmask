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
/// A `$ref` is `#/...` and the segment before the last one is `$defs`.
/// `~0` is `~` and `~1` is `/`.
fn pointer_segments(target : String) -> Array[String] raise SchemaError {
  let chars = target.to_array()
  if chars.length() < 3 || chars[0] != '#' || chars[1] != '/' {
    raise Unsupported("$ref")
  }
  let segments : Array[String] = []
  let mut buf = StringBuilder()
  let mut i = 2
  while i <= chars.length() {
    let done = i == chars.length()
    let c = if done { '/' } else { chars[i] }
    if done || c == '/' {
      let name = buf.to_string()
      if name.length() == 0 {
        raise Unsupported("$ref")
      }
      segments.push(name)
      buf = StringBuilder()
      i += 1
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
  if segments.length() < 2 || segments[segments.length() - 2] != "$defs" {
    raise Unsupported("$ref")
  }
  segments
}

///|
fn escape_pointer(segment : String) -> String {
  let buf = StringBuilder()
  for c in segment {
    match c {
      '~' => buf.write_string("~0")
      '/' => buf.write_string("~1")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn canonical_ref(target : String) -> String raise SchemaError {
  let buf = StringBuilder()
  buf.write_char('#')
  for segment in pointer_segments(target) {
    buf.write_char('/')
    buf.write_string(escape_pointer(segment))
  }
  buf.to_string()
}

///|
fn join_pointer(here : String, segments : Array[String]) -> String {
  let buf = StringBuilder()
  buf.write_string(here)
  for segment in segments {
    buf.write_char('/')
    buf.write_string(escape_pointer(segment))
  }
  buf.to_string()
}

///|
fn lookup_ref(root : Json, target : String) -> Json raise SchemaError {
  let mut cur = root
  for segment in pointer_segments(target) {
    guard cur is Object(fields) else { raise Invalid("$ref") }
    match fields.get(segment) {
      None => raise Invalid("$ref")
      Some(next) => cur = next
    }
  }
  cur
}

///|
fn gen(schema : Json) -> String raise SchemaError {
  guard schema is Object(_) else { raise Unsupported("boolean schema") }
  expand(schema, schema, [], "#")
}

///|
/// Keywords beside `$ref` that narrow the referenced schema.
priv struct RefSiblings {
  ty : Json?
  en : Json?
  co : Json?
  min_length : Json?
  max_length : Json?
  pat : Json?
}

///|
/// `type`, `enum`, `const`, `minLength`, `maxLength`, and `pattern` beside
/// `$ref` narrow the referenced schema, including when that schema is itself a
/// reference carrying the same keywords. Any other sibling keyword is rejected.
/// A sibling that cannot overlap the reference is rejected rather than ignored.
fn ref_siblings(fields : Map[String, Json]) -> RefSiblings raise SchemaError {
  let mut sib_type : Json? = None
  let mut sib_enum : Json? = None
  let mut sib_const : Json? = None
  let mut sib_min : Json? = None
  let mut sib_max : Json? = None
  let mut sib_pat : Json? = None
  for key in fields.keys() {
    if key == "$ref" || is_annotation(key) {
      continue
    }
    match key {
      "type" => sib_type = fields.get("type")
      "enum" => sib_enum = fields.get("enum")
      "const" => sib_const = fields.get("const")
      "minLength" => sib_min = fields.get("minLength")
      "maxLength" => sib_max = fields.get("maxLength")
      "pattern" => sib_pat = fields.get("pattern")
      _ => raise Unsupported("$ref")
    }
  }
  return {
    ty: sib_type,
    en: sib_enum,
    co: sib_const,
    min_length: sib_min,
    max_length: sib_max,
    pat: sib_pat,
  }
}

///|
fn RefSiblings::has_text(self : RefSiblings) -> Bool {
  self.min_length is Some(_) ||
  self.max_length is Some(_) ||
  self.pat is Some(_)
}

///|
fn RefSiblings::has_constraint(self : RefSiblings) -> Bool {
  self.ty is Some(_) ||
  self.en is Some(_) ||
  self.co is Some(_) ||
  self.has_text()
}

///|
/// Constraints gathered from every `$ref` along an acyclic chain.
priv struct ChainLimit {
  ty : Array[String]?
  values : Array[Json]?
  min_length : Json?
  max_length : Json?
  patterns : Array[String]
}

///|
fn ChainLimit::has_text(self : ChainLimit) -> Bool {
  self.min_length is Some(_) ||
  self.max_length is Some(_) ||
  self.patterns.length() > 0
}

///|
fn empty_limit() -> ChainLimit {
  return {
    ty: None,
    values: None,
    min_length: None,
    max_length: None,
    patterns: [],
  }
}

///|
fn apply_ref_siblings(
  body : Json,
  sib : RefSiblings,
  root : Json,
  stack : Array[String],
  here : String,
) -> String raise SchemaError {
  if sib.en is Some(_) && sib.co is Some(_) {
    raise Unsupported("enum/const with other constraints")
  }
  let (core, chain, there) = follow_chain(body, root, stack, here)
  apply_limit(core, merge_limit(chain, sib), root, stack, there)
}

///|
fn follow_chain(
  schema : Json,
  root : Json,
  stack : Array[String],
  here : String,
) -> (Map[String, Json], ChainLimit, String) raise SchemaError {
  guard schema is Object(fields) else { raise Unsupported("boolean schema") }
  match fields.get("$ref") {
    None => (fields, empty_limit(), here)
    Some(target) => {
      let sib = ref_siblings(fields)
      if sib.en is Some(_) && sib.co is Some(_) {
        raise Unsupported("enum/const with other constraints")
      }
      guard target is String(pointer) else { raise Invalid("$ref") }
      let canon = canonical_ref(pointer)
      if stack.contains(canon) {
        raise Invalid("$ref cycle")
      }
      let body = lookup_ref(root, canon)
      let (core, inner, there) = follow_chain(
        body,
        root,
        push_ref(stack, canon),
        canon,
      )
      (core, merge_limit(inner, sib), there)
    }
  }
}

///|
fn merge_limit(
  limit : ChainLimit,
  sib : RefSiblings,
) -> ChainLimit raise SchemaError {
  let patterns : Array[String] = []
  for pattern in limit.patterns {
    patterns.push(pattern)
  }
  match pattern_of(sib.pat) {
    None => ()
    Some(pattern) => patterns.push(pattern)
  }
  let min_length = tighter(limit.min_length, sib.min_length, true, "minLength")
  let max_length = tighter(limit.max_length, sib.max_length, false, "maxLength")
  let _ = paired_bounds(min_length, max_length)
  return {
    ty: merge_type(limit.ty, sib.ty),
    values: intersect_values(limit.values, sib_values(sib)),
    min_length,
    max_length,
    patterns,
  }
}

///|
fn merge_type(
  have : Array[String]?,
  extra : Json?,
) -> Array[String]? raise SchemaError {
  match extra {
    None => have
    Some(value) => {
      let want = type_names(value)
      match have {
        None => Some(want)
        Some(old) => {
          let both = intersect_types(old, want)
          if both.is_empty() {
            raise Invalid("$ref")
          }
          Some(both)
        }
      }
    }
  }
}

///|
fn sib_values(sib : RefSiblings) -> Array[Json]? raise SchemaError {
  match (sib.co, sib.en) {
    (None, None) => None
    (Some(value), None) => Some([value])
    (None, Some(Array(items))) => Some(items)
    (None, Some(_)) => raise Invalid("enum")
    _ => raise Unsupported("enum/const with other constraints")
  }
}

///|
fn core_values(core : Map[String, Json]) -> Array[Json]? raise SchemaError {
  match (core.get("const"), core.get("enum")) {
    (None, None) => None
    (Some(value), None) => Some([value])
    (None, Some(Array(items))) => Some(items)
    (Some(_), Some(_)) => raise Unsupported("enum/const with other constraints")
    (None, Some(_)) => raise Invalid("enum")
  }
}

///|
fn intersect_values(
  left : Array[Json]?,
  right : Array[Json]?,
) -> Array[Json]? raise SchemaError {
  match left {
    None => right
    Some(xs) =>
      match right {
        None => Some(xs)
        Some(ys) => {
          let out : Array[Json] = []
          for x in xs {
            let text = x.stringify()
            let mut found = false
            for y in ys {
              if y.stringify() == text {
                found = true
              }
            }
            if found {
              let mut seen = false
              for item in out {
                if item.stringify() == text {
                  seen = true
                }
              }
              if !seen {
                out.push(x)
              }
            }
          }
          if out.is_empty() {
            raise Invalid("$ref")
          }
          Some(out)
        }
      }
  }
}

///|
/// Length and pattern have to be met as well as the reference. A value that is
/// not a string cannot meet them. No overlap is an error.
fn apply_limit(
  core : Map[String, Json],
  limit : ChainLimit,
  root : Json,
  stack : Array[String],
  here : String,
) -> String raise SchemaError {
  let mut core = core
  if limit.ty is Some(names) {
    core = narrowed_core(core, type_json(names))
  }
  let values = intersect_values(core_values(core), limit.values)
  if values is Some(values) {
    let types = match core.get("type") {
      None => None
      Some(ty) => Some(type_names(ty))
    }
    let dfa = compile_re(expand_fields(core, root, stack, here))
    return filter_values(values, types, dfa, limit_text_dfa(limit))
  }
  if limit.has_text() {
    return assert_overlap(merged_limits(core, limit))
  }
  expand_fields(core, root, stack, here)
}

///|
fn filter_values(
  values : Array[Json],
  types : Array[String]?,
  dfa : @regex.Dfa,
  extra : @regex.Dfa?,
) -> String raise SchemaError {
  let parts : Array[String] = []
  for value in values {
    if types is Some(types) && !matches_types(value, types) {
      continue
    }
    let text = value.stringify()
    if !dfa.accepts(text) {
      continue
    }
    if extra is Some(extra) && !extra.accepts(text) {
      continue
    }
    if !parts.contains(literal(value)) {
      parts.push(literal(value))
    }
  }
  if parts.is_empty() {
    raise Invalid("$ref")
  }
  alt(parts)
}

///|
fn narrowed_core(
  core : Map[String, Json],
  sib_type : Json,
) -> Map[String, Json] raise SchemaError {
  let want = type_names(sib_type)
  match core.get("type") {
    Some(ty) => {
      let both = intersect_types(type_names(ty), want)
      if both.is_empty() {
        raise Invalid("$ref")
      }
      if same_types(both, type_names(ty)) {
        core
      } else {
        with_type(core, both, type_json(both))
      }
    }
    None =>
      if core.get("enum") is Some(_) || core.get("const") is Some(_) {
        with_type(core, want, type_json(want))
      } else {
        raise Unsupported("$ref")
      }
  }
}

///|
fn compile_re(pattern : String) -> @regex.Dfa raise SchemaError {
  try @regex.compile(pattern) catch {
    @regex.ParseError(msg~, ..) => raise Invalid(msg)
  } noraise {
    dfa => dfa
  }
}

///|
fn assert_overlap(pattern : String) -> String raise SchemaError {
  let dfa = compile_re(pattern)
  let mut live = false
  for i in 0..<dfa.state_count() {
    if dfa.is_accept(i) {
      live = true
    }
  }
  if !live {
    raise Invalid("$ref")
  }
  pattern
}

///|
fn limit_text_dfa(limit : ChainLimit) -> @regex.Dfa? raise SchemaError {
  if !limit.has_text() {
    return None
  }
  let (min, max) = paired_bounds(limit.min_length, limit.max_length)
  Some(compile_re(string_regex(min, max, limit.patterns)))
}

///|
fn merged_limits(
  core : Map[String, Json],
  limit : ChainLimit,
) -> String raise SchemaError {
  let names = match core.get("type") {
    Some(ty) => type_names(ty)
    None => raise Invalid("$ref")
  }
  if !names.contains("string") {
    raise Invalid("$ref")
  }
  let string_core = if names.length() == 1 && names[0] == "string" {
    core
  } else {
    with_type(core, ["string"], type_json(["string"]))
  }
  reject_foreign(string_core, ["type", "minLength", "maxLength", "pattern"])
  let min_j = tighter(
    string_core.get("minLength"),
    limit.min_length,
    true,
    "minLength",
  )
  let max_j = tighter(
    string_core.get("maxLength"),
    limit.max_length,
    false,
    "maxLength",
  )
  let (min, max) = paired_bounds(min_j, max_j)
  let patterns : Array[String] = []
  match pattern_of(string_core.get("pattern")) {
    None => ()
    Some(pattern) => patterns.push(pattern)
  }
  for pattern in limit.patterns {
    patterns.push(pattern)
  }
  string_regex(min, max, patterns)
}

///|
fn paired_bounds(min_j : Json?, max_j : Json?) -> (Int, Int?) raise SchemaError {
  let min = match min_j {
    None => 0
    Some(value) => bound_value("minLength", value)
  }
  let max = match max_j {
    None => None
    Some(value) => Some(bound_value("maxLength", value))
  }
  if max is Some(bound) && min > bound {
    raise Invalid("$ref")
  }
  (min, max)
}

///|
fn pattern_of(value : Json?) -> String? raise SchemaError {
  match value {
    None => None
    Some(String("")) => None
    Some(String(pattern)) => Some(pattern)
    Some(_) => raise Invalid("pattern")
  }
}

///|
fn bound_value(key : String, value : Json) -> Int raise SchemaError {
  match value {
    Number(n, ..) =>
      if n < 0.0 || n != n.floor() {
        raise Invalid(key)
      } else if n > 1000.0 {
        raise Unsupported(key)
      } else {
        n.to_int()
      }
    _ => raise Invalid(key)
  }
}

///|
fn tighter(
  left : Json?,
  right : Json?,
  larger_wins : Bool,
  key : String,
) -> Json? raise SchemaError {
  match left {
    None => right
    Some(a) =>
      match right {
        None => Some(a)
        Some(b) => {
          let na = bound_value(key, a)
          let nb = bound_value(key, b)
          if larger_wins {
            if na >= nb {
              Some(a)
            } else {
              Some(b)
            }
          } else if na <= nb {
            Some(a)
          } else {
            Some(b)
          }
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
  root : Json,
  stack : Array[String],
  here : String,
) -> String raise SchemaError {
  guard schema is Object(fields) else { raise Unsupported("boolean schema") }
  expand_fields(fields, root, stack, here)
}

///|
fn bind_defs(
  fields : Map[String, Json],
  root : Json,
  stack : Array[String],
  here : String,
) -> Map[String, Json] raise SchemaError {
  match fields.get("$defs") {
    None => fields
    Some(_) => {
      let defined = read_defs(fields)
      for name, body in defined {
        let ptr = join_pointer(here, ["$defs", name])
        let _ = expand(body, root, push_ref(stack, ptr), ptr)
      }
      drop_defs(fields)
    }
  }
}

///|
fn expand_fields(
  fields : Map[String, Json],
  root : Json,
  stack : Array[String],
  here : String,
) -> String raise SchemaError {
  let fields = bind_defs(fields, root, stack, here)
  for key in fields.keys() {
    if !is_known(key) {
      raise Unsupported(key)
    }
  }
  if fields.get("$ref") is Some(target) {
    let sib = ref_siblings(fields)
    guard target is String(pointer) else { raise Invalid("$ref") }
    let canon = canonical_ref(pointer)
    if stack.contains(canon) {
      raise Invalid("$ref cycle")
    }
    let body = lookup_ref(root, canon)
    let next = push_ref(stack, canon)
    if !sib.has_constraint() {
      return expand(body, root, next, canon)
    }
    return apply_ref_siblings(body, sib, root, next, canon)
  }
  if fields.get("const") is Some(_) || fields.get("enum") is Some(_) {
    return gen_enum(fields)
  }
  if fields.get("anyOf") is Some(options) {
    reject_foreign(fields, ["anyOf"])
    guard options is Array(items) else { raise Invalid("anyOf") }
    let parts = []
    for i, item in items {
      parts.push(
        expand(item, root, stack, join_pointer(here, ["anyOf", "\{i}"])),
      )
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
        parts.push(gen_typed(Map::from_array(kept), ty, root, stack, here))
      }
      alt(parts)
    }
    Some(String(ty)) => gen_typed(fields, ty, root, stack, here)
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
  if max is Some(bound) && min > bound {
    raise Invalid("minLength > maxLength")
  }
  let patterns = match pattern_of(fields.get("pattern")) {
    None => []
    Some(pattern) => [pattern]
  }
  string_regex(min, max, patterns)
}

///|
fn string_regex(
  min : Int,
  max : Int?,
  patterns : Array[String],
) -> String raise SchemaError {
  let kept : Array[String] = []
  for pattern in patterns {
    if pattern != "" {
      check_user_pattern(pattern)
      kept.push(pattern)
    }
  }
  let body = if kept.length() == 0 {
    repeat_atom(string_char, min, max)
  } else {
    let max_n = match max {
      None => -1
      Some(bound) => bound
    }
    let buf = StringBuilder()
    buf.write_string("(?@\{min},\{max_n}")
    for pattern in kept {
      let plen = pattern.to_array().length()
      buf.write_string(",\{plen}")
    }
    buf.write_string(":")
    for pattern in kept {
      buf.write_string(pattern)
    }
    buf.write_string(")")
    buf.to_string()
  }
  "\"" + body + "\""
}

///|
fn check_user_pattern(pattern : String) -> Unit raise SchemaError {
  try @regex.string_pattern(pattern) catch {
    @regex.ParseError(_) => raise Unsupported("pattern")
  } noraise {
    _ => ()
  }
}

///|
fn gen_typed(
  fields : Map[String, Json],
  ty : String,
  root : Json,
  stack : Array[String],
  here : String,
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
    "object" => gen_object(fields, root, stack, here)
    "array" => gen_array(fields, root, stack, here)
    _ => raise Unsupported(ty)
  }
}

///|
fn gen_object(
  fields : Map[String, Json],
  root : Json,
  stack : Array[String],
  here : String,
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
        escape(key.to_json().stringify()) +
        ":" +
        expand(child, root, stack, join_pointer(here, ["properties", key])),
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
  root : Json,
  stack : Array[String],
  here : String,
) -> String raise SchemaError {
  reject_foreign(fields, ["type", "items", "minItems", "maxItems"])
  guard fields.get("items") is Some(items) else {
    raise Unsupported("array without items")
  }
  let item = expand(items, root, stack, join_pointer(here, ["items"]))
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
