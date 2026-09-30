"""Fetch the pinned GPT-2 tokenizer with SHA-256 verification (Python stdlib)."""
import hashlib
from pathlib import Path
import urllib.request

REV = "607a30d783dfa663caf39e06633721c8d4cfcd7e"
SHA = "8414cab924d8b9b33013f0d221c5862f365ee9be39c5c2bfae8a5a9e970478a6"
OUT = Path(__file__).resolve().parents[1] / "assets/gpt2/tokenizer.json"


def main():
    if OUT.exists() and hashlib.sha256(OUT.read_bytes()).hexdigest() == SHA:
        print("Tokenizer already verified:", OUT)
        return
    with urllib.request.urlopen(f"https://huggingface.co/openai-community/gpt2/resolve/{REV}/tokenizer.json", timeout=60) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != SHA:
        raise ValueError("Tokenizer checksum mismatch; existing file was not overwritten")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    temporary = OUT.with_suffix(".json.part")
    temporary.write_bytes(data)
    temporary.replace(OUT)
    print("Downloaded and verified:", OUT)


if __name__ == "__main__":
    main()
