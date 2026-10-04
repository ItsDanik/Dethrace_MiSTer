# Dethrace for MiSTer

Carmageddon (1997) on [MiSTer FPGA](https://github.com/MiSTer-devel/Main_MiSTer/wiki) as a hybrid core.

The game itself is [dethrace](https://github.com/dethrace-labs/dethrace), the open source reimplementation of Carmageddon. It runs on the MiSTer's ARM CPU. The Dethrace FPGA core provides native 320x200 15kHz video (CRT, VGA and HDMI), 44.1kHz audio and keyboard, mouse and gamepad input. The two halves talk through shared DDR3 memory.

> **Beta.** This is the first public release. Expect rough edges and please report problems in the issues.

## Requirements

- **danik_hybrid_cores**, the launcher that comes in the release zip (`Scripts/danik_hybrid_cores.sh`): run it **once** from the MiSTer's `Scripts` menu. It starts the game whenever the core is loaded, keeps running after a reboot, and serves all our hybrid cores. Every hybrid core brings the launcher along and the newest version is the one that runs, so it never has to be run again after an update. Without it the core only shows colour bars.
- **Carmageddon game data**, which is not included. Use your original CD or the GOG release (Carmageddon Max Pack).

## Installation

1. Download the newest `Dethrace_YYYYMMDD.zip` from [releases](releases/) and extract it to the root of your SD card (`/media/fat`). That gives you:
   - `_Other/Dethrace_YYYYMMDD.rbf`, the FPGA core
   - `games/Dethrace/`, the game binary and its launcher
   - `Scripts/danik_hybrid_cores.sh`, the launcher (from [Hybrid_MiSTer](https://github.com/ItsDanik/Hybrid_MiSTer), which can also keep it up to date through `update_all`)
2. Copy the game's `DATA` folder to `/media/fat/games/Dethrace/DATA` (`DATA/GENERAL.TXT` must exist).
3. Optional CD music (GOG release): copy the `MUSIC` folder (`Track02.ogg` ...) to `/media/fat/games/Dethrace/MUSIC`.
4. Run **danik_hybrid_cores** from the `Scripts` menu, if you have not done so before (see Requirements).
5. Load **Dethrace** from the `Other` menu.

Quitting from the game's main menu returns to the MiSTer menu. The game's log is in `/media/fat/logs/Dethrace/dethrace.log`.

## OSD options

| Option | |
|---|---|
| Aspect ratio, Scandoubler Fx, Stereo Mix | as in other cores |
| Sound Volume | master volume of sound effects and cutscene audio, on top of the game's own setting |
| Music Volume | master volume of the CD music, on top of the game's own setting |
| Renderer | **Optimized** (default): rewritten rasteriser and fog loops, pixel for pixel the same picture as the original code. **Fast**: also simplifies the perspective texture mapping (exact every 16 pixels, interpolated in between); the picture is nearly the same and the game runs 20-25% faster. **Original**: the original rasteriser code |
| Lock to 30 FPS | shows every frame for exactly two video fields (29.8 fps) instead of a frame rate that floats between 30 and 60 fps. Steadier motion, best together with the Fast renderer |
| Menu OK, Menu Back | the gamepad button that acts as Enter / Esc in the game's menus, even if it is also a race control. **MiSTer** (default) uses the OK/Back buttons of your MiSTer menu |

## Controls

- **Keyboard:** the original PC controls.
- **Gamepad** in a race (default mapping):

| Button | Action |
|---|---|
| D-pad / left stick | Steer |
| B (Xbox A / PlayStation Cross) | Accelerate |
| Y (Xbox X / PlayStation Square) | Brake |
| A (Xbox B / PlayStation Circle) | Handbrake |
| X (Xbox Y / PlayStation Triangle) | Change View |
| L (LB / L1) | Repair |
| R (RB / R1) | Map |
| Select | Recover |
| Start | Pause (Esc) |

To accelerate and brake with the triggers (RT/LT), assign them in the OSD under *Define Dethrace buttons*. MiSTer's default mapping can't use triggers.

*Menu OK* and *Menu Back* in *Define Dethrace buttons* are only needed for a button that has no race function. MiSTer doesn't let you assign a button twice there, so to use a race control as Enter/Esc in menus, pick that button in the OSD's Menu OK/Menu Back options instead.

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
| `core/` | FPGA core, based on [Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer). `rtl/dethrace_host.sv` documents the shared memory layout. `sim/run.sh` runs its testbench. |
| `dethrace/` | submodule: [ItsDanik/dethrace](https://github.com/ItsDanik/dethrace) branch `mister`, a fork of dethrace with the MiSTer platform driver in `src/harness/platforms/mister*.c` |
| `dethrace/lib/BRender-v1.3.2` | submodule: [ItsDanik/BRender-v1.3.2](https://github.com/ItsDanik/BRender-v1.3.2) branch `mister`, with the optimised rasteriser |
| `hybrid/` | submodule: [ItsDanik/Hybrid_MiSTer](https://github.com/ItsDanik/Hybrid_MiSTer), what all our hybrid cores share. Dethrace uses its launcher: `launcher/danik_hybrid_cores.sh`, the daemon that runs `games/<core>/danik_hybrid_launch.sh` while its core is loaded (its header documents it) |
| `package/` | files shipped in the release next to the binary: the game's launcher (`danik_hybrid_launch.sh`) and README |
| `releases/` | release packages |
| `toolchain/`, `tools/`, `bench/` | Docker toolchains, development helpers, benchmark scripts |

### Development notes

- `./build_host.sh` and `./verify.sh grid|drive` build the game for the PC and play a scripted race. Every call to the optimised rasteriser is checked against the original (`PENTPRIM_VERIFY=1`), and the two must produce byte-identical output. The scripted race needs a `DATA` folder in the repository root.
- The MiSTer platform driver can run headless with scripted input, screenshots and a sampling profiler. Its environment variables are documented at the top of `dethrace/src/harness/platforms/mister.c`.
- `tools/bench.sh build/mister/dethrace <label> [script] [VAR=value ...]` plays `bench/bench.txt` headless on the MiSTer and fetches the frame times, profile and screenshots to `bench/out/<label>`. It runs with a fixed time step (`DETHRACE_MISTER_FIXED_STEP`) and full detail, so every run renders the same frames and results are comparable to about 1%. `PENTPRIM_FAST=1` and `PENTPRIM_REFERENCE=1` select the Fast and Original renderer. `tools/profsym.py` and `tools/proflines.py` break the profile down by function and by source line.
- `tools/pgo.sh` makes a profile guided build (5-8% faster): it trains on the MiSTer with the benchmark, then rebuilds `build/mister/dethrace`. The release binary is built this way.
- Benchmark on the MiSTer (ms per frame, 20261004): Original 28.0, Optimized 22.7, Fast 18.5. Sound is off in the benchmark because it makes runs differ; it costs the game thread next to nothing (the mixer runs on CPU1). `tools/hwbench.sh` runs the same benchmark on the loaded core with both CPUs and, with `DETHRACE_MISTER_FIXED_SOUND=1`, with sound.
- `touch /tmp/dethrace_nolaunch` on the MiSTer keeps the core loaded without starting the game, so you can start a development binary by hand. `/tmp/danik_hybrid_cores.log` shows what the launcher daemon did.

## Credits

- **[dethrace](https://github.com/dethrace-labs/dethrace)** by Jeff Harris and the dethrace-labs contributors: the reimplementation of Carmageddon this port is built on.
- **[BRender](https://github.com/dethrace-labs/BRender-v1.3.2)** by Argonaut Software, released under the MIT license.
- **[MiSTer](https://github.com/MiSTer-devel)** by Sorgelig and the MiSTer-devel contributors: the framework and Template_MiSTer.
- **[MiSTer Frontier](https://github.com/MiSTerOrganize/MiSTer_Frontier)** by MiSTer Organize: thank you for the inspiration. Hybrid cores on the MiSTer, and the way their game is launched (a daemon that watches the loaded core and runs a script from its games folder), come from MiSTer Frontier. Our launcher is a separate implementation and does not need MiSTer Frontier installed.

This project and its maintainers are in no way associated with or endorsed by SCi, Stainless Software or THQ Nordic. It does not include any Carmageddon game data, and it may only be used with assets from a copy of Carmageddon that you own.

## License

The top-level scripts, tools and documentation are licensed under the [GPL-3.0](LICENSE). The components keep their own licenses: dethrace (see `dethrace/LICENSE` and the Legal section of `dethrace/README.md`, including its non-commercial use condition), BRender is MIT (`dethrace/lib/BRender-v1.3.2/LICENSE`), and the FPGA core and the MiSTer framework are GPL-2.0 (`core/LICENSE`, with the core's own sources GPL-2.0-or-later).
