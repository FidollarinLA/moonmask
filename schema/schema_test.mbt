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
    raises(() => @schema.compile({ "type": "integer", "minimum": 0 })),
  )
  assert_true(
    raises(() => @schema.compile({ "type": "string", "pattern": "a+" })),
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
