#!/bin/sh
# Play the scripted benchmark race on the host build with every rewritten
# rasteriser function checked against the original (see pentprim/verify.h).
# usage: ./verify.sh [grid|drive]
cd "$(dirname "$0")"
OUT=${OUT:-/tmp/dethrace-verify}
mkdir -p "$OUT"
PENTPRIM_VERIFY=1 DETHRACE_MISTER_HEADLESS=1 DETHRACE_MISTER_OUT="$OUT" DETHRACE_MISTER_SCRIPT=bench/${1:-drive}.txt \
    timeout 300 build/host/dethrace --dir "$PWD" 2>&1 | grep -E "pentprim|calls,|SUMMARY|Assert|PANIC"
