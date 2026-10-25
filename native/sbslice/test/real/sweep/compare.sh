#!/usr/bin/env bash
# What a sweep changed against the 0.4.1 results (or another sweep): counts, then every job that passed there and
# doesn't now, with its FAIL lines
#   compare.sh [sweep.txt] [base, default results-0.4.1.txt.gz]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
NEW=${1:-sweep.txt}
BASE=${2:-$HERE/results-0.4.1.txt.gz}
cat_any() { case "$1" in *.gz) gzip -dc "$1";; *) cat "$1";; esac; }
awk -F'|' 'NR == FNR { a[$1 "|" $2] = $3; next }
  ($1 "|" $2) in a { k = $1 "|" $2; n++; if (a[k] == "PASS" && $3 != "PASS") { r++; reg[r] = $0 } if (a[k] != "PASS" && $3 == "PASS") f++ }
  END { printf "%d compared: %d pass -> fail, %d fail -> pass\n", n, r, f; for (i = 1; i <= r; i++) print reg[i] }' \
  <(cat_any "$BASE") <(cat_any "$NEW")
