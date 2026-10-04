#!/bin/sh
# Run the scripted benchmark race headless on the MiSTer (full detail, CPU0)
# with a fixed 33ms time step (same frames every run) and fetch the results.
# usage: tools/bench.sh <binary> <label> [script] [VAR=value ...]
#   results in bench/out/<label>/ (log.txt, profile.bin, maps.txt, frametimes.txt)
set -e
cd "$(dirname "$0")/.."
HOST=${MISTER:-root@192.168.1.206}
BIN=$1; LABEL=$2; SCRIPT=${3:-bench}; shift 2; [ $# -gt 0 ] && shift
DEV=/media/fat/dethrace-dev
OUT=bench/out/$LABEL
mkdir -p "$OUT"
scp -q "$BIN" "$HOST:$DEV/bench-bin"
scp -q "bench/$SCRIPT.txt" bench/options_full.txt "$HOST:$DEV/"
ssh "$HOST" "rm -rf /tmp/bench && mkdir -p /tmp/bench && cd /media/fat/games/Dethrace &&
  env -u HOME -u XDG_DATA_HOME DETHRACE_MISTER_HEADLESS=1 DETHRACE_MISTER_OUT=/tmp/bench \
  DETHRACE_MISTER_SCRIPT=$DEV/$SCRIPT.txt DETHRACE_OPTIONS_FILE=$DEV/options_full.txt DETHRACE_MISTER_FIXED_STEP=${STEP:-33} $* \
  taskset -c 0 $DEV/bench-bin --dir /media/fat/games/Dethrace > /tmp/bench/log.txt 2>&1; true"
scp -q "$HOST:/tmp/bench/shot_*.ppm" "$HOST:/tmp/bench/log.txt" "$HOST:/tmp/bench/profile.bin" "$HOST:/tmp/bench/maps.txt" "$HOST:/tmp/bench/frametimes.txt" "$OUT/" 2>/dev/null || true
grep -E "SUMMARY|pentprim" "$OUT/log.txt"
