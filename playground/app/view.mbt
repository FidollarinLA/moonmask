///|
fn view(model : Model, emit : Emit[Msg]) -> Html {
  div(class="app", [
    view_header(model, emit),
    view_pipeline(model),
    div(class="grid", [
      view_editor(model, emit),
      view_stream(model, emit),
      view_mask(model, emit),
      view_graph(model),
      view_bench(model, emit),
    ]),
    view_footer(),
  ])
}

///|
fn card(
  cls : String,
  num : String,
  title : String,
  sub : String,
  body : Array[Html],
) -> Html {
  let head = div(class="card-head", [
    span(class="num", num),
    span(class="card-title", title),
    span(class="card-sub", sub),
  ])
  @html.section(class="card " + cls, [head, ..body])
}

///|
fn with_commas(n : Int) -> String {
  let s = n.to_string()
  let out = StringBuilder()
  let len = s.length()
  for i, c in s {
    if i > 0 && (len - i) % 3 == 0 {
      out.write_char(',')
    }
    out.write_char(c)
  }
  out.to_string()
}

///|
fn view_header(model : Model, emit : Emit[Msg]) -> Html {
  let v = model.lexicon.vocab
  let toy_cls = if model.vocab_state is Toy { "pill on" } else { "pill" }
  let gpt_cls = if model.vocab_state is Gpt2 { "pill on" } else { "pill" }
  let gpt_label = match model.vocab_state {
    Loading => "GPT-2 · downloading…"
    Gpt2 => "GPT-2 · " + with_commas(v.size()) + " tokens"
    Failed(_) => "GPT-2 · retry"
    Toy => "GPT-2 · 50,257 tokens"
  }
  let toy_label = if model.vocab_state is Toy {
    "Toy · " + v.size().to_string() + " tokens"
  } else {
    "Toy vocab"
  }
  @html.header(class="top", [
    div(class="brand", [
      div(class="logo", "◐"),
      div([
        div(class="name", [text("moonmask"), span(class="tag", "playground")]),
        div(
          class="tagline",
          "Constrained decoding for LLMs, compiled to a byte-level DFA. Everything below runs in your browser — written in MoonBit.",
        ),
      ]),
    ]),
    div(class="top-right", [
      span(class="label", "Vocabulary"),
      button(class=toy_cls, on_click=emit(UseToy), toy_label),
      button(
        class=gpt_cls,
        disabled=model.vocab_state is (Loading | Gpt2),
        on_click=emit(LoadGpt2),
        gpt_label,
      ),
      a(class="gh", href=REPO_URL, "GitHub ↗"),
    ]),
    match model.vocab_state {
      Failed(msg) => div(class="warn", "Could not load GPT-2: " + msg)
      _ => nothing
    },
  ])
}

///|
fn view_pipeline(model : Model) -> Html {
  let states = match model.engine {
    Ok(e) => with_commas(e.dfa.state_count()) + " states"
    Err(_) => "—"
  }
  let steps = [
    (model.mode.label(), "constraint"),
    ("regex", "one pattern"),
    ("NFA → DFA", states),
    ("token mask", with_commas(model.lexicon.vocab.size()) + " tokens"),
    ("sampler", "masked logits"),
  ]
  let items = []
  for i, s in steps {
    if i > 0 {
      items.push(span(class="arrow", "→"))
    }
    items.push(
      div(class="stage", [
        div(class="stage-name", s.0),
        div(class="stage-note", s.1),
      ]),
    )
  }
  div(class="pipeline", items)
}

