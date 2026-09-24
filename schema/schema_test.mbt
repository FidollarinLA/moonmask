///|
fn[T] raises(f : () -> T raise) -> Bool {
  try f() catch {
    _ => true
  } noraise {
    _ => false
  }
}

///|
test "primitive types" {
  assert_eq(@schema.to_regex({ "type": "boolean" }), "(?:true|false)")
  let integer = @schema.compile({ "type": "integer" })
  assert_true(integer.accepts("-12"))
  assert_true(integer.accepts("0"))
  assert_false(integer.accepts("012"))
  assert_false(integer.accepts("1.5"))
  assert_true(integer.accepts("999999999999999"))
  assert_false(integer.accepts("1000000000000000"))
  let num = @schema.compile({ "type": "number" })
  assert_true(num.accepts("1.5e-3"))
  assert_false(num.accepts("1."))
  assert_true(@schema.compile({ "type": "null" }).accepts("null"))
  let either = @schema.compile({ "type": ["integer", "null"] })
  assert_true(either.accepts("7"))
  assert_true(either.accepts("null"))
}

///|
test "union length bounds apply only to strings" {
  let either = @schema.compile({ "type": ["string", "null"], "maxLength": 2 })
  assert_true(either.accepts("null"))
  assert_true(either.accepts("\"ab\""))
  assert_false(either.accepts("\"abcd\""))
}

///|
test "strings with length bounds" {
  let s = @schema.compile({ "type": "string", "minLength": 1, "maxLength": 3 })
  assert_true(s.accepts("\"ab\""))
  assert_true(s.accepts("\"a\\nb\""))
  assert_false(s.accepts("\"\""))
  assert_false(s.accepts("\"abcd\""))
  assert_false(s.accepts("\"a\"b\""))
}

///|
test "enum and const" {
  let e = @schema.compile({ "enum": ["red", "green", 3, null] })
  assert_true(e.accepts("\"red\""))
  assert_true(e.accepts("3"))
  assert_true(e.accepts("null"))
  assert_false(e.accepts("\"blue\""))
  let typed = @schema.compile({ "type": "string", "enum": ["a", 1] })
  assert_true(typed.accepts("\"a\""))
  assert_false(typed.accepts("1"))
  let c = @schema.compile({ "const": "a.b" })
  assert_true(c.accepts("\"a.b\""))
  assert_false(c.accepts("\"axb\""))
}

///|
test "objects emit every declared property in order" {
  let o = @schema.compile({
    "type": "object",
    "properties": {
      "name": { "type": "string", "maxLength": 4 },
      "ok": { "type": "boolean" },
    },
    "required": ["name"],
    "additionalProperties": false,
  })
  assert_true(o.accepts("{\"name\":\"ab\",\"ok\":true}"))
  assert_false(o.accepts("{\"ok\":true,\"name\":\"ab\"}"))
  assert_false(o.accepts("{\"name\":\"ab\"}"))
  assert_true(
    @schema.compile({ "type": "object", "properties": {} }).accepts("{}"),
  )
}

///|
test "arrays with item bounds" {
  let a = @schema.compile({
    "type": "array",
    "items": { "type": "integer" },
    "minItems": 1,
    "maxItems": 3,
  })
  assert_false(a.accepts("[]"))
  assert_true(a.accepts("[1]"))
  assert_true(a.accepts("[1,-2,3]"))
  assert_false(a.accepts("[1,2,3,4]"))
  assert_false(a.accepts("[1,]"))
  let any_len = @schema.compile({ "type": "array", "items": { "type": "null" } })
  assert_true(any_len.accepts("[]"))
  assert_true(any_len.accepts("[null,null,null,null]"))
}

///|
test "unsupported keywords are rejected, never ignored" {
  assert_true(
    raises(() => @schema.compile({ "type": "integer", "multipleOf": 2 })),
  )
  assert_true(
    raises(() => @schema.compile({ "type": "string", "pattern": "(?=a)" })),
  )
  assert_true(
    raises(() => @schema.compile({ "type": "string", "format": "email" })),
  )
  assert_true(
    raises(() => @schema.compile({ "oneOf": [{ "type": "string" }] })),
  )
  assert_true(raises(() => @schema.compile({ "$ref": "#/$defs/x" })))
  assert_true(raises(() => @schema.compile({ "type": "array" })))
  assert_true(
    raises(() => {
      @schema.compile({ "type": "object", "properties": {}, "required": ["x"] })
    }),
  )
  assert_true(
    raises(() => {
      @schema.compile({ "type": "string", "minLength": 3, "maxLength": 1 })
    }),
  )
}

