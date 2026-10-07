#!/bin/sh
# Play a software model trace through the FPGA rasteriser of the loaded
# Dethrace core and compare the result (tools/rasttest.c). The game must not
# be running: touch /tmp/dethrace_nolaunch on the MiSTer before loading the core.
# usage: tools/rasttest.sh <trace dir> [runs]
set -e
cd "$(dirname "$0")/.."
HOST=${MISTER:-root@192.168.1.206}
mkdir -p build/rasttest
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD":/src mister-dethrace-tc sh -c \
  "arm-linux-gnueabihf-gcc -O2 -mcpu=cortex-a9 -mfpu=neon -mfloat-abi=hard -o /src/build/rasttest/rasttest /src/tools/rasttest.c"
ssh "$HOST" "rm -rf /tmp/rasttest && mkdir -p /tmp/rasttest"
scp -q build/rasttest/rasttest "$1/mem.hex" "$1/cmds.hex" "$1/expect.hex" "$HOST:/tmp/rasttest/"
ssh "$HOST" "taskset -c 0 /tmp/rasttest/rasttest /tmp/rasttest ${2:-3}"
