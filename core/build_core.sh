#!/bin/sh
# Build Dethrace.rbf with Quartus Lite 17.0.2 (docker image used by MiSTer-devel CI)
set -e
cd "$(dirname "$0")/.."
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD":/build -w /build/core \
    theypsilon/quartus-lite-c5:17.0.2.docker0 \
    /opt/intelFPGA_lite/quartus/bin/quartus_sh --flow compile Dethrace
ls -la core/output_files/Dethrace.rbf
