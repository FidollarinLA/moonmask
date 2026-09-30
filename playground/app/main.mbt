///|
using @html {
  div,
  span,
  button,
  text,
  nothing,
  pre,
  select,
  option,
  textarea,
  a,
  type Html,
}

///|
using @rabbita {type Emit, type Cmd}

///|
const GPT2_URL : String = "https://huggingface.co/openai-community/gpt2/resolve/607a30d783dfa663caf39e06633721c8d4cfcd7e/tokenizer.json"

///|
const REPO_URL : String = "https://github.com/FidollarinLA/moonmask"

///|
enum Outcome {
  Going
  Complete(Bool)
  Broke
  Stuck
  Cut
} derive(Eq)

///|
struct Rng {
  id : Int
  rand : @random.Rand
}

///|
impl Eq for Rng with fn equal(a, b) {
  a.id == b.id
}

///|
/// `states[i]` is the automaton state before token `i`; the last one is current.
/// After `Broke` the last token led nowhere and has no state of its own.
struct Run {
  masked : Bool
  seed : Int
  rng : Rng
  tokens : Array[Int]
  states : Array[Int]
  outcome : Outcome
} derive(Eq)

///|
struct Bench {
  samples : Int
  masked_valid : Int
  masked_len : Double
  unmasked_valid : Int
  unmasked_len : Double
  millis : Double
  example : String
} derive(Eq)

///|
enum VocabState {
  Toy
  Loading
  Gpt2
  Failed(String)
} derive(Eq)

///|
struct Model {
  mode : Mode
  whitespace : Bool
  preset : Int
  source : String
  edits : Int
  lexicon : Lexicon
  vocab_state : VocabState
  engine : Result[Engine, String]
  run : Run
  playing : Bool
  speed : Int
  budget : Int
  bench : Bench?
  next_id : Int
} derive(Eq)

///|
enum Msg {
  SetMode(Mode)
  SetWhitespace(Bool)
  SetPreset(String)
  Edit(String)
  Recompile(Int)
  SetMasked(Bool)
  Step
  Tick
  TogglePlay
  Reset
  Reroll
  Choose(Int)
  SetSpeed(String)
  LoadGpt2
  Gpt2Loaded(Result[(String, Bytes), Error])
  UseToy
  RunBench
}

///|
fn start_state(engine : Result[Engine, String]) -> Int {
  match engine {
    Ok(e) => e.guide.start()
    Err(_) => 0
  }
}

///|
fn fresh_run(
  id : Int,
  masked : Bool,
  seed : Int,
  engine : Result[Engine, String],
) -> Run {
  {
    masked,
    seed,
    rng: { id, rand: @random.Rand::chacha8(seed=seed_bytes(seed)), },
    tokens: [],
    states: [start_state(engine)],
    outcome: Going,
  }
}

///|
fn Run::state(self : Run) -> Int {
  self.states[self.states.length() - 1]
}

///|
/// One more token: `pick` when the user chose it, otherwise what the monkey picks.
fn Run::advance(self : Run, engine : Engine, budget : Int, pick : Int?) -> Run {
  guard self.outcome is Going else { return self }
  let g = engine.guide
  let v = g.vocab
  let state = self.state()
  let step = self.tokens.length()
  let id = match pick {
    Some(id) => id
    None if self.masked =>
      match
        @mask.monkey_step(g, self.rng.rand, state, step~, max_tokens=budget) {
        Some(id) => id
        None => return { ..self, outcome: Stuck, }
      }
    None => {
      if step >= budget {
        return { ..self, outcome: Cut, }
      }
      self.rng.rand.int(limit=v.size())
    }
  }
  let tokens = self.tokens.copy()
  tokens.push(id)
  if id == v.eos {
    return {
      ..self,
      tokens,
      outcome: Complete(engine.check(text_of(v, tokens))),
    }
  }
  match g.advance(state, id) {
    Some(next) => {
      let states = self.states.copy()
      states.push(next)
      { ..self, tokens, states, }
    }
    None => { ..self, tokens, outcome: Broke, }
  }
}

///|
fn init_model() -> Model {
  let lexicon = { id: 0, vocab: toy_vocab(), }
  let source = schema_presets[0].source
  let engine = compile(Schema, source, lexicon, 1)
  {
    mode: Schema,
    whitespace: false,
    preset: 0,
    source,
    edits: 0,
    lexicon,
    vocab_state: Toy,
    engine,
    run: fresh_run(2, true, 42, engine),
    playing: false,
    speed: 180,
    budget: 64,
    bench: None,
    next_id: 3,
  }
}

///|
/// Recompiles the constraint and restarts decoding, keeping the seed and mode.
fn Model::rebuild(self : Model) -> Model {
  let engine = compile(
    self.mode,
    self.source,
    self.lexicon,
    self.next_id,
    whitespace=self.whitespace,
  )
  {
    ..self,
    engine,
    run: fresh_run(self.next_id + 1, self.run.masked, self.run.seed, engine),
    playing: false,
    bench: None,
    next_id: self.next_id + 2,
  }
}

///|
fn Model::restart(self : Model, masked~ : Bool, seed~ : Int) -> Model {
  {
    ..self,
    run: fresh_run(self.next_id, masked, seed, self.engine),
    next_id: self.next_id + 1,
  }
}

///|
fn Model::step(self : Model, pick : Int?) -> Model {
  match self.engine {
    Ok(e) => {
      let run = self.run.advance(e, self.budget, pick)
      { ..self, run, playing: self.playing && run.outcome is Going, }
    }
    Err(_) => { ..self, playing: false, }
  }
}

