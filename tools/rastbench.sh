#!/bin/sh
# The benchmark race with the FPGA rasteriser: loads the development core,
# plays bench/bench.txt headless (fixed time step, full detail, CPU0) with
# DETHRACE_MISTER_RAST=1 and fetches the results. With DETHRACE_MISTER_FRAMECRC=1
# there is a checksum per frame (framecrc.txt) to compare with another renderer.
# usage: tools/rastbench.sh <binary> <core.rbf> <label> [VAR=value ...]
#   results in bench/out/<label>/
set -e
cd "$(dirname "$0")/.."
HOST=${MISTER:-root@192.168.1.206}
BIN=$1; RBF=$2; LABEL=$3; shift 3
DEV=/media/fat/dethrace-dev
OUT=bench/out/$LABEL
mkdir -p "$OUT"
scp -q "$BIN" "$HOST:$DEV/bench-bin"
scp -q "$RBF" "$HOST:$DEV/Dethrace_rast.rbf"
scp -q bench/bench.txt bench/options_full.txt "$HOST:$DEV/"
ssh "$HOST" "touch /tmp/dethrace_nolaunch
  echo load_core $DEV/Dethrace_rast.rbf > /dev/MiSTer_cmd; sleep 6
  rm -rf /tmp/bench && mkdir -p /tmp/bench && cd /media/fat/games/Dethrace &&
  env -u HOME -u XDG_DATA_HOME DETHRACE_MISTER_HEADLESS=1 DETHRACE_MISTER_RAST=1 DETHRACE_MISTER_OUT=/tmp/bench \
    DETHRACE_MISTER_SCRIPT=$DEV/bench.txt DETHRACE_OPTIONS_FILE=$DEV/options_full.txt DETHRACE_MISTER_FIXED_STEP=33 $* \
    taskset -c 0 $DEV/bench-bin --dir /media/fat/games/Dethrace > /tmp/bench/log.txt 2>&1; true
  rm -f /tmp/dethrace_nolaunch; echo load_core /media/fat/menu.rbf > /dev/MiSTer_cmd"
scp -q "$HOST:/tmp/bench/shot_*.ppm" "$HOST:/tmp/bench/log.txt" "$HOST:/tmp/bench/profile.bin" "$HOST:/tmp/bench/maps.txt" "$HOST:/tmp/bench/frametimes.txt" "$HOST:/tmp/bench/framecrc.txt" "$OUT/" 2>/dev/null || true
grep -E "SUMMARY|rasteriser|fpgarast" "$OUT/log.txt"
