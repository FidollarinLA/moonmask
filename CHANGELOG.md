# Changelog

## 0.1.0

- Byte-level regex engine: parser, Thompson NFA, subset-construction DFA with dead-state pruning and distances.
- JSON Schema subset compiler; unsupported keywords are rejected. Integers are capped at 15 digits so sampled documents parse as exact JSON numbers.
- GPT-2 byte-level vocabulary loader on top of tokenizers-moonbit.
- Per-state token masks and a budget-aware monkey sampler.
- Monkey typewriter experiment CLI.
