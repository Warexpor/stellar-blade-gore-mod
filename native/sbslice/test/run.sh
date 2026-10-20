#!/usr/bin/env bash
# Build and run the skin cut harness natively (clang, ASan/UBSan).
set -euo pipefail
cd "$(dirname "$0")"
OUT=${TMPDIR:-/tmp}/sbslice-test
clang -O1 -g -fsanitize=address,undefined -w -o "$OUT" test_cut.c
ASAN_OPTIONS=detect_leaks=0 "$OUT"