///|
fn e2e_schemas() -> Array[Json] {
  [
    {
      "type": "object",
      "properties": {
        "name": { "type": "string", "minLength": 1, "maxLength": 8 },
        "age": { "type": "integer" },
        "role": { "enum": ["admin", "viewer"] },
        "tags": {
          "type": "array",
          "items": { "type": "string", "maxLength": 3 },
          "maxItems": 2,
        },
      },
      "required": ["name", "age", "role", "tags"],
      "additionalProperties": false,
    },
    {
      "anyOf": [
        {
          "type": "object",
          "properties": {
            "tool": { "const": "search" },
            "q": { "type": "string", "maxLength": 5 },
          },
          "additionalProperties": false,
        },
        {
          "type": "object",
          "properties": { "tool": { "const": "stop" } },
          "additionalProperties": false,
        },
      ],
    },
  ]
}

///|
test "every sampled string passes the independent validator" {
  let rand = @random.Rand::chacha8(seed=b"moonmask-schema-e2e-seed-0000000")
  for schema in e2e_schemas() {
    let dfa = @schema.compile(schema)
    let validator = @moonschema.Schema::new(schema)
    let mut produced = 0
    for _ in 0..<200 {
      guard dfa.sample(rand, max_len=400) is Some(bytes) else { continue }
      let text = @utf8.decode(bytes)
      if !validator.valid(@json.parse(text)) {
        fail("schema \{schema.stringify()} rejected sample \{text}")
      }
      produced += 1
    }
    assert_true(produced > 100)
  }
}

///|
fn json_value(text : String) -> Json? {
  try Some(@json.parse(text)) catch {
    _ => None
  } noraise {
    value => value
  }
}

///|
fn accepts_exactly(schema : Json, text : String) -> Bool raise {
  let dfa = @schema.compile(schema)
  if !dfa.accepts(text) {
    return false
  }
  let validator = @moonschema.Schema::new(schema)
  try validator.valid(@json.parse(text)) catch {
    _ => false
  } noraise {
    ok => ok
  }
}

///|
test "integer bounds match the validator on every nearby integer" {
  let cases : Array[Json] = [
    { "type": "integer", "minimum": -3, "maximum": 12 },
    { "type": "integer", "minimum": 98, "maximum": 105 },
    { "type": "integer", "minimum": 999, "maximum": 1001 },
    { "type": "integer", "exclusiveMinimum": 2, "exclusiveMaximum": 5 },
    { "type": "integer", "minimum": 1.5, "maximum": 4.2 },
    { "type": "integer", "minimum": -5, "maximum": -2 },
    { "type": "integer", "minimum": 0 },
    { "type": "integer", "maximum": -5 },
  ]
  for schema in cases {
    let dfa = @schema.compile(schema)
    let validator = @moonschema.Schema::new(schema)
    for n in -30..<=1100 {
      if n > 120 && n < 90 {
        continue
      }
      if n > 120 && n < 980 {
        continue
      }
      if n > 1020 {
        continue
      }
      let text = n.to_string()
      let ok = validator.valid(@json.parse(text))
      if dfa.accepts(text) != ok {
        fail(
          "\{schema.stringify()} on \{text}: dfa=\{dfa.accepts(text)} validator=\{ok}",
        )
      }
    }
    assert_false(dfa.accepts("-0"))
    assert_false(dfa.accepts("01"))
    assert_false(dfa.accepts("1.0"))
  }
}