///|
fn run_bench(engine : Engine, budget : Int, samples : Int) -> Bench {
  let t0 = now_ms()
  let rand = @random.Rand::chacha8(seed=seed_bytes(20260929))
  let mut masked_valid = 0
  let mut masked_len = 0
  let mut example = ""
  for _ in 0..<samples {
    let s = @mask.monkey(engine.guide, rand, max_tokens=budget)
    masked_len = masked_len + s.tokens.length()
    if s.finished && engine.check(s.text) {
      masked_valid = masked_valid + 1
      if example == "" {
        example = @utf8.decode_lossy(s.text)
      }
    }
  }
  let mut unmasked_valid = 0
  let mut unmasked_len = 0
  for _ in 0..<samples {
    let s = @mask.monkey_unmasked(engine.guide.vocab, rand, max_tokens=budget)
    unmasked_len = unmasked_len + s.tokens.length()
    if s.finished && engine.check(s.text) {
      unmasked_valid = unmasked_valid + 1
    }
  }
  {
    samples,
    masked_valid,
    masked_len: masked_len.to_double() / samples.to_double(),
    unmasked_valid,
    unmasked_len: unmasked_len.to_double() / samples.to_double(),
    millis: now_ms() - t0,
    example,
  }
}

///|
fn load_gpt2(bytes : Bytes) -> @vocab.Vocab raise {
  @vocab.from_tokenizer(
    @tokenizer.from_buffer(bytes),
    eos_token="<|endoftext|>",
  )
}

///|
fn update(model : Model, msg : Msg, emit : Emit[Msg]) -> (Model, Cmd) {
  match msg {
    SetWhitespace(whitespace) =>
      ({ ..model, whitespace, }.rebuild(), @rabbita.none)
    SetMode(mode) if mode == model.mode => (model, @rabbita.none)
    SetMode(mode) =>
      (
        { ..model, mode, preset: 0, source: presets(mode)[0].source, }.rebuild(),
        @rabbita.none,
      )
    SetPreset(value) => {
      let i = @string.parse_int(value) catch { _ => 0 }
      let list = presets(model.mode)
      let i = if i >= 0 && i < list.length() { i } else { 0 }
      ({ ..model, preset: i, source: list[i].source, }.rebuild(), @rabbita.none)
    }
    Edit(source) => {
      let edits = model.edits + 1
      ({ ..model, source, edits, }, @rabbita.delay(emit(Recompile(edits)), 350))
    }
    Recompile(n) if n == model.edits => (model.rebuild(), @rabbita.none)
    Recompile(_) => (model, @rabbita.none)
    SetMasked(masked) =>
      (model.restart(masked~, seed=model.run.seed), @rabbita.none)
    Step => (model.step(None), @rabbita.none)
    Tick if model.playing => (model.step(None), @rabbita.none)
    Tick => (model, @rabbita.none)
    TogglePlay =>
      if model.playing {
        ({ ..model, playing: false, }, @rabbita.none)
      } else if model.run.outcome is Going {
        ({ ..model, playing: true, }, @rabbita.none)
      } else {
        let m = model.restart(masked=model.run.masked, seed=model.run.seed + 1)
        ({ ..m, playing: true, }, @rabbita.none)
      }
    Reset =>
      (
        {
          ..model.restart(masked=model.run.masked, seed=model.run.seed),
          playing: false,
        },
        @rabbita.none,
      )
    Reroll =>
      (
        model.restart(masked=model.run.masked, seed=model.run.seed + 1),
        @rabbita.none,
      )
    Choose(id) => (model.step(Some(id)), @rabbita.none)
    SetSpeed(value) => {
      let speed = @string.parse_int(value) catch { _ => 180 }
      ({ ..model, speed, }, @rabbita.none)
    }
    LoadGpt2 =>
      (
        { ..model, vocab_state: Loading, },
        @http.get(GPT2_URL).expect_bytes(emit.map(r => Gpt2Loaded(r))),
      )
    Gpt2Loaded(Ok((_, bytes))) =>
      try load_gpt2(bytes) catch {
        e => ({ ..model, vocab_state: Failed(e.to_string()), }, @rabbita.none)
      } noraise {
        vocab => {
          let lexicon = { id: model.next_id, vocab, }
          (
            { ..model, lexicon, vocab_state: Gpt2, next_id: model.next_id + 1, }.rebuild(),
            @rabbita.none,
          )
        }
      }
    Gpt2Loaded(Err(e)) =>
      ({ ..model, vocab_state: Failed(e.to_string()), }, @rabbita.none)
    UseToy => {
      let lexicon = { id: model.next_id, vocab: toy_vocab(), }
      (
        { ..model, lexicon, vocab_state: Toy, next_id: model.next_id + 1, }.rebuild(),
        @rabbita.none,
      )
    }
    RunBench =>
      match model.engine {
        Ok(e) =>
          (
            { ..model, bench: Some(run_bench(e, model.budget, 30)), },
            @rabbita.none,
          )
        Err(_) => (model, @rabbita.none)
      }
  }
}

///|
fn subscriptions(model : Model, emit : Emit[Msg]) -> @sub.Sub {
  if model.playing {
    @sub.every(model.speed, emit(Tick))
  } else {
    @sub.none
  }
}

///|
fn main {
  @rabbita.elmish(model=init_model(), view~, update~, subscriptions~).mount(
    "app",
  )
}
