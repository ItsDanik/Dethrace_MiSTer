#!/bin/sh
# Cross-compile dethrace for MiSTer inside the toolchain container.
# Usage: ./build.sh [Release|RelWithDebInfo|Debug]
set -e
cd "$(dirname "$0")"
docker image inspect mister-dethrace-tc > /dev/null 2>&1 || docker build -t mister-dethrace-tc toolchain
TYPE=${1:-RelWithDebInfo}
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD":/src mister-dethrace-tc sh -c "
  cmake -S dethrace -B build/mister -DCMAKE_TOOLCHAIN_FILE=/src/toolchain/mister.cmake \
    -DCMAKE_BUILD_TYPE=$TYPE -DCMAKE_C_FLAGS_RELWITHDEBINFO='-O2 -g' \
    -DDETHRACE_PLATFORM_SDL2=OFF -DDETHRACE_PLATFORM_MISTER=ON \
    -DDETHRACE_SOUND_ENABLED=ON -DDETHRACE_NET_ENABLED=OFF &&
  cmake --build build/mister -j\$(nproc)"
