#!/bin/sh
# Profile guided build of the ARM binary, 5-8% faster than ./build.sh alone:
# build with instrumentation, play the benchmark on the MiSTer with the
# Optimized and the Fast renderer, rebuild with the collected profile.
# A later plain ./build.sh goes back to the normal build.
set -e
cd "$(dirname "$0")/.."
HOST=${MISTER:-root@192.168.1.206}
find build/mister -name '*.gcda' -delete 2> /dev/null || true
EXTRA_CFLAGS=-fprofile-generate EXTRA_LDFLAGS=-fprofile-generate ./build.sh
ssh "$HOST" "rm -rf /tmp/gcda"
# the instrumented binary writes its counters below GCOV_PREFIX on exit
tools/bench.sh build/mister/dethrace pgo-train bench GCOV_PREFIX=/tmp/gcda
tools/bench.sh build/mister/dethrace pgo-train bench GCOV_PREFIX=/tmp/gcda PENTPRIM_FAST=1
ssh "$HOST" "cd /tmp/gcda/src && tar cf - ." | tar xf - -C .
EXTRA_CFLAGS="-fprofile-use -fprofile-correction -Wno-missing-profile" ./build.sh
