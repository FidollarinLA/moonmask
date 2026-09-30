///|
test "whitespace is opt-in and restricted to four JSON characters" {
  let schema : Json = { "type": "boolean" }
  let compact = @schema.compile(schema)
  let spaced = @schema.compile(schema, whitespace=true)
  assert_true(compact.accepts("true"))
  assert_false(compact.accepts(" true "))
  for ws in [" ", "\t", "\r", "\n", " \t\r\n"] {
    assert_true(spaced.accepts(ws + "true" + ws))
    assert_false(spaced.accepts("tr" + ws + "ue"))
    assert_false(spaced.accepts(ws))
  }
  for ws in ["\u000b", "\u000c", "\u00a0", "\u2003"] {
    assert_false(spaced.accepts(ws + "true"))
    assert_false(spaced.accepts("true" + ws))
  }
  assert_false(spaced.accepts("true false"))
}

///|
test "whitespace preserves required members and comma rules" {
  let schema : Json = {
    "type": "object",
    "properties": {
      "a": { "type": "integer" },
      "b": { "type": "boolean" },
      "c": { "type": "null" },
    },
    "required": ["b"],
    "additionalProperties": false,
  }
  let dfa = @schema.compile(schema, whitespace=true)
  let validator = @moonschema.Schema::new(schema)
  for
    text in [
      " { \"b\" \t: true }\r\n", "{\"a\" : 12 ,\n\"b\":false}", "{\"b\":true , \"c\" : null}",
      "{ \"a\":0 , \"b\":true , \"c\":null }",
    ] {
    assert_true(dfa.accepts(text))
    assert_true(validator.valid(@json.parse(text)))
  }
  for
    text in [
      "{ }", "{\"a\":1}", "{ , \"b\":true}", "{\"b\":true , }", "{\"b\":true ,, \"c\":null}",
      "{\"b\":true \"c\":null}", "{\"b\":true,\"x\":0}", "{\"b\":true,\"b\":false}",
    ] {
    assert_false(dfa.accepts(text))
  }
}

///|
test "empty containers and bounded arrays allow structural whitespace" {
  let empty_schemas : Array[Json] = [
    { "type": "object" },
    { "type": "array", "items": { "type": "null" }, "maxItems": 0 },
  ]
  for i, schema in empty_schemas {
    let dfa = @schema.compile(schema, whitespace=true)
    assert_true(
      dfa.accepts(if i == 0 { " { \t\r\n } " } else { " [ \t\r\n ] " }),
    )
    assert_false(dfa.accepts(if i == 0 { "{ , }" } else { "[ null ]" }))
  }
  for min in [0, 1, 2] {
    let schema : Json = {
      "type": "array",
      "items": { "type": "integer" },
      "minItems": min.to_json(),
      "maxItems": 2,
    }
    let dfa = @schema.compile(schema, whitespace=true)
    assert_eq(dfa.accepts("[ ]"), min == 0)
    assert_eq(dfa.accepts("[ 1 ]"), min <= 1)
    assert_true(dfa.accepts("[ 1 ,\n 2 ]"))
    for text in ["[ , ]", "[1, ]", "[,1]", "[1 2]", "[1,,2]", "[1,2,3]"] {
      assert_false(dfa.accepts(text))
    }
  }
}

///|
test "nested refs and anyOf inherit whitespace including ref siblings" {
  let schema : Json = {
    "$defs": {
      "row": { "type": "array", "items": { "type": "integer" }, "minItems": 1 },
      "alias": { "$ref": "#/$defs/row" },
    },
    "type": "object",
    "properties": {
      "data": { "anyOf": [{ "$ref": "#/$defs/alias" }, { "type": "null" }] },
    },
    "required": ["data"],
  }
  let dfa = @schema.compile(schema, whitespace=true)
  assert_true(dfa.accepts(" { \"data\" : [ 1 , -2 ] } "))
  assert_true(dfa.accepts("{ \"data\" : null }"))
  assert_false(dfa.accepts("{ \"data\" : [ ] }"))
  let siblings : Array[Json] = [
    {
      "$defs": { "v": { "type": "array", "items": { "type": "integer" } } },
      "$ref": "#/$defs/v",
      "const": [1, 2],
    },
    {
      "$defs": { "v": { "enum": [[1, 2], [3]] } },
      "$ref": "#/$defs/v",
      "enum": [[1, 2]],
    },
  ]
  for schema in siblings {
    let dfa = @schema.compile(schema, whitespace=true)
    assert_true(dfa.accepts("\n[ 1 , 2 ]\t"))
    assert_false(dfa.accepts("[ 3 ]"))
    assert_false(dfa.accepts("[ 1 , 2 , ]"))
  }
}

///|
test "const and enum tokenize punctuation only outside JSON strings" {
  let value : Json = { "a": [1, { "s": "x,:[{}]\\\"y" }], "b": {} }
  let schemas : Array[Json] = [{ "const": value }, { "enum": [value] }]
  for schema in schemas {
    let dfa = @schema.compile(schema, whitespace=true)
    let text = " { \"a\" : [ 1 , { \"s\" : \"x,:[{}]\\\\\\\"y\" } ] , \"b\" : { } } "
    assert_true(dfa.accepts(text))
    assert_true(@moonschema.Schema::new(schema).valid(@json.parse(text)))
    assert_false(
      dfa.accepts("{\"a\":[1,{\"s\":\"x ,:[{}]\\\\\\\"y\"}],\"b\":{}}"),
    )
  }
}

///|
test "whitespace does not relax numbers or string length and patterns" {
  let number = @schema.compile({ "type": "number" }, whitespace=true)
  assert_true(number.accepts(" \t-12.5e+2\n"))
  for text in ["- 1", "1 2", "1 .2", "1. 2", "1e 2", "1e+ 2", "01", "1."] {
    assert_false(number.accepts(text))
  }
  let text = @schema.compile(
    { "type": "string", "minLength": 2, "maxLength": 2, "pattern": "[a-z]{2}" },
    whitespace=true,
  )
  assert_true(text.accepts(" \"ab\" \n"))
  for bad in ["\"a b\"", "\"a\"", "\"abc\"", "\"a\tb\"", "\"a\nb\""] {
    assert_false(text.accepts(bad))
  }
  let literal = @schema.compile({ "const": " a b " }, whitespace=true)
  assert_true(literal.accepts(" \" a b \" "))
  assert_false(literal.accepts("\"ab\""))
}

///|
test "whitespace ref string siblings retain all constraints" {
  let schema : Json = {
    "$defs": { "s": { "type": "string", "pattern": "[a-z]{2}" } },
    "$ref": "#/$defs/s",
    "minLength": 2,
    "maxLength": 2,
  }
  let dfa = @schema.compile(schema, whitespace=true)
  assert_true(dfa.accepts(" \"ab\"\n"))
  for text in ["\"a\"", "\"abc\"", "\"a \"", "\"12\""] {
    assert_false(dfa.accepts(text))
  }
}