///|
fn view_editor(model : Model, emit : Emit[Msg]) -> Html {
  let tabs = [Schema, Regex, Grammar].map(m => {
    let cls = if m == model.mode { "tab on" } else { "tab" }
    button(class=cls, on_click=emit(SetMode(m)), m.label())
  })
  let options = []
  for i, p in presets(model.mode) {
    options.push(
      option(value=i.to_string(), selected=i == model.preset, p.name),
    )
  }
  let status = match model.engine {
    Ok(e) =>
      div(class="status ok", [
        span(class="dot", ""),
        text(
          "compiled · " +
          with_commas(e.dfa.state_count()) +
          " DFA states · " +
          fixed(e.millis, 1) +
          " ms · checked by " +
          e.judge(),
        ),
      ])
    Err(msg) => div(class="status err", [span(class="dot", ""), text(msg)])
  }
  card("editor", "1", "Constraint", "约束", [
    div(class="tabs", tabs),
    select(class="preset", on_change=emit.map(v => SetPreset(v)), options),
    textarea(
      class="code",
      value=model.source,
      rows=18,
      on_input=emit.map(s => Edit(s)),
      attrs=@html.Attrs::build().spellcheck(false),
      "",
    ),
    status,
    match model.engine {
      Ok({ pattern: Some(p), .. }) =>
        div(class="regex", [
          div(
            class="regex-head",
            "compiled to one regex · " + with_commas(p.length()) + " chars",
          ),
          pre(class="regex-body", clip(p, 700)),
        ])
      _ => nothing
    },
  ])
}

///|
fn view_stream(model : Model, emit : Emit[Msg]) -> Html {
  let run = model.run
  let seg = div(class="seg", [
    button(
      class=if run.masked { "on good" } else { "" },
      on_click=emit(SetMasked(true)),
      "✓ masked",
    ),
    button(
      class=if run.masked { "" } else { "on bad" },
      on_click=emit(SetMasked(false)),
      "✗ unmasked",
    ),
  ])
  let play_label = if model.playing { "⏸ Pause" } else { "▶ Play" }
  let speeds = [("60", "fast"), ("180", "normal"), ("500", "slow")].map(p => {
    option(value=p.0, selected=p.0 == model.speed.to_string(), p.1)
  })
  let toolbar = div(class="toolbar", [
    seg,
    button(class="btn primary", on_click=emit(TogglePlay), play_label),
    button(class="btn", on_click=emit(Step), "Step"),
    button(class="btn", on_click=emit(Reset), "Reset"),
    button(class="btn", on_click=emit(Reroll), "New seed"),
    select(class="speed", on_change=emit.map(v => SetSpeed(v)), speeds),
    span(class="seed", "seed " + run.seed.to_string()),
  ])
  match model.engine {
    Err(_) =>
      card("stream", "2", "Decoding", "逐 token 生成", [
        toolbar,
        div(class="empty", "Fix the constraint to start decoding."),
      ])
    Ok(e) => {
      let v = e.guide.vocab
      let chips = []
      let last = run.tokens.length() - 1
      for i, id in run.tokens {
        let broken = i == last && run.outcome is Broke
        let cls = if id == v.eos {
          "tok eos"
        } else if broken {
          "tok bad"
        } else {
          "tok c" + (i % 6).to_string()
        }
        chips.push(
          span(class=cls, title="token #" + id.to_string(), token_text(v, id)),
        )
      }
      if run.outcome is Going {
        chips.push(span(class="caret", ""))
      }
      let outcome = match run.outcome {
        Going if run.tokens.length() == 0 =>
          span(class="badge", "press Play or Step")
        Going => span(class="badge", "generating…")
        Complete(true) =>
          span(class="badge good", "✓ complete and valid (" + e.judge() + ")")
        Complete(false) =>
          span(class="badge bad", "✗ stopped early — not a valid output")
        Broke =>
          span(
            class="badge bad",
            "✗ token " +
            run.tokens.length().to_string() +
            " fell off the automaton — no way to finish",
          )
        Stuck => span(class="badge bad", "✗ nothing can make progress")
        Cut => span(class="badge bad", "✗ budget used up without eos")
      }
      let state = run.state()
      let stats = div(class="stats", [
        stat("tokens", run.tokens.length().to_string()),
        stat("state", state.to_string()),
        stat("steps to accept", e.dfa.distance(state).to_string()),
        stat("bytes", text_of(v, run.tokens).length().to_string()),
        outcome,
      ])
      card("stream", "2", "Decoding", "逐 token 生成", [
        toolbar,
        div(class="tokens", chips),
        stats,
        pre(class="raw", @utf8.decode_lossy(text_of(v, run.tokens))),
      ])
    }
  }
}

