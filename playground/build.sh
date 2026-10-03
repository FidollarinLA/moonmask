#!/usr/bin/env bash
# Builds the playground into playground/dist, ready to serve as static files.
set -euo pipefail
cd "$(dirname "$0")"
python3 build.py
