"""Real CPU model logits -> MoonBit greedy decoding -> independent validation.

No model-generated commands are executed. The engine is a local child process,
not a network service. Only fixed-revision safetensors weights are auto-downloaded.
"""
import argparse
import hashlib
import importlib.metadata
import json
import platform
from pathlib import Path
import subprocess
import time

from client import Decoder, ENGINE, ROOT

MODEL = "distilbert/distilgpt2"
REVISION = "2290a62682d06624634c1f46a6ad5be0f47f38aa"


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def reject_constant(value):
    raise ValueError(f"Non-JSON numeric constant: {value}")


def run_case(decoder, model, tokenizer, torch, validator, prompt_ids, mode, args):
    decoder.request("reset")
    current = prompt_ids
    past = None
    trace = []
    reason = "token_limit"
    started = time.perf_counter()
    with torch.inference_mode():
        for step in range(args.max_tokens):
            outputs = model(input_ids=current, past_key_values=past, use_cache=True)
            past = outputs.past_key_values
            logits = outputs.logits[0, -1, :].float().cpu()
            if not torch.isfinite(logits).all():
                raise ValueError("Model returned non-finite logits")
            raw = int(torch.argmax(logits))  # First (lowest id) wins ties.
            finishing = mode != "unmasked" and args.finish_after is not None and step >= args.finish_after
            if mode == "unmasked":
                result = decoder.request("advance", token=raw, raw_token=raw)
            else:
                result = decoder.request("greedy", logits=logits.tolist(), finish=finishing, raw_token=raw)
            token = result["token"]
            event = {"step": step, "finishing": finishing, "raw_token": raw,
                     "raw_logit": float(logits[raw]), **result}
            if token is None:
                trace.append(event)
                reason = "no_candidate"
                break
            event.update(
                chosen_logit=float(logits[token]),
                chosen_rank=1 + int((logits > logits[token]).sum())
                + int((logits[:token] == logits[token]).sum()),
                token_display=tokenizer.decode([token], clean_up_tokenization_spaces=False),
            )
            trace.append(event)
            if result["ended"]:
                reason = "eos"
                break
            current = torch.tensor([[token]], dtype=torch.long)
    final = decoder.request("result")
    raw_bytes = bytes(final.pop("bytes"))
    independent = False
    try:
        value = json.loads(raw_bytes.decode("utf-8"), parse_constant=reject_constant)
        independent = validator.is_valid(value)
    except (UnicodeDecodeError, ValueError):
        pass
    if final["valid"] != independent:
        raise AssertionError("MoonBit moonschema and Python jsonschema disagree")
    complete = final["ended"] and final["accepting"] and independent
    return {"mode": mode, "reason": reason, "complete_valid": complete,
            "independent_valid": independent, "tokens": len(trace),
            "raw_top1_blocked_steps": sum(row["raw_allowed"] is False for row in trace),
            "completion_policy_steps": sum(row["finishing"] for row in trace),
            "elapsed_seconds": time.perf_counter() - started, **final, "trace": trace}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, help="Use local weights; report records file hashes instead of claiming their origin")
    parser.add_argument("--cache-dir", type=Path, default=ROOT / "_local/huggingface")
    parser.add_argument("--schema", type=Path, default=Path(__file__).with_name("schema.json"))
    parser.add_argument("--prompt", type=Path, default=Path(__file__).with_name("prompt.txt"))
    parser.add_argument("--output", type=Path, default=ROOT / "_local/logits-report.json")
    parser.add_argument("--max-tokens", type=int, default=96)
    parser.add_argument("--finish-after", type=int, default=None,
                        help="Opt-in distance-decreasing completion after this many tokens; default: pure masked greedy")
    parser.add_argument("--threads", type=int, default=2)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()
    if args.max_tokens <= 0 or args.threads <= 0 or (args.finish_after is not None and not 0 <= args.finish_after < args.max_tokens):
        parser.error("positive budget/threads required; finish-after must be within the budget")

    import torch
    import jsonschema
    from huggingface_hub import snapshot_download
    from transformers import AutoModelForCausalLM, AutoTokenizer

    if not args.skip_build:
        subprocess.run(["moon", "build", "--target", "js", "--release", "cmd/logits"], cwd=ROOT, check=True)
    if args.model_dir:
        folder = args.model_dir.resolve()
        source = {"kind": "local_files", "name": folder.name}
    else:
        folder = Path(snapshot_download(MODEL, revision=REVISION, cache_dir=args.cache_dir,
                      allow_patterns=["config.json", "model.safetensors", "tokenizer.json", "tokenizer_config.json", "vocab.json", "merges.txt", "README.md"]))
        source = {"kind": "huggingface", "id": MODEL, "revision": REVISION}
    torch.set_num_threads(args.threads)
    torch.manual_seed(args.seed)
    torch.use_deterministic_algorithms(True)
    tokenizer = AutoTokenizer.from_pretrained(folder, local_files_only=True, trust_remote_code=False)
    model = AutoModelForCausalLM.from_pretrained(folder, local_files_only=True, trust_remote_code=False,
                                                use_safetensors=True, attn_implementation="eager").cpu().eval()
    schema_text = args.schema.read_text(encoding="utf-8")
    schema = json.loads(schema_text)
    jsonschema.Draft202012Validator.check_schema(schema)
    validator = jsonschema.Draft202012Validator(schema)
    prompt = args.prompt.read_text(encoding="utf-8").rstrip("\r\n")
    prompt_ids = tokenizer(prompt, return_tensors="pt").input_ids
    if prompt_ids.shape[1] + args.max_tokens > model.config.n_positions:
        raise ValueError("prompt + generation budget exceeds the model context window")
    tokenizer_source = (folder / "tokenizer.json").read_text(encoding="utf-8")
    stored_vocab = json.loads(tokenizer_source)["model"]["vocab"]
    if tokenizer.get_vocab() != stored_vocab:
        raise ValueError("loaded tokenizer IDs differ from the tokenizer supplied to MoonBit")
    if model.config.vocab_size != len(tokenizer):
        raise ValueError("model and tokenizer vocabulary sizes differ")
    cases = []
    with Decoder() as decoder:
        for mode in ("compact", "whitespace", "unmasked"):
            info = decoder.request("init", tokenizer=tokenizer_source, schema=schema, whitespace=mode != "compact")
            if info["vocab_size"] != len(tokenizer) or info["eos"] != tokenizer.eos_token_id:
                raise ValueError("MoonBit and model vocabulary/EOS mismatch")
            case = run_case(decoder, model, tokenizer, torch, validator, prompt_ids, mode, args)
            cases.append(case)
            print(json.dumps({k: case[k] for k in ("mode", "reason", "complete_valid", "tokens", "raw_top1_blocked_steps", "text")}, ensure_ascii=True), flush=True)
    report = {
        "model_source": source,
        "model_files_sha256": {name: sha256(folder / name) for name in ("model.safetensors", "config.json", "tokenizer.json")},
        "engine_sha256": sha256(ENGINE),
        "versions": {name: importlib.metadata.version(name) for name in ("torch", "transformers", "tokenizers", "huggingface-hub", "safetensors", "jsonschema")},
        "runtime": {"python": platform.python_version(), "os": platform.system(), "architecture": platform.machine(),
                    "node": subprocess.check_output(["node", "--version"], text=True).strip(), "torch": torch.__version__},
        "device": "cpu", "dtype": "float32", "attention": "eager", "threads": args.threads,
        "seed": args.seed, "decoding": "greedy; lowest token ID wins ties; no random sampling",
        "max_tokens": args.max_tokens, "finish_after": args.finish_after,
        "prompt": prompt, "prompt_token_ids": prompt_ids[0].tolist(), "schema": schema,
        "cases": cases,
        "scope": "Integration evidence, not a general model-quality or performance benchmark. Both baselines share the hard token cap; only masked modes apply the opt-in completion policy.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Trace report: {args.output}", flush=True)


if __name__ == "__main__":
    main()