///|
fn stat(label : String, value : String) -> Html {
  div(class="stat", [span(class="stat-v", value), span(class="stat-l", label)])
}

///|
fn view_mask(model : Model, emit : Emit[Msg]) -> Html {
  guard model.engine is Ok(e) else {
    return card("mask", "3", "Token mask", "掩码", [div(class="empty", "—")])
  }
  let v = e.guide.vocab
  let state = model.run.state()
  let allowed = e.guide.allowed(state)
  let k = allowed.length()
  let total = v.size()
  let pct = k.to_double() * 100.0 / total.to_double()
  let width = if pct < 0.6 && k > 0 { 0.6 } else { pct }
  let shown = allowed.length().min(90)
  let chips = []
  for i in 0..<shown {
    let id = allowed[i]
    let cls = if id == v.eos { "chip eos" } else { "chip" }
    chips.push(
      button(
        class=cls,
        title="token #" + id.to_string() + " — click to emit it",
        disabled=!(model.run.outcome is Going),
        on_click=emit(Choose(id)),
        token_text(v, id),
      ),
    )
  }
  if k > shown {
    chips.push(span(class="more", "+" + with_commas(k - shown) + " more"))
  }
  let note = if model.run.masked {
    "Every other token gets logit −∞, so the sampler cannot pick it."
  } else {
    "Mask off: the sampler draws from all " +
    with_commas(total) +
    " tokens, and " +
    fixed(100.0 - pct, 1) +
    "% of them would break the output here."
  }
  card("mask", "3", "Token mask", "掩码 · state " + state.to_string(), [
    div(class="big", [
      span(class="big-k", with_commas(k)),
      span(class="big-of", " / " + with_commas(total) + " tokens allowed"),
      span(class="big-pct", fixed(pct, 2) + "%"),
    ]),
    div(class="bar", [
      div(class="fill", style=["width:" + fixed(width, 2) + "%"], ""),
    ]),
    div(class="note", note),
    div(class="chips", chips),
    div(class="hint", "Click a token to play the LLM yourself."),
  ])
}

