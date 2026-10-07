#!/bin/sh
# Cross-compile dethrace for MiSTer inside the toolchain container.
# Usage: ./build.sh [Release|RelWithDebInfo|Debug]
# EXTRA_CFLAGS / EXTRA_LDFLAGS are added to the compiler / linker flags
# (tools/pgo.sh uses them for the profile guided build). BUILD_DIR selects the
# build directory (default build/mister).
set -e
cd "$(dirname "$0")"
docker image inspect mister-dethrace-tc > /dev/null 2>&1 || docker build -t mister-dethrace-tc toolchain
TYPE=${1:-RelWithDebInfo}
BUILD_DIR=${BUILD_DIR:-build/mister}
# same as the defaults in toolchain/mister.cmake
ARCH_FLAGS='-mcpu=cortex-a9 -mfpu=neon -mfloat-abi=hard -fno-pie'
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD":/src mister-dethrace-tc sh -c "
  cmake -S dethrace -B $BUILD_DIR -DCMAKE_TOOLCHAIN_FILE=/src/toolchain/mister.cmake \
    -DCMAKE_BUILD_TYPE=$TYPE -DCMAKE_C_FLAGS_RELWITHDEBINFO='-O2 -g' \
    -DCMAKE_C_FLAGS='$ARCH_FLAGS $EXTRA_CFLAGS' -DCMAKE_EXE_LINKER_FLAGS='-no-pie $EXTRA_LDFLAGS' \
    -DDETHRACE_PLATFORM_SDL2=OFF -DDETHRACE_PLATFORM_MISTER=ON \
    -DDETHRACE_SOUND_ENABLED=ON -DDETHRACE_NET_ENABLED=OFF &&
  cmake --build $BUILD_DIR -j\$(nproc)"