///|
test "numeric bounds accept in-range decimals and reject the rest" {
  let schema : Json = { "type": "number", "minimum": 1.25, "maximum": 3.25 }
  let dfa = @schema.compile(schema)
  let validator = @moonschema.Schema::new(schema)
  let yes = ["1.25", "1.250", "1.5", "2", "2.5", "3", "3.2", "3.25", "3.250"]
  for text in yes {
    if !dfa.accepts(text) || !validator.valid(@json.parse(text)) {
      fail(text)
    }
  }
  let no = [
    "1.24", "1.249", "1", "3.26", "3.251", "4", "1e1", "1E1", "01.5", "-0",
  ]
  for text in no {
    assert_false(dfa.accepts(text))
  }
  for ip in 0..<=4 {
    for d1 in 0..<10 {
      let text = "\{ip}.\{d1}"
      guard json_value(text) is Some(value) else { continue }
      if dfa.accepts(text) {
        assert_true(validator.valid(value))
      } else if validator.valid(value) {
        fail("missing in-range decimal \{text}")
      }
    }
  }
  let wide : Json = { "type": "number", "minimum": 0, "maximum": 10 }
  let wide_dfa = @schema.compile(wide)
  assert_true(wide_dfa.accepts("1.5"))
  assert_true(wide_dfa.accepts("0.0"))
  assert_false(wide_dfa.accepts("1e1"))
  assert_false(wide_dfa.accepts("10.1"))
  assert_false(wide_dfa.accepts("-0.1"))
  let tenth : Json = { "type": "number", "minimum": 0.1, "maximum": 0.3 }
  let tenth_dfa = @schema.compile(tenth)
  let tenth_v = @moonschema.Schema::new(tenth)
  for text in ["0.1", "0.2", "0.30"] {
    if !tenth_dfa.accepts(text) || !tenth_v.valid(@json.parse(text)) {
      fail(text)
    }
  }
  assert_false(tenth_dfa.accepts("0.09"))
  assert_false(tenth_dfa.accepts("0.31"))
  assert_false(tenth_dfa.accepts("1e-1"))
  let cross : Json = { "type": "number", "minimum": -2.5, "maximum": 3.2 }
  let cross_dfa = @schema.compile(cross)
  let cross_v = @moonschema.Schema::new(cross)
  let samples = [
    "-2.5", "-2.50", "-2", "-1.5", "-0.5", "0", "0.0", "1.5", "3", "3.2", "3.20",
  ]
  for text in samples {
    if !cross_dfa.accepts(text) || !cross_v.valid(@json.parse(text)) {
      fail(text)
    }
  }
  assert_false(cross_dfa.accepts("-2.6"))
  assert_false(cross_dfa.accepts("3.3"))
  assert_false(cross_dfa.accepts("-2.5e0"))
  assert_false(cross_dfa.accepts("-0"))
}

///|
test "exclusive numeric bounds and rejected bound forms" {
  let open = @schema.compile({
    "type": "integer",
    "exclusiveMinimum": 2,
    "exclusiveMaximum": 5,
  })
  assert_false(open.accepts("2"))
  assert_true(open.accepts("3"))
  assert_true(open.accepts("4"))
  assert_false(open.accepts("5"))
  let stricter = @schema.compile({
    "type": "integer",
    "minimum": 0,
    "exclusiveMinimum": 2,
    "maximum": 10,
    "exclusiveMaximum": 6,
  })
  assert_false(stricter.accepts("2"))
  assert_true(stricter.accepts("3"))
  assert_true(stricter.accepts("5"))
  assert_false(stricter.accepts("6"))
  let either = @schema.compile({ "type": ["integer", "null"], "minimum": 0 })
  assert_true(either.accepts("null"))
  assert_true(either.accepts("0"))
  assert_false(either.accepts("-1"))
  assert_true(
    raises(() => {
      @schema.compile({ "type": "integer", "exclusiveMinimum": true })
    }),
  )
  assert_true(
    raises(() => {
      @schema.compile({ "type": "number", "exclusiveMaximum": false })
    }),
  )
  assert_true(
    raises(() => {
      @schema.compile({ "type": "integer", "minimum": 5, "maximum": 1 })
    }),
  )
  assert_true(
    raises(() => {
      @schema.compile({
        "type": "integer",
        "exclusiveMinimum": 1,
        "exclusiveMaximum": 2,
      })
    }),
  )
  assert_true(
    raises(() => {
      @schema.compile(@json.parse("{\"type\":\"number\",\"minimum\":1e20}"))
    }),
  )
  assert_true(
    accepts_exactly(
      { "type": "number", "minimum": -2.5, "maximum": 3.2 },
      "-1.25",
    ),
  )
}

