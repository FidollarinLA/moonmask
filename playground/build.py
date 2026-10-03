"""Build the MoonBit playground and a standalone historical-logits viewer."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


def strict_equal(left, right):
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(strict_equal(left[k], right[k]) for k in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(strict_equal(a, b) for a, b in zip(left, right))
    return left == right


def load_evidence():
    folder = ROOT / "examples/logits/evidence/suite"
    manifest = json.loads((folder / "sha256.json").read_text(encoding="utf-8"))
    # The evidence manifest specifies canonical JSON, independent of CRLF/LF.
    reports = {}
    for name, expected in manifest["files"].items():
        document = json.loads((folder / name).read_text(encoding="utf-8"))
        canonical = json.dumps(document, sort_keys=True, separators=(",", ":"),
                               ensure_ascii=True, allow_nan=False).encode("ascii")
        if hashlib.sha256(canonical).hexdigest() != expected:
            raise ValueError(f"Evidence checksum mismatch: {name}")
        reports[name] = document
    corpus = json.loads((ROOT / "examples/logits/corpus.json").read_text(encoding="utf-8"))
    summary = reports["summary.json"]
    tasks = []
    for task in corpus:
        policies = {}
        for policy in ("pure", "completion"):
            name = f'{task["id"]}/{policy}-0.json'
            report = reports[name]
            if report["schema"] != task["schema"] or report["prompt"] != task["prompt"].rstrip("\r\n"):
                raise ValueError(f"Corpus/report mismatch: {name}")
            scores = {r["mode"]: r for r in summary["runs"]
                      if r["id"] == task["id"] and r["policy"] == policy and r["repeat"] == 0}
            for case in report["cases"]:
                try:
                    value = json.loads(case["text"])
                    matches = case["independent_valid"] and strict_equal(value, task["expected"])
                except ValueError:
                    matches = False
                if scores[case["mode"]]["expected_match"] != matches:
                    raise ValueError(f"Expected-answer/score mismatch: {name}")
            policies[policy] = {"report": report, "scores": scores}
        tasks.append({**task, "policies": policies})
    return {"tasks": tasks, "summary": summary}


def main():
    data = load_evidence()  # Fail before changing dist if evidence is inconsistent.
    subprocess.run(["moon", "build", "--target", "js", "--release"], cwd=HERE, check=True)
    dist = HERE / "dist"
    dist.mkdir(exist_ok=True)
    for name in ("index.html", "style.css"):
        shutil.copyfile(HERE / name, dist / name)
    shutil.copyfile(HERE / "_build/js/release/build/FidollarinLA/moonmask-playground/app/app.js", dist / "app.js")
    # Escape '<' so prompts/schema cannot terminate the JSON script element.
    payload = json.dumps(data, ensure_ascii=True, allow_nan=False).replace("<", "\\u003c")
    template = (HERE / "traces.html").read_text(encoding="utf-8")
    if template.count("__EVIDENCE_JSON__") != 1:
        raise ValueError("Expected exactly one evidence placeholder")
    (dist / "traces.html").write_text(template.replace("__EVIDENCE_JSON__", payload), encoding="utf-8")
    print(f"Built {dist}: MoonBit app + verified historical model traces")


if __name__ == "__main__":
    main()