///|
fn view_graph(model : Model) -> Html {
  guard model.engine is Ok(e) else {
    return card("graph", "4", "Automaton", "自动机", [
      div(class="empty", "—"),
    ])
  }
  let run = model.run
  let v = e.guide.vocab
  let focus = run.state()
  let (nodes, edges) = neighbourhood(e.dfa, focus, depth=2, per_layer=5)
  let ahead : Map[Int, Unit] = Map::from_array(nodes.map(n => (n.state, ())))
  // The last two moves that led here, newest first: (state, token that left it).
  let trail : Array[(Int, Int)] = []
  let mut i = run.states.length() - 2
  while i >= 0 && trail.length() < 2 {
    let s = run.states[i]
    if ahead.contains(s) || trail.any(t => t.0 == s) {
      break
    }
    trail.push((s, run.tokens[i]))
    i = i - 1
  }
  let w = 960
  let h = 340
  let back = trail.length()
  let layers = nodes.fold(init=0, (n, x) => n.max(x.layer + 1))
  let columns = back + layers.max(if run.outcome is Broke { 2 } else { 1 })
  let gap = if columns > 1 { ((w - 140) / (columns - 1)).min(230) } else { 0 }
  let x0 = (w - gap * (columns - 1)) / 2
  let column_x = c => x0 + c * gap
  let pos : Map[Int, (Int, Int)] = Map::from_array([])
  for d in 0..<layers {
    let col = nodes.filter(x => x.layer == d)
    for i, n in col {
      pos[n.state] = (
        column_x(back + d),
        (h - 20) * (i + 1) / (col.length() + 1) + 10,
      )
    }
  }
  for k, t in trail {
    pos[t.0] = (column_x(back - 1 - k), h / 2)
  }
  let arrow = @svg.defs([
    @svg.marker(
      id="arrow",
      attrs=@svg.Attrs::build()
        .view_box("0 0 10 10")
        .ref_x("10")
        .ref_y("5")
        .marker_width("7")
        .marker_height("7")
        .orient("auto"),
      [@svg.path(d="M 0 0 L 10 5 L 0 10 z", fill="#7c86a2")],
    ),
  ])
  let shapes = [arrow]
  for ed in edges {
    let (x1, y1) = pos[ed.src]
    let (x2, y2) = pos[ed.dst]
    let sx = x1 + 20
    let tx = x2 - 21
    let mx = (sx + tx) / 2
    let d = "M \{sx} \{y1} C \{mx} \{y1}, \{mx} \{y2}, \{tx} \{y2}"
    shapes.push(
      @svg.path(
        class="edge",
        d~,
        fill="none",
        attrs=@svg.Attrs::build().marker_end("url(#arrow)"),
      ),
    )
    let t = 0.72
    let u = 1.0 - t
    let lx = (sx.to_double() * u * u * u +
    3.0 * mx.to_double() * u * t +
    tx.to_double() * t * t * t).to_int()
    let ly = y1 +
      ((y2 - y1).to_double() * (3.0 * t * t - 2.0 * t * t * t)).to_int() -
      5
    shapes.push(
      @svg.g([
        @svg.title([@svg.text(ed.label)]),
        @svg.svg_text(
          class="elabel",
          x=lx,
          y=ly,
          text=clip(ed.label, 16),
          attrs=@svg.Attrs::build().text_anchor("middle"),
        ),
      ]),
    )
  }
  let token_label = (id : Int, x : Int, y : Int) => {
    @svg.g([
      @svg.title([@svg.text("token #" + id.to_string())]),
      @svg.svg_text(
        class="tlabel",
        x~,
        y~,
        text=clip(token_text(v, id), 14),
        attrs=@svg.Attrs::build().text_anchor("middle"),
      ),
    ])
  }
  for k, t in trail {
    let (x1, y1) = pos[t.0]
    let (x2, y2) = if k == 0 { pos[focus] } else { pos[trail[k - 1].0] }
    shapes.push(
      @svg.path(
        class="edge trail",
        d="M \{x1 + 20} \{y1} L \{x2 - 21} \{y2}",
        fill="none",
        attrs=@svg.Attrs::build().marker_end("url(#arrow)"),
      ),
    )
    shapes.push(token_label(t.1, (x1 + x2) / 2, y1 - 10))
    shapes.push(@svg.circle(class="node past", cx=x1, cy=y1, r=19))
    shapes.push(
      @svg.svg_text(
        class="nlabel",
        x=x1,
        y=y1 + 4,
        text=t.0.to_string(),
        attrs=@svg.Attrs::build().text_anchor("middle"),
      ),
    )
  }
  if run.outcome is Broke {
    let (fx, fy) = pos[focus]
    let dx = column_x(back + 1)
    let dy = h - 26
    shapes.push(
      @svg.path(
        class="edge dead",
        d="M \{fx + 14} \{fy + 14} Q \{fx + 20} \{dy}, \{dx - 21} \{dy}",
        fill="none",
      ),
    )
    shapes.push(
      token_label(
        run.tokens[run.tokens.length() - 1],
        (fx + dx) / 2 + 10,
        dy - 10,
      ),
    )
    shapes.push(@svg.circle(class="node deadnode", cx=dx, cy=dy, r=19))
    shapes.push(
      @svg.svg_text(
        class="nlabel",
        x=dx,
        y=dy + 4,
        text="✗",
        attrs=@svg.Attrs::build().text_anchor("middle"),
      ),
    )
  }
  for n in nodes {
    let (x, y) = pos[n.state]
    let accept = e.dfa.is_accept(n.state)
    let cls = if n.state == focus { "node focus" } else { "node" }
    if accept {
      shapes.push(@svg.circle(class="ring", cx=x, cy=y, r=24, fill="none"))
    }
    shapes.push(@svg.circle(class=cls, cx=x, cy=y, r=19))
    shapes.push(
      @svg.svg_text(
        class="nlabel",
        x~,
        y=y + 4,
        text=n.state.to_string(),
        attrs=@svg.Attrs::build().text_anchor("middle"),
      ),
    )
    shapes.push(
      @svg.svg_text(
        class="ndist",
        x=x + 24,
        y=y - 6,
        text="d=" + e.dfa.distance(n.state).to_string(),
      ),
    )
    match n.loop_label {
      Some(label) => {
        shapes.push(
          @svg.path(
            class="edge",
            d="M \{x - 9} \{y - 17} C \{x - 22} \{y - 48}, \{x + 22} \{y - 48}, \{x + 9} \{y - 17}",
            fill="none",
            attrs=@svg.Attrs::build().marker_end("url(#arrow)"),
          ),
        )
        shapes.push(
          @svg.g([
            @svg.title([@svg.text(label)]),
            @svg.svg_text(
              class="elabel",
              x~,
              y=y - 44,
              text=clip(label, 14),
              attrs=@svg.Attrs::build().text_anchor("middle"),
            ),
          ]),
        )
      }
      None => ()
    }
    if n.hidden > 0 {
      shapes.push(
        @svg.svg_text(
          class="hidden",
          x=x + 24,
          y=y + 12,
          text="+" + n.hidden.to_string(),
        ),
      )
    }
  }
  card(
    "graph",
    "4",
    "Automaton",
    "自动机 · neighbourhood of state " + focus.to_string(),
    [
      @svg.svg(class="fsm", view_box="0 0 \{w} \{h}", shapes),
      div(class="legend", [
        span(class="lg past", "just visited (edge = token emitted)"),
        span(class="lg focus", "current state"),
        span(class="lg ring", "accepting"),
        span(class="lg dead", "dead — output can no longer finish"),
        span(class="lg", "d = bytes still needed"),
        span(class="lg", "+n = edges off-screen"),
      ]),
    ],
  )
}