///|
test "sampled bounded numbers pass the independent validator" {
  let schemas : Array[Json] = [
    { "type": "integer", "minimum": -2, "maximum": 5 },
    { "type": "number", "minimum": 0, "maximum": 2 },
    { "type": "number", "exclusiveMinimum": 1.25, "maximum": 3.25 },
  ]
  let rand = @random.Rand::chacha8(seed=b"moonmask-numeric-e2e-seed-000000")
  for schema in schemas {
    let dfa = @schema.compile(schema)
    let validator = @moonschema.Schema::new(schema)
    let mut produced = 0
    for _ in 0..<80 {
      guard dfa.sample(rand, max_len=80) is Some(bytes) else { continue }
      let text = @utf8.decode(bytes)
      if !validator.valid(@json.parse(text)) {
        fail("\{schema.stringify()} rejected sample \{text}")
      }
      produced += 1
    }
    assert_true(produced > 40)
  }
}

///|
fn json_string(content : String) -> String {
  "\"" + content + "\""
}

///|
test "string patterns agree with the validator" {
  let patterns = ["a+", "[0-9]{2}", "a*", "(?:ab|c)", "z"]
  let contents = [
    "", "a", "b", "aa", "ab", "ba", "bb", "12", "1", "x12", "c", "zab", "az",
  ]
  for pattern in patterns {
    let schema : Json = { "type": "string", "pattern": pattern }
    let dfa = @schema.compile(schema)
    let validator = @moonschema.Schema::new(schema)
    for content in contents {
      let text = json_string(content)
      let value = @json.parse(text)
      let ok = validator.valid(value)
      if dfa.accepts(text) != ok {
        fail(
          "pattern \{pattern} on \{text}: dfa=\{dfa.accepts(text)} validator=\{ok}",
        )
      }
    }
    let escaped = "\"\\na\""
    let escaped_ok = validator.valid(@json.parse(escaped))
    if dfa.accepts(escaped) != escaped_ok {
      fail("pattern \{pattern} on escaped newline")
    }
  }
  assert_true(
    raises(() => @schema.compile({ "type": "string", "pattern": "." })),
  )
  assert_true(
    raises(() => @schema.compile({ "type": "string", "pattern": "\\s" })),
  )
  assert_true(
    raises(() => @schema.compile({ "type": "string", "pattern": "^a" })),
  )
  assert_true(
    raises(() => {
      @schema.compile({ "type": "string", "pattern": ".", "maxLength": 4 })
    }),
  )
  let either = @schema.compile({ "type": ["string", "null"], "pattern": "a+" })
  assert_true(either.accepts("null"))
  assert_true(either.accepts("\"ba\""))
  assert_false(either.accepts("\"b\""))
}

///|
fn expect_json(schema : Json, text : String, want : Bool) -> Unit raise {
  let dfa = @schema.compile(schema)
  let validator = @moonschema.Schema::new(schema)
  let ok = validator.valid(@json.parse(text))
  if ok != want {
    fail("validator \{schema.stringify()} on \{text}: \{ok}")
  }
  if dfa.accepts(text) != want {
    fail("dfa \{schema.stringify()} on \{text}: \{dfa.accepts(text)}")
  }
}

