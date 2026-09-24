///|
let runs : Int = 100

///|
let seed : Bytes = b"moonmask-monkey-typewriter-00042"

///|
fn is_valid(text : Bytes, validator : @moonschema.Schema) -> Bool {
  try {
    let value = @json.parse(@utf8.decode(text))
    validator.valid(value)
  } catch {
    _ => false
  } noraise {
    ok => ok
  }
}

///|
fn preview(text : Bytes) -> String {
  let buf = StringBuilder()
  let mut n = 0
  for c in @utf8.decode_lossy(text) {
    if n == 100 {
      buf.write_string("...")
      break
    }
    buf.write_char(c)
    n += 1
  }
  buf.to_string()
}

///|
fn run(args : Array[String]) -> Unit raise {
  let tok = @tokenizer.from_file(args[1])
  let vocab = @vocab.from_tokenizer(tok, eos_token="<|endoftext|>")
  println("vocab size: \{vocab.size()}, runs per schema: \{runs}")
  println("")
  println(
    "| schema | masked valid | unmasked valid | avg tokens (masked) | DFA states |",
  )
  println("| --- | --- | --- | --- | --- |")
  let samples : Array[String] = []
  for path in args[2:] {
    let schema = @json.parse(@fs.read_file_to_string(path))
    let dfa = @schema.compile(schema)
    let guide = @mask.Guide::new(dfa, vocab)
    let validator = @moonschema.Schema::new(schema)
    let rand = @random.Rand::chacha8(seed~)
    let mut masked_ok = 0
    let mut unmasked_ok = 0
    let mut total_tokens = 0
    for k in 0..<runs {
      let out = @mask.monkey(guide, rand, max_tokens=256)
      if out.finished && is_valid(out.text, validator) {
        masked_ok += 1
      }
      total_tokens += out.tokens.length()
      let raw = @mask.monkey_unmasked(vocab, rand, max_tokens=64)
      if is_valid(raw.text, validator) {
        unmasked_ok += 1
      }
      if k == 0 {
        samples.push("\{path} masked:   \{preview(out.text)}")
        samples.push("\{path} unmasked: \{preview(raw.text)}")
      }
    }
    let avg = total_tokens.to_double() / runs.to_double()
    println(
      "| \{path} | \{masked_ok}/\{runs} | \{unmasked_ok}/\{runs} | \{avg} | \{dfa.state_count()} |",
    )
  }
  println("")
  for s in samples {
    println(s)
  }
}

///|
fn main {
  let args = @env.args()
  if args.length() < 3 {
    println("usage: moon run cmd/main -- <tokenizer.json> <schema.json>...")
    panic()
  }
  run(args) catch {
    e => {
      println("moonmask: \{e}")
      panic()
    }
  }
}
