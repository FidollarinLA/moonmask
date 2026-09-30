"""Run a small, versioned real-model regression corpus, preserving every trace."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from client import ROOT


def reject_constant(value):
    raise ValueError(f"Non-JSON numeric constant: {value}")


def strict_equal(left, right):
    """JSON structural equality, without Python's True == 1 coercion."""
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(strict_equal(left[k], right[k]) for k in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(strict_equal(a, b) for a, b in zip(left, right))
    return left == right


def score(case, expected):
    # Never extract a JSON substring, strip model prose, or repair the output.
    try:
        value = json.loads(case["text"], parse_constant=reject_constant)
        matches = case["independent_valid"] and strict_equal(value, expected)
    except ValueError:
        matches = False
    return {"schema_valid": bool(case["independent_valid"]),
            "complete_valid": bool(case["complete_valid"]),
            "expected_match": bool(matches),
            "complete_expected_match": bool(matches and case["complete_valid"])}


def fingerprint(case):
    # Wall time is deliberately excluded; all token/logit/state evidence is kept.
    stable = {k: v for k, v in case.items() if k != "elapsed_seconds"}
    return hashlib.sha256(json.dumps(stable, sort_keys=True, ensure_ascii=True,
                                    allow_nan=False).encode()).hexdigest()


def summarize(rows):
    groups = []
    for policy in ("pure", "completion"):
        for mode in ("compact", "whitespace", "unmasked"):
            selected = [r for r in rows if r["policy"] == policy and r["mode"] == mode]
            if not selected:
                continue
            first = [r for r in selected if r["repeat"] == 0]
            groups.append({"policy": policy, "mode": mode, "cases": len(first),
                           **{key: sum(r[key] for r in first) for key in
                              ("schema_valid", "complete_valid", "expected_match", "complete_expected_match")},
                           "repeat_consistent": all(len({r["fingerprint"] for r in selected if r["id"] == base["id"]}) == 1 for base in first)})
    return groups


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, default=Path(__file__).with_name("corpus.json"))
    parser.add_argument("--output-dir", type=Path, default=ROOT / "_local/logits-suite")
    parser.add_argument("--model-dir", type=Path)
    parser.add_argument("--max-tokens", type=int, default=64)
    parser.add_argument("--finish-after", type=int, default=32)
    parser.add_argument("--repeats", type=int, default=2)
    args = parser.parse_args()
    args.output_dir = args.output_dir.resolve()
    if args.model_dir:
        args.model_dir = args.model_dir.resolve()
    if args.repeats < 2 or not 0 <= args.finish_after < args.max_tokens:
        parser.error("repeats >= 2 and 0 <= finish-after < max-tokens required")
    corpus_bytes = args.corpus.read_bytes()
    corpus = json.loads(corpus_bytes)
    ids = [case["id"] for case in corpus]
    if not corpus or len(set(ids)) != len(ids) or any(not name or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789_-" for c in name) for name in ids):
        parser.error("corpus requires unique, safe lowercase case IDs")
    import jsonschema
    for case in corpus:
        jsonschema.Draft202012Validator.check_schema(case["schema"])
        jsonschema.Draft202012Validator(case["schema"]).validate(case["expected"])
    args.output_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run(["moon", "build", "--target", "js", "--release", "cmd/logits"], cwd=ROOT, check=True)
    rows = []
    for case in corpus:
        folder = args.output_dir / case["id"]
        folder.mkdir(exist_ok=True)
        schema = folder / "schema.json"
        prompt = folder / "prompt.txt"
        schema.write_text(json.dumps(case["schema"]), encoding="utf-8")
        prompt.write_text(case["prompt"], encoding="utf-8")
        for policy in ("pure", "completion"):
            for repeat in range(args.repeats):
                output = folder / f"{policy}-{repeat}.json"
                command = [sys.executable, str(Path(__file__).with_name("run.py")), "--skip-build",
                           "--schema", str(schema), "--prompt", str(prompt), "--output", str(output),
                           "--max-tokens", str(args.max_tokens)]
                if args.model_dir:
                    command += ["--model-dir", str(args.model_dir)]
                if policy == "completion":
                    command += ["--finish-after", str(args.finish_after)]
                subprocess.run(command, cwd=ROOT, check=True)
                report_bytes = output.read_bytes()
                report = json.loads(report_bytes)
                for result in report["cases"]:
                    rows.append({"id": case["id"], "policy": policy, "repeat": repeat,
                                 "mode": result["mode"], **score(result, case["expected"]),
                                 "tokens": result["tokens"], "reason": result["reason"],
                                 "fingerprint": fingerprint(result),
                                 "report": output.relative_to(args.output_dir).as_posix()})
    summary = {"corpus_sha256": hashlib.sha256(corpus_bytes).hexdigest(),
               "max_tokens": args.max_tokens, "finish_after": args.finish_after,
               "repeats": args.repeats, "groups": summarize(rows), "runs": rows,
               "scope": "Small hand-authored integration corpus, not a model accuracy benchmark. Counts use first repeats only. Expected match compares the entire parsed value; syntax and EOS are separate. Timing is not scored."}
    (args.output_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary["groups"], indent=2), flush=True)
    if not all(g["repeat_consistent"] for g in summary["groups"]):
        raise SystemExit("Repeated token/logit/state evidence differs; inspect reports")


if __name__ == "__main__":
    main()
