#!/usr/bin/env bash
set -euo pipefail
REV=607a30d783dfa663caf39e06633721c8d4cfcd7e
SHA=8414cab924d8b9b33013f0d221c5862f365ee9be39c5c2bfae8a5a9e970478a6
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/assets/gpt2/tokenizer.json"
mkdir -p "$(dirname "$OUT")"
curl -fsSL -o "$OUT" "https://huggingface.co/openai-community/gpt2/resolve/$REV/tokenizer.json"
if command -v sha256sum >/dev/null 2>&1; then
  echo "$SHA  $OUT" | sha256sum -c -
else
  echo "$SHA  $OUT" | shasum -a 256 -c -
fi
