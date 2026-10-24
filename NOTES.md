# Dethrace for MiSTer: notes

How the port works and how it is built. For playing it, see the [README](README.md).

## Triggers, racing wheels and rumble

The triggers work without any mapping: MiSTer passes no trigger axes to a core, so the game reads them from the controller itself (the one pressed furthest, if there are several). The buttons for gas and brake work as well.

**Racing wheel**: the wheels MiSTer itself knows (Logitech G25, G27, G29, Driving Force, Driving Force Pro and GT; Fanatec ClubSport V2.5, Podium DD1 and DD2; Thrustmaster T300RS, F430 and FGT, and a few adapters) steer with the wheel and drive with the pedals, analog: the gas pedal is the right trigger, the brake the left. Map the wheel's buttons in the OSD as for a gamepad. While a wheel is connected, a gamepad's stick pushed up also counts as a pedal, and the gas pedal moves the menus' lines like the stick up.

The controller rumbles when the car is hit, the harder the hit the stronger, on every controller that can (OSD option *Rumble*).

*Pratcam* (the driver's face in the corner, key P) has no button by default: give it one in *Define Dethrace buttons* to switch it on and off from the gamepad.

## Building

Everything builds in Docker on a Linux PC.

```sh
git clone --recursive https://github.com/ItsDanik/Dethrace_MiSTer.git
cd Dethrace_MiSTer
./build.sh              # ARM game binary  -> build/mister/dethrace
./core/build_core.sh    # FPGA core (Quartus Lite 17.0.2) -> core/output_files/Dethrace.rbf
./package.sh            # release zip      -> dist/Dethrace_YYYYMMDD.zip
```

The ARM toolchain image (Debian bullseye, glibc 2.31 to match the MiSTer) is built from `toolchain/` on first use.

### Repository layout

| Path | |
|---|---|
| `core/` | FPGA core, based on [Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer). The host module is the shared `hybrid/rtl/hybrid_host.sv`, which documents the shared memory layout (`hybrid/sim/run.sh` runs its testbench). |
| `dethrace/` | submodule: [ItsDanik/dethrace](https://github.com/ItsDanik/dethrace) branch `mister`, a fork of dethrace with the MiSTer platform driver in `src/harness/platforms/mister*.c` |
| `dethrace/lib/BRender-v1.3.2` | submodule: [ItsDanik/BRender-v1.3.2](https://github.com/ItsDanik/BRender-v1.3.2) branch `mister`, with the optimised rasteriser |
| `hybrid/` | submodule: [ItsDanik/Hybrid_MiSTer](https://github.com/ItsDanik/Hybrid_MiSTer), what all our hybrid ports share: the FPGA host module, the library the game's MiSTer platform is built on (`hps/`), the launcher (`launcher/danik_hybrid_ports.sh`), conventions |
| `package/` | files shipped in the release next to the binary: the game's launcher (`danik_hybrid_launch.sh`) and README |
| `releases/` | release packages |
| `toolchain/`, `tools/`, `bench/` | Docker toolchains, development helpers, benchmark scripts |

### Development notes

- `./build_host.sh` and `./verify.sh grid|drive` build the game for the PC and play a scripted race. Every call to the optimised rasteriser is checked against the original (`PENTPRIM_VERIFY=1`), and the two must produce byte-identical output. The scripted race needs a `DATA` folder in the repository root.
- The MiSTer platform driver can run headless with scripted input, screenshots and a sampling profiler. Its environment variables are documented at the top of `dethrace/src/harness/platforms/mister.c`.
- `tools/bench.sh build/mister/dethrace <label> [script] [VAR=value ...]` plays `bench/bench.txt` headless on the MiSTer and fetches the frame times, profile and screenshots to `bench/out/<label>`. It runs with a fixed time step (`DETHRACE_MISTER_FIXED_STEP`) and full detail, so every run renders the same frames and results are comparable to about 1%. `PENTPRIM_FAST=1` and `PENTPRIM_REFERENCE=1` select the Fast and Original renderer. `tools/profsym.py` and `tools/proflines.py` break the profile down by function and by source line.
- `tools/pgo.sh` makes a profile guided build (5-8% faster): it trains on the MiSTer with the benchmark, then rebuilds `build/mister/dethrace`. The release binary is built this way.
- Benchmark on the MiSTer (ms per frame, 20261004): Original 28.0, Optimized 22.7, Fast 18.5. Sound is off in the benchmark because it makes runs differ; it costs the game thread next to nothing (the mixer runs on CPU1). `tools/hwbench.sh` runs the same benchmark on the loaded core with both CPUs and, with `DETHRACE_MISTER_FIXED_SOUND=1`, with sound.
- `MISTER=root@<address> tools/test_on_mister.sh CARMA` tries the build on a MiSTer next to what is installed there, without installing it: from `/tmp`, with the installed game's folder mirrored there (what the game writes stays in `/tmp`) and its own OSD settings. `SPLAT` for the Splat Pack, `list` and `nodata` for the core started by itself and without data, `log` for the game's log, `stop` to remove all of it again.
- `touch /tmp/dethrace_nolaunch` on the MiSTer keeps the core loaded without starting the game, so you can start a development binary by hand (`MISTER_HYBRID_CORE=Dethrace`, and `MISTER_HYBRID_SET` for a game's set name, e.g. `Dethrace_SPLAT`). `/tmp/danik_hybrid_ports.log` shows what the launcher daemon did.

### FPGA rasteriser (in development)

The next step is to let the FPGA fill the triangles: the game keeps the triangle setup and writes commands to a ring in shared memory, the core walks the edges and fills colour and depth in DDR3. Development is paused: the rasteriser is not in the core (`core/files.qip` leaves it out since host version 13), and the game does not use it.

- `dethrace/lib/BRender-v1.3.2/drivers/pentprim/fpgarast.h` documents the commands, `fpgarast.c` has the emitter, the buffer ownership rules and a software model of the hardware. The model draws pixel for pixel what the Optimized renderer draws. `PENTPRIM_FPGA=1` plays the game through commands and the model (`./verify.sh` checks it against the original code like the other rewrites), `PENTPRIM_FPGA=2` gives the model its own copy of the buffers like the hardware has, which tests that everything that touches the buffers on the CPU asks for them first. `DETHRACE_MISTER_FRAMECRC=1` writes a checksum per frame to compare whole runs between renderers.
- `core/rtl/dethrace_rast.sv` is the rasteriser, `dethrace_rast_top.sv` its command ring, `dethrace_ddr_arb.sv` shares the DDR3 port with the video/audio/input module. `core/sim/run_rast.sh <trace> [+fast|top]` replays a trace of the model in simulation and compares the buffers (the script's header shows how to record one).
- `tools/rasttest.sh <trace>` does the same on the MiSTer with the core loaded and the game not running.
- `DETHRACE_MISTER_RAST=1` makes the game on the MiSTer draw with the FPGA rasteriser (the platform's backend is `mister_rast.c`); `tools/rastbench.sh <binary> <core.rbf> <label>` runs the benchmark that way. With `DETHRACE_MISTER_FRAMECRC=1` the frames can be compared with another renderer's.
- State: flat, Gouraud, textured (power of 2 and arbitrary width), lit textured and perspective correct triangles, the depth clear and the fog pass run on the FPGA. The benchmark race on the MiSTer is frame for frame identical to the Optimized renderer and takes 21.0 ms per frame (Optimized 24.6, Fast 19.8 with the same non-PGO build). The FPGA is the bottleneck: the CPU waits about 4.5 ms per frame for it, copies buffers for 3 ms and writes commands for 2 ms. Blended triangles, smoke and sparks are still drawn by the CPU, which fetches the buffers for them.
- `PENTPRIM_NULL=1` skips all pixel loops and the fog pass: what is left (10.3 ms per frame in the benchmark) is the frame time the FPGA rasteriser can approach.
