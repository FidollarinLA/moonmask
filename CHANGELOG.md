# Changelog

## 0.1.0 — 2026-10-01

First mooncakes release. Requires moonc 0.10.14 or newer.

- Historical real-model trace viewer with task/policy/mode controls, per-token navigation, separate schema/EOS/answer indicators and visible failure cases. Cross-platform Playground build verifies evidence hashes and corpus alignment before publishing the static page.

- Multi-case real-logit regression runner with four versioned prompt/schema/expected-answer fixtures, pure/completion policies, repeated trace checks, and separate structure/EOS/answer scores. Model-free scoring tests join the protocol CI job.
- `Guide::greedy` selects the highest allowed model logit with stable token-ID tie breaking, validation, EOS gating, suppression via negative infinity and an explicit optional distance-decreasing completion policy.
- Real CPU DistilGPT-2 example in `examples/logits/`: MoonBit decoding over a local JSON-lines process, pinned model revision, per-step traces, independent JSON Schema validation and a same-hard-cap unmasked comparison. Model-free protocol tests are included in CI.
- Optional JSON whitespace through `schema::compile(..., whitespace=true)` and `schema::to_regex(..., whitespace=true)`. Compact output remains the default. Only SP, TAB, CR and LF are allowed at structural boundaries and document edges, including nested containers, literals and references.
- CLI `--whitespace` and Playground compact/whitespace controls; changing the policy resets decoding and benchmark results. Tests cover malformed separators, required properties, scalar constraints, token masks, EOS and budget-driven termination.
- Object properties outside `required` may be omitted; declaration order is kept and no stray comma is produced.
- `mask::monkey_step` picks a single token, so callers can drive decoding one step at a time; `monkey` is built on it and samples exactly as before.
- Browser playground (`playground/`, MoonBit + rabbita): constraint editor, token-by-token decoding with and without the mask, token-mask view, DFA neighbourhood graph and the monkey experiment, deployed to GitHub Pages.

- Byte-level regex engine: parser, Thompson NFA, subset-construction DFA with dead-state pruning and distances.
- JSON Schema subset compiler; unsupported keywords are rejected. Integers are capped at 15 digits so sampled documents parse as exact JSON numbers.
- GPT-2 byte-level vocabulary loader on top of tokenizers-moonbit.
- Per-state token masks and a budget-aware monkey sampler.
- Monkey typewriter experiment CLI.
