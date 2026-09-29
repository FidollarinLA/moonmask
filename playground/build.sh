#!/usr/bin/env bash
# Builds the playground into playground/dist, ready to serve as static files.
set -euo pipefail
cd "$(dirname "$0")"
moon build --target js --release
rm -rf dist
mkdir -p dist
cp index.html style.css dist/
cp _build/js/release/build/FidollarinLA/moonmask-playground/app/app.js dist/app.js
echo "built playground/dist ($(du -h dist/app.js | cut -f1) app.js)"