///|
fn bench_row(
  label : String,
  cls : String,
  valid : Int,
  samples : Int,
  avg : Double,
) -> Html {
  let pct = valid.to_double() * 100.0 / samples.to_double()
  div(class="brow", [
    span(class="blabel", label),
    div(class="btrack", [
      div(
        class="bfill " + cls,
        style=["width:" + fixed(pct.max(1.0), 1) + "%"],
        "",
      ),
    ]),
    span(
      class="bval",
      valid.to_string() + " / " + samples.to_string() + " valid",
    ),
    span(class="bavg", fixed(avg, 1) + " tokens avg"),
  ])
}

///|
fn view_bench(model : Model, emit : Emit[Msg]) -> Html {
  let body = match model.bench {
    None =>
      [
        div(
          class="note",
          "A monkey picks tokens uniformly at random. With the mask it can only pick legal ones; without it, it just types. Both are checked by the same validator.",
        ),
      ]
    Some(b) =>
      [
        bench_row("masked", "good", b.masked_valid, b.samples, b.masked_len),
        bench_row(
          "unmasked",
          "bad",
          b.unmasked_valid,
          b.samples,
          b.unmasked_len,
        ),
        div(
          class="note",
          "\{b.samples} + \{b.samples} samples in " +
          fixed(b.millis, 0) +
          " ms, budget \{model.budget} tokens. First valid masked sample:",
        ),
        pre(class="raw", if b.example == "" { "—" } else { b.example }),
      ]
  }
  card(
    "bench",
    "5",
    "Monkey typewriter",
    "猴子打字机",
    [
      div(class="toolbar", [
        button(
          class="btn primary",
          disabled=model.engine is Err(_),
          on_click=emit(RunBench),
          "Run 30 + 30 samples",
        ),
      ]),
      ..body,
    ],
  )
}

///|
fn view_footer() -> Html {
  @html.footer(class="foot", [
    text("Built with "),
    a(href="https://www.moonbitlang.com", "MoonBit"),
    text(" + "),
    a(href="https://github.com/moonbit-community/rabbita", "rabbita"),
    text(" · tokenizer by "),
    a(
      href="https://mooncakes.io/docs/howtomakeaname/tokenizers-moonbit",
      "tokenizers-moonbit",
    ),
    text(" · validation by "),
    a(href="https://mooncakes.io/docs/moonbitstack/moonschema", "moonschema"),
    text(
      " · token chips inspired by tiktokenizer, FSM view inspired by Outlines. ",
    ),
    a(href=REPO_URL, "Source on GitHub"),
  ])
}
