#!/bin/sh
# Run the dethrace_rast testbench in the simulation container against a trace
# of the software model.
# usage: sim/run_rast.sh <trace dir below core/> [+fast | top]
#   +fast: no random bus waits, for cycle counts
#   top:   the rasteriser with its command ring behind the DDR arbiter (tb_rast_top.sv)
#   make a trace on the host build (see fpgarast.c), for example:
#     PENTPRIM_FPGA=1 PENTPRIM_FPGA_TRACE=core/sim/trace/t1 PENTPRIM_FPGA_TRACE_SKIP=400000 \
#       DETHRACE_MISTER_HEADLESS=1 DETHRACE_MISTER_SCRIPT=bench/bench.txt DETHRACE_MISTER_FIXED_STEP=33 \
#       DETHRACE_OPTIONS_FILE=bench/options_full.txt build/host/dethrace --dir "$PWD"
#     PENTPRIM_FPGA_REPLAY=core/sim/trace/t1 build/host/dethrace
cd "$(dirname "$0")/.."
docker image inspect mister-dethrace-sim > /dev/null 2>&1 || docker build -t mister-dethrace-sim ../toolchain/sim
docker run --rm -v "$PWD":/src mister-dethrace-sim sh -c \
  "if [ '$2' = top ]; then
     iverilog -g2012 -Wall -o /tmp/tb sim/tb_rast_top.sv rtl/dethrace_rast_top.sv rtl/dethrace_rast.sv rtl/dethrace_ddr_arb.sv && vvp -n /tmp/tb +trace=$1
   else
     iverilog -g2012 -Wall -o /tmp/tb sim/tb_rast.sv rtl/dethrace_rast.sv && vvp -n /tmp/tb +trace=$1 $2 $3
   fi"
