#!/bin/sh
# Run the dethrace_host testbench in the simulation container
cd "$(dirname "$0")/.."
docker image inspect mister-dethrace-sim > /dev/null 2>&1 || docker build -t mister-dethrace-sim ../toolchain/sim
docker run --rm -v "$PWD":/src mister-dethrace-sim sh -c \
  "iverilog -g2012 -Wall -o /tmp/tb sim/tb_host.sv rtl/dethrace_host.sv && vvp -n /tmp/tb"