///|
test "pattern and length count decoded characters" {
  let short : Json = {
    "type": "string",
    "pattern": "a+",
    "minLength": 1,
    "maxLength": 3,
  }
  expect_json(short, "\"a\"", true)
  expect_json(short, "\"aa\"", true)
  expect_json(short, "\"aaa\"", true)
  expect_json(short, "\"ba\"", true)
  expect_json(short, "\"ab\"", true)
  expect_json(short, "\"a\\n\"", true)
  expect_json(short, "\"\\na\"", true)
  expect_json(short, "\"\"", false)
  expect_json(short, "\"b\"", false)
  expect_json(short, "\"aaaa\"", false)
  expect_json(short, "\"\\n\\n\"", false)
  expect_json(short, "\"\\n\\n\\n\\n\"", false)
  let digits : Json = {
    "type": "string",
    "pattern": "[0-9]{2}",
    "minLength": 2,
    "maxLength": 4,
  }
  expect_json(digits, "\"12\"", true)
  expect_json(digits, "\"x12\"", true)
  expect_json(digits, "\"12xy\"", true)
  expect_json(digits, "\"\\n12\"", true)
  expect_json(digits, "\"1\"", false)
  expect_json(digits, "\"ab\"", false)
  expect_json(digits, "\"12345\"", false)
  let pair : Json = {
    "type": "string",
    "pattern": "ab",
    "minLength": 2,
    "maxLength": 4,
  }
  expect_json(pair, "\"ab\"", true)
  expect_json(pair, "\"aab\"", true)
  expect_json(pair, "\"aaab\"", true)
  expect_json(pair, "\"\\nab\"", true)
  expect_json(pair, "\"a\\nb\"", false)
  expect_json(pair, "\"a\"", false)
  let slash : Json = {
    "type": "string",
    "pattern": "/",
    "minLength": 1,
    "maxLength": 1,
  }
  expect_json(slash, "\"/\"", true)
  expect_json(slash, "\"\\/\"", true)
  expect_json(slash, "\"a\"", false)
  let open : Json = { "type": "string", "pattern": "a", "minLength": 2 }
  expect_json(open, "\"ba\"", true)
  expect_json(open, "\"a\"", false)
  expect_json(open, "\"bbbb\"", false)
  let nested = @schema.compile({
    "type": "object",
    "properties": { "s": short },
  })
  assert_true(nested.accepts("{\"s\":\"aa\"}"))
  assert_false(nested.accepts("{\"s\":\"b\"}"))
  assert_false(nested.accepts("{\"s\":\"aaaa\"}"))
  assert_true(
    raises(() => {
      @schema.compile({
        "type": "string",
        "pattern": "a+",
        "minLength": 3,
        "maxLength": 1,
      })
    }),
  )
  assert_true(
    raises(() => {
      @schema.compile({ "type": "string", "pattern": "(?=a)", "maxLength": 2 })
    }),
  )
  let bodies = [
    "", "a", "b", "aa", "ab", "ba", "bb", "aaa", "aaaa", "12", "1", "x12", "12xy",
    "12345", "aaab", "\\n", "\\na", "\\n\\n", "a\\n", "a\\nb", "\\/",
  ]
  let schemas : Array[Json] = [
    short,
    digits,
    pair,
    { "type": "string", "pattern": "a*", "minLength": 0, "maxLength": 2 },
    { "type": "string", "pattern": "z", "minLength": 1, "maxLength": 3 },
  ]
  for schema in schemas {
    let dfa = @schema.compile(schema)
    let validator = @moonschema.Schema::new(schema)
    for body in bodies {
      let text = json_string(body)
      let ok = validator.valid(@json.parse(text))
      if dfa.accepts(text) != ok {
        fail(
          "\{schema.stringify()} on \{text}: dfa=\{dfa.accepts(text)} validator=\{ok}",
        )
      }
    }
  }
}

///|
test "sampled patterned strings pass the independent validator" {
  let schema : Json = { "type": "string", "pattern": "a+" }
  let dfa = @schema.compile(schema)
  let validator = @moonschema.Schema::new(schema)
  let rand = @random.Rand::chacha8(seed=b"moonmask-pattern-e2e-seed-000000")
  let mut produced = 0
  for _ in 0..<200 {
    guard dfa.sample(rand, max_len=80) is Some(bytes) else { continue }
    let text = @utf8.decode(bytes)
    if !validator.valid(@json.parse(text)) {
      fail(text)
    }
    produced += 1
  }
  assert_true(produced > 10)
}

