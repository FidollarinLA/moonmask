///|
enum Mode {
  Schema
  Regex
  Grammar
} derive(Eq)

///|
fn Mode::label(self : Mode) -> String {
  match self {
    Schema => "JSON Schema"
    Regex => "Regex"
    Grammar => "GBNF"
  }
}

///|
struct Preset {
  name : String
  source : String
}

///|
fn presets(mode : Mode) -> Array[Preset] {
  match mode {
    Schema => schema_presets
    Regex => regex_presets
    Grammar => grammar_presets
  }
}

///|
let schema_presets : Array[Preset] = [
  {
    name: "user · enum + integer + boolean",
    source: (
      #|{
      #|  "type": "object",
      #|  "properties": {
      #|    "name": { "type": "string", "minLength": 1, "maxLength": 12 },
      #|    "age": { "type": "integer" },
      #|    "role": { "enum": ["admin", "editor", "viewer"] },
      #|    "active": { "type": "boolean" }
      #|  },
      #|  "required": ["name", "age", "role", "active"],
      #|  "additionalProperties": false
      #|}
    ),
  },
  {
    name: "tool_call · anyOf + const",
    source: (
      #|{
      #|  "anyOf": [
      #|    {
      #|      "type": "object",
      #|      "properties": {
      #|        "tool": { "const": "get_weather" },
      #|        "args": {
      #|          "type": "object",
      #|          "properties": {
      #|            "city": { "type": "string", "minLength": 2, "maxLength": 10 },
      #|            "unit": { "enum": ["c", "f"] }
      #|          },
      #|          "required": ["city", "unit"],
      #|          "additionalProperties": false
      #|        }
      #|      },
      #|      "required": ["tool", "args"],
      #|      "additionalProperties": false
      #|    },
      #|    {
      #|      "type": "object",
      #|      "properties": {
      #|        "tool": { "const": "search" },
      #|        "args": {
      #|          "type": "object",
      #|          "properties": {
      #|            "query": { "type": "string", "minLength": 1, "maxLength": 16 },
      #|            "top_k": { "type": "integer" }
      #|          },
      #|          "required": ["query", "top_k"],
      #|          "additionalProperties": false
      #|        }
      #|      },
      #|      "required": ["tool", "args"],
      #|      "additionalProperties": false
      #|    }
      #|  ]
      #|}
    ),
  },
  {
    name: "order · nested array + nullable",
    source: (
      #|{
      #|  "type": "object",
      #|  "properties": {
      #|    "order_id": { "type": "string", "minLength": 4, "maxLength": 8 },
      #|    "items": {
      #|      "type": "array",
      #|      "minItems": 1,
      #|      "maxItems": 3,
      #|      "items": {
      #|        "type": "object",
      #|        "properties": {
      #|          "sku": { "type": "string", "minLength": 1, "maxLength": 6 },
      #|          "qty": { "type": "integer" }
      #|        },
      #|        "required": ["sku", "qty"],
      #|        "additionalProperties": false
      #|      }
      #|    },
      #|    "note": { "type": ["string", "null"], "maxLength": 10 }
      #|  },
      #|  "required": ["order_id", "items", "note"],
      #|  "additionalProperties": false
      #|}
    ),
  },
  {
    name: "todo · optional properties",
    source: (
      #|{
      #|  "type": "object",
      #|  "properties": {
      #|    "id": { "type": "integer" },
      #|    "title": { "type": "string", "minLength": 1, "maxLength": 10 },
      #|    "done": { "type": "boolean" },
      #|    "tag": { "enum": ["work", "home"] }
      #|  },
      #|  "required": ["id", "done"],
      #|  "additionalProperties": false
      #|}
    ),
  },
]

///|
let regex_presets : Array[Preset] = [
  {
    name: "ISO date",
    source: "20[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])",
  },
  {
    name: "email-ish",
    source: "[a-z]{2,8}(\\.[a-z]{2,6})?@[a-z]{2,6}\\.(com|org|cn)",
  },
  {
    name: "semver",
    source: "(0|[1-9][0-9]{0,2})\\.(0|[1-9][0-9]{0,2})\\.(0|[1-9][0-9]{0,2})",
  },
  { name: "hex color", source: "#([0-9a-f]{3}|[0-9a-f]{6})", },
]

///|
let grammar_presets : Array[Preset] = [
  {
    name: "tiny SQL",
    source: (
      #|root  ::= "SELECT " cols " FROM " table where?
      #|cols  ::= "*" | col (", " col){0,2}
      #|col   ::= "id" | "name" | "age" | "city"
      #|table ::= "users" | "orders"
      #|where ::= " WHERE " col " " op " " num
      #|op    ::= "=" | ">" | "<"
      #|num   ::= [1-9] [0-9]{0,2}
    ),
  },
  {
    name: "arithmetic (bounded)",
    source: (
      #|root ::= term (" " op " " term){0,3}
      #|term ::= num | "(" num " " op " " num ")"
      #|op   ::= "+" | "-" | "*" | "/"
      #|num  ::= "0" | [1-9] [0-9]{0,3}
    ),
  },
  {
    name: "log line",
    source: (
      #|root  ::= "[" level "] " time " " msg
      #|level ::= "INFO" | "WARN" | "ERROR"
      #|time  ::= [0-2] [0-9] ":" [0-5] [0-9]
      #|msg   ::= [a-z] [a-z ]{2,20}
    ),
  },
]
