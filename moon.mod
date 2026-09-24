name = "FidollarinLA/moonmask"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/FidollarinLA/moonmask"

license = "Apache-2.0"

keywords = [
  "llm",
  "constrained-decoding",
  "structured-output",
  "json-schema",
  "regex",
  "dfa",
]

preferred_target = "wasm"

description = "Constrained decoding for LLMs in MoonBit: compile JSON Schema and regex to byte-level DFAs and mask invalid tokens."

import {
  "howtomakeaname/tokenizers-moonbit@0.13.1",
  "moonbitlang/regexp@0.3.5",
  "moonbitstack/moonschema@0.2.0",
  "moonbitlang/x@0.5.5",
}
