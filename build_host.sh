#!/bin/sh
# Native (x86-64) build of dethrace with the MiSTer platform in headless mode,
# used to verify renderer rewrites against the original code at desktop speed.
set -e
cd "$(dirname "$0")"
cmake -S dethrace -B build/host -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_C_FLAGS_RELWITHDEBINFO='-O2 -g' \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DDETHRACE_PLATFORM_SDL2=OFF -DDETHRACE_PLATFORM_MISTER=ON \
    -DDETHRACE_SOUND_ENABLED=OFF -DDETHRACE_NET_ENABLED=OFF > /dev/null
cmake --build build/host -j"$(nproc)"
