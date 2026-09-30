///|
// Transport only: the decoder, score selection and validation below are MoonBit.
extern "js" fn serve(handler : (String) -> String) -> Unit =
  #| (handler) => {
  #|   const readline = require('node:readline');
  #|   const input = readline.createInterface({input: process.stdin, crlfDelay: Infinity});
  #|   input.on('line', line => process.stdout.write(handler(line) + '\n'));
  #| }

///|
struct Session {
  guide : @mask.Guide
  validator : @moonschema.Schema
  mut state : Int
  mut ended : Bool
  bytes : Buffer
}

///|
fn Session::accepting(self : Session) -> Bool {
  self.state >= 0 && self.guide.is_accept(self.state)
}

///|
fn Session::allowed_count(self : Session) -> Int {
  if self.state < 0 || self.ended {
    0
  } else {
    self.guide.allowed(self.state).length()
  }
}

///|
fn Session::advance(self : Session, token : Int) -> Unit raise {
  if self.ended {
    fail("session already ended; reset before decoding")
  }
  if token < 0 || token >= self.guide.vocab.size() {
    fail("token id is out of range")
  }
  if token == self.guide.vocab.eos {
    self.ended = true
  } else {
    if self.state >= 0 {
      self.state = self.guide.advance(self.state, token).unwrap_or(-1)
    }
    self.bytes.write_bytes(self.guide.vocab.tokens[token])
  }
}

///|
fn required(fields : Map[String, Json], name : String) -> Json raise {
  match fields.get(name) {
    Some(value) => value
    None => fail("missing field: " + name)
  }
}

///|
fn flag(fields : Map[String, Json], name : String) -> Bool raise {
  match fields.get(name) {
    None | Some(False) => false
    Some(True) => true
    _ => fail("expected boolean: " + name)
  }
}

///|
fn initialize(fields : Map[String, Json]) -> Session raise {
  guard required(fields, "tokenizer") is String(source) else {
    fail("expected tokenizer JSON string")
  }
  let schema = required(fields, "schema")
  let tokenizer = @tokenizer.from_buffer(@utf8.encode(source))
  let vocab = @vocab.from_tokenizer(tokenizer, eos_token="<|endoftext|>")
  let dfa = @schema.compile(schema, whitespace=flag(fields, "whitespace"))
  {
    guide: @mask.Guide::new(dfa, vocab),
    validator: @moonschema.Schema::new(schema),
    state: dfa.start,
    ended: false,
    bytes: Buffer(),
  }
}

///|
fn dispatch(
  session : Session,
  op : String,
  fields : Map[String, Json],
) -> Json raise {
  if op == "reset" {
    session.state = session.guide.start()
    session.ended = false
    session.bytes.reset()
    return {
      "state": session.state.to_json(),
      "accepting": session.accepting().to_json(),
    }
  }
  if op == "result" {
    let bytes = session.bytes.to_bytes()
    let valid = try
      session.validator.valid(@json.parse(@utf8.decode(bytes)))
    catch {
      _ => false
    } noraise {
      result => result
    }
    let raw : Array[Int] = []
    for b in bytes {
      raw.push(b.to_int())
    }
    return {
      "state": session.state.to_json(),
      "accepting": session.accepting().to_json(),
      "ended": session.ended.to_json(),
      "valid": valid.to_json(),
      "text": @utf8.decode_lossy(bytes).to_json(),
      "bytes": raw.to_json(),
    }
  }
  let before = session.state
  let allowed_count = session.allowed_count()
  let raw_allowed : Json = match fields.get("raw_token") {
    None => (None : Int?).to_json()
    Some(Number(n, ..)) if n >= 0.0 &&
      n < session.guide.vocab.size().to_double() &&
      n == n.floor() =>
      (before >= 0 &&
      !session.ended &&
      session.guide.allowed(before).contains(n.to_int())).to_json()
    _ => fail("invalid raw_token id")
  }
  let token = if op == "greedy" {
    if session.ended {
      fail("session already ended; reset before decoding")
    }
    guard required(fields, "logits") is Array(values) else {
      fail("expected logits array")
    }
    let scores : Array[Double] = []
    for value in values {
      match value {
        Number(score, ..) => scores.push(score)
        Null => scores.push(@double.neg_infinity)
        _ => fail("expected numeric logits or null for negative infinity")
      }
    }
    session.guide.greedy(session.state, scores, finish=flag(fields, "finish"))
  } else if op == "advance" {
    guard required(fields, "token") is Number(n, ..) &&
      n >= 0.0 &&
      n < session.guide.vocab.size().to_double() &&
      n == n.floor() else {
      fail("invalid token id")
    }
    Some(n.to_int())
  } else {
    fail("unknown operation")
  }
  if token is Some(id) {
    session.advance(id)
  }
  let token_json = match token {
    Some(id) => id.to_json()
    None => (None : Int?).to_json()
  }
  return {
    "token": token_json,
    "state_before": before.to_json(),
    "state": session.state.to_json(),
    "accepting": session.accepting().to_json(),
    "ended": session.ended.to_json(),
    "allowed_count": allowed_count.to_json(),
    "raw_allowed": raw_allowed,
  }
}

///|
fn main {
  let mut session : Session? = None
  serve(line => {
    let response : Json = try {
      guard @json.parse(line) is Object(fields) else { fail("expected object") }
      guard required(fields, "op") is String(op) else {
        fail("expected op string")
      }
      if op == "init" {
        // Only replace the current session after initialization succeeds.
        let initialized = initialize(fields)
        session = Some(initialized)
        {
          "vocab_size": initialized.guide.vocab.size().to_json(),
          "eos": initialized.guide.vocab.eos.to_json(),
          "state": initialized.state.to_json(),
          "allowed_count": initialized.allowed_count().to_json(),
        }
      } else {
        guard session is Some(current) else { fail("initialize first") }
        dispatch(current, op, fields)
      }
    } catch {
      error => { "error": error.to_string().to_json() }
    }
    response.stringify()
  })
}