///|
test "string content accepts well-formed utf-8 and rejects the rest" {
  let one : Json = { "type": "string", "minLength": 1, "maxLength": 1 }
  expect_json(one, "\"é\"", true)
  expect_json(one, "\"中\"", true)
  expect_json(one, "\"😀\"", true)
  expect_json(one, "\"\\n\"", true)
  expect_json(one, "\"a\"", true)
  expect_json(one, "\"中文\"", false)
  expect_json(one, "\"e\u{0301}\"", false)
  expect_json(one, "\"\\n中\"", false)
  let two : Json = { "type": "string", "minLength": 2, "maxLength": 2 }
  expect_json(two, "\"\\n中\"", true)
  expect_json(two, "\"中\\n\"", true)
  expect_json(two, "\"e\u{0301}\"", true)
  expect_json(two, "\"中\"", false)
  let marked : Json = {
    "type": "string",
    "pattern": "a+",
    "minLength": 1,
    "maxLength": 3,
  }
  expect_json(marked, "\"中a\"", true)
  expect_json(marked, "\"a中\"", true)
  expect_json(marked, "\"中文a\"", true)
  expect_json(marked, "\"中\"", false)
  expect_json(marked, "\"😀\"", false)
  expect_json(marked, "\"中文ab\"", false)
  let text = @schema.compile(one)
  assert_true(text.matches(Bytes::from_array([0x22, 0xC3, 0xA9, 0x22])))
  let bad = [
    [0x22, 0x80, 0x22],
    [0x22, 0xC0, 0x80, 0x22],
    [0x22, 0xED, 0xA0, 0x80, 0x22],
    [0x22, 0xC2, 0x22],
    [0x22, 0xE0, 0x80, 0x80, 0x22],
    [0x22, 0xF5, 0x80, 0x80, 0x80, 0x22],
  ]
  for bytes in bad {
    let raw : Array[Byte] = []
    for b in bytes {
      raw.push(b.to_byte())
    }
    assert_false(text.matches(Bytes::from_array(raw)))
  }
  assert_true(
    raises(() => @schema.compile({ "type": "string", "pattern": "中" })),
  )
  assert_true(
    raises(() => @schema.compile({ "type": "string", "pattern": "\\u4e2d" })),
  )
  assert_true(
    raises(() => @schema.compile({ "type": "string", "pattern": "\\xC2" })),
  )
}

///|
test "pattern length bound of 1000 still matches one decoded character" {
  let schema : Json = {
    "type": "string",
    "pattern": "a",
    "minLength": 1000,
    "maxLength": 1000,
  }
  let dfa = @schema.compile(schema)
  let buf = StringBuilder()
  buf.write_char('"')
  for _ in 0..<999 {
    buf.write_char('b')
  }
  buf.write_char('a')
  buf.write_char('"')
  assert_true(dfa.accepts(buf.to_string()))
  assert_false(dfa.accepts("\"a\""))
  let too_long = StringBuilder()
  too_long.write_char('"')
  for _ in 0..<1001 {
    too_long.write_char('a')
  }
  too_long.write_char('"')
  assert_false(dfa.accepts(too_long.to_string()))
}

///|
test "sampled strings with pattern and length pass the validator" {
  let schema : Json = {
    "type": "string",
    "pattern": "a+",
    "minLength": 1,
    "maxLength": 4,
  }
  let dfa = @schema.compile(schema)
  let validator = @moonschema.Schema::new(schema)
  let rand = @random.Rand::chacha8(seed=b"moonmask-pattern-len-seed-000000")
  let mut produced = 0
  for _ in 0..<80 {
    guard dfa.sample(rand, max_len=40) is Some(bytes) else { continue }
    let text = @utf8.decode(bytes)
    if !validator.valid(@json.parse(text)) {
      fail(text)
    }
    produced += 1
  }
  assert_true(produced > 20)
}

///|
test "hand-written invalid documents are rejected" {
  let dfa = @schema.compile(e2e_schemas()[0])
  assert_true(
    dfa.accepts("{\"name\":\"a\",\"age\":1,\"role\":\"admin\",\"tags\":[]}"),
  )
  let bad = [
    "{\"name\":\"\",\"age\":1,\"role\":\"admin\",\"tags\":[]}", "{\"name\":\"a\",\"age\":1.5,\"role\":\"admin\",\"tags\":[]}",
    "{\"name\":\"a\",\"age\":1,\"role\":\"root\",\"tags\":[]}", "{\"name\":\"a\",\"age\":1,\"role\":\"admin\",\"tags\":[\"x\",\"y\",\"z\"]}",
    "{\"name\":\"a\", \"age\":1,\"role\":\"admin\",\"tags\":[]}",
  ]
  for doc in bad {
    assert_false(dfa.accepts(doc))
  }
}
