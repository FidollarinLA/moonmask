# Changelog

## Unreleased

- Object properties outside `required` may be omitted; declaration order is kept and no stray comma is produced.
- `mask::monkey_step` picks a single token, so callers can drive decoding one step at a time; `monkey` is built on it and samples exactly as before.
- Browser playground (`playground/`, MoonBit + rabbita): constraint editor, token-by-token decoding with and without the mask, token-mask view, DFA neighbourhood graph and the monkey experiment, deployed to GitHub Pages.

## 0.1.0

- Byte-level regex engine: parser, Thompson NFA, subset-construction DFA with dead-state pruning and distances.
- JSON Schema subset compiler; unsupported keywords are rejected. Integers are capped at 15 digits so sampled documents parse as exact JSON numbers.
- GPT-2 byte-level vocabulary loader on top of tokenizers-moonbit.
- Per-state token masks and a budget-aware monkey sampler.
- Monkey typewriter experiment CLI.
