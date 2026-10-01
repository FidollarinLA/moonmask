# Real model logits, selected by MoonBit

This example runs a real [DistilGPT-2](https://huggingface.co/distilbert/distilgpt2) model on CPU. Python/PyTorch computes each next-token logit vector. A local Node child process runs the compiled **MoonBit** schema compiler, vocabulary loader, token guide, `Guide::greedy` selection, state transitions and moonschema validation. Python independently validates the final raw UTF-8 bytes with `jsonschema`.

No HTTP service, ChatGPT bridge or model API key is needed. This example is separate from the browser Playground, which still uses random sampling.

## Run

Requirements: MoonBit **moonc >= 0.10.14**, Node.js 24, Python 3.12 and CPU PyTorch. From the repository root, prepare an isolated environment:

```bash
python -m venv _local/model-venv
# Windows: _local/model-venv/Scripts/python.exe
# Unix:    _local/model-venv/bin/python
```

Using that environment's Python, install PyTorch following its [official installation selector](https://pytorch.org/get-started/locally/), then `pip install -r examples/logits/requirements.txt`. For example on Windows PowerShell:

```powershell
_local/model-venv/Scripts/python.exe -m pip install torch --index-url https://download.pytorch.org/whl/cpu
_local/model-venv/Scripts/python.exe -m pip install -r examples/logits/requirements.txt
moon update
_local/model-venv/Scripts/python.exe examples/logits/run.py --max-tokens 64
_local/model-venv/Scripts/python.exe examples/logits/run.py --max-tokens 64 --finish-after 32 --output _local/logits-completion.json
```

Both commands build `cmd/logits` for JS, download the same fixed model revision on first use, then run compact, whitespace and unmasked cases with the same prompt and hard token limit. Default cache and reports stay under ignored `_local/`. Use a standard MoonBit installation on your PATH; no private setup script is required. For subsequent offline runs, `--model-dir PATH` accepts a complete local model directory; its hashes are recorded without assuming provenance.

Model revision: `2290a62682d06624634c1f46a6ad5be0f47f38aa`. Only safetensors weights are loaded, with `trust_remote_code=False`. The driver compares the full tokenizer token-ID mapping, vocabulary size and EOS ID before decoding. The model card declares Apache-2.0; model weights remain outside this repository. The inference packages are used as dependencies, not copied implementations.

The provided prompt uses English few-shot sentiment examples because DistilGPT-2 is an English base model, not an instruction-tuned model. Change `--schema` and `--prompt` to test other supported constraints. This is one integration demonstration, not evidence of general task accuracy.

## Completion is separate from valid syntax

The default is pure greedy selection among allowed tokens. `--finish-after N` explicitly changes the policy from step N: select only tokens that strictly decrease DFA byte distance, or EOS alone when already accepting. The highest eligible model logit still wins. The baseline does not apply this policy; all cases have the same hard cap.

The report distinguishes `ended`, `accepting`, independent validation and `complete_valid`. A document can parse and validate yet fail `complete_valid` because it hit the token limit without EOS. No forced repair, output trimming or JSON extraction is performed.

In the recorded run:

| Policy | Compact | Whitespace | Unmasked |
| --- | --- | --- | --- |
| Pure greedy, 64-token cap | valid, EOS, 11 tokens | valid JSON but no EOS, 64 tokens | invalid full output, no EOS, 64 tokens |
| Finish after 32, same cap | valid, EOS, 11 tokens | valid, EOS, 33 tokens | same unmasked result |

Compact output: `{"sentiment":"positive","confidence":"high"}`. Pure whitespace decoding continued emitting newlines; completion mode used one explicit finishing step to emit EOS. Unmasked decoding continued into another review example. See [recorded evidence](../../docs/logits-demo.md).

Each trace includes raw top-1 token and score, whether it was allowed at that prefix, selected token/score/rank, DFA states, EOS, and whether the completion policy applied. `allowed_count` counts the schema mask before completion-policy filtering. Once the unmasked prefix is dead, its `raw_allowed` stays false; these counts are not a paired causal comparison of identical prefixes. Timings include CPU inference and JSON IPC and are not a performance benchmark.

## Multi-case regression

`corpus.json` contains four hand-authored tasks: negative sentiment, a nested tool call with `$ref` and `const`, an ordered bounded array, and an empty array with a boolean flag. Each has an explicit expected value. Run the complete corpus offline against the same local model:

```powershell
_local/model-venv/Scripts/python.exe examples/logits/suite.py --model-dir _local/models/distilgpt2
```

Without `--model-dir`, the existing driver downloads the pinned revision. The default runs both pure greedy and explicit completion after step 32, with a shared 64-token cap. Each task/policy is repeated twice across compact, whitespace and unmasked modes (48 generations). The model is loaded in a fresh process for each repeat. All raw reports and the summary remain in `_local/logits-suite/`; `--output-dir` selects another directory.

`summary.json` separates schema validity, validity plus EOS, full parsed expected-value match, and expected match plus EOS. Repeat runs do not inflate the denominator. Every repeat must match the first token/logit/state trace exactly; wall time is excluded. A mismatch exits unsuccessfully and preserves the summary and individual reports. A model's wrong answer or failure to finish is recorded as an outcome rather than causing the harness to hide the remaining cases. Setup, protocol and validator errors stop the run.

These few-shot tasks test integration coverage, not general model accuracy. Completion narrows the allowed tokens and can affect the answer; schema validity alone does not establish semantic correctness. No repair or JSON substring extraction is used. The scoring tests run without model dependencies:

```bash
python -m unittest discover -s examples/logits -p test_suite.py -v
```

## Library API

```moonbit
let token = guide.greedy(state, logits) // Array[Double], one score per token
// Optional explicit completion policy:
let final_token = guide.greedy(state, logits, finish=true)
```

The input vector is unchanged. Scores must be finite or negative infinity. NaN, positive infinity, wrong vector dimensions and invalid states are errors. Negative infinity suppresses a token. Ties choose the lowest ID. `None` means no eligible unsuppressed token; it does not mean EOS. EOS is returned only when accepting, and must be handled separately from `Guide::advance`.

## Protocol and tests

The child process accepts one JSON object per line and emits one response per line. Only one request may be outstanding per client. Operations:

- `init`: `tokenizer` (JSON string), `schema` (JSON object), optional `whitespace` (bool).
- `reset`: clears accumulated bytes, state and EOS while reusing the compiled constraint.
- `greedy`: `logits` (array of numbers, `null` for negative infinity), optional `finish`; chooses **and advances**. Optional `raw_token` reports whether the model's top candidate was allowed.
- `advance`: `token` ID; an observational unmasked path that may enter dead state `-1`. It never claims early EOS is valid.
- `result`: exact accumulated bytes, display text, accepting/ended flags and moonschema validity.

Errors return `{"error":"..."}` and leave the existing session unchanged. EOF ends the child. Model-free tests exercise the real compiled executable and only need the fixed GPT-2 tokenizer fixture:

```bash
./scripts/fetch-gpt2.sh
moon check --target js --deny-warn
moon build --target js --release cmd/logits
python -m unittest discover -s examples/logits -p test_protocol.py -v
```

CI runs this protocol check on Windows and Linux without downloading weights or requiring PyTorch. Real-model evidence is generated separately by the commands above.
