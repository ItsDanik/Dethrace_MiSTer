#!/bin/sh
# Like bench.sh but on the loaded Dethrace core with both CPUs, as in real
# play (frame copy and audio threads on CPU1). Also prints the CPU time of
# every thread. Loads the core from the dev directory and returns to the menu.
# usage: tools/hwbench.sh <binary> <label> [VAR=value ...]
set -e
cd "$(dirname "$0")/.."
HOST=${MISTER:-root@192.168.1.206}
BIN=$1; LABEL=$2; shift 2
DEV=/media/fat/dethrace-dev
OUT=bench/out/$LABEL
mkdir -p "$OUT"
scp -q "$BIN" "$HOST:$DEV/bench-bin"
scp -q bench/bench.txt bench/options_full.txt "$HOST:$DEV/"
ssh "$HOST" "touch /tmp/dethrace_nolaunch
  echo load_core $DEV/Dethrace.rbf > /dev/MiSTer_cmd; sleep 6
  rm -rf /tmp/bench && mkdir -p /tmp/bench && cd /media/fat/games/Dethrace &&
  (env -u HOME -u XDG_DATA_HOME DETHRACE_MISTER_OUT=/tmp/bench DETHRACE_MISTER_SCRIPT=$DEV/bench.txt \
    DETHRACE_OPTIONS_FILE=$DEV/options_full.txt DETHRACE_MISTER_FIXED_STEP=33 $* \
    taskset 0x03 $DEV/bench-bin --dir /media/fat/games/Dethrace > /tmp/bench/log.txt 2>&1 &)
  sleep 2; P=\$(pidof bench-bin)
  while [ -d /proc/\$P ]; do
    for t in /proc/\$P/task/*; do awk '{print \$2, \$14, \$15, \$39}' \$t/stat; done > /tmp/bench/threads.new 2>/dev/null && mv /tmp/bench/threads.new /tmp/bench/threads.txt
    sleep 1
  done
  rm -f /tmp/dethrace_nolaunch; echo load_core /media/fat/menu.rbf > /dev/MiSTer_cmd"
scp -q "$HOST:/tmp/bench/shot_*.ppm" "$HOST:/tmp/bench/log.txt" "$HOST:/tmp/bench/profile.bin" "$HOST:/tmp/bench/maps.txt" "$HOST:/tmp/bench/frametimes.txt" "$HOST:/tmp/bench/threads.txt" "$OUT/" 2>/dev/null || true
grep -E "SUMMARY|underrun" "$OUT/log.txt"
echo "threads (name, user ticks, system ticks, cpu):"; cat "$OUT/threads.txt"
