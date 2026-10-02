# Dethrace for MiSTer

Carmageddon (1997) on [MiSTer FPGA](https://github.com/MiSTer-devel/Main_MiSTer/wiki) as a hybrid core.

The game itself is [dethrace](https://github.com/dethrace-labs/dethrace), the open source reimplementation of Carmageddon. It runs on the MiSTer's ARM CPU. The Dethrace FPGA core provides native 320x200 15kHz video (CRT, VGA and HDMI), 44.1kHz audio and keyboard, mouse and gamepad input. The two halves talk through shared DDR3 memory.

> **Beta.** This is the first public release. Expect rough edges and please report problems in the issues.

## Requirements

- A MiSTer with **MiSTer Frontier** installed. Its `Master_Daemon` starts the game (`games/Dethrace/_handler.sh`) when the core is loaded and stops it when you switch cores.
- **Carmageddon game data**, which is not included. Use your original CD or the GOG release (Carmageddon Max Pack).

## Installation

1. Download the newest `Dethrace_YYYYMMDD.zip` from [releases](releases/) and extract it to the root of your SD card (`/media/fat`). That gives you:
   - `_Other/Dethrace_YYYYMMDD.rbf`, the FPGA core
   - `games/Dethrace/`, the game binary and its launcher
2. Copy the game's `DATA` folder to `/media/fat/games/Dethrace/DATA` (`DATA/GENERAL.TXT` must exist).
3. Optional CD music (GOG release): copy the `MUSIC` folder (`Track02.ogg` ...) to `/media/fat/games/Dethrace/MUSIC`.
4. Load **Dethrace** from the `Other` menu.

Quitting from the game's main menu returns to the MiSTer menu. The game's log is in `/media/fat/logs/Dethrace/dethrace.log`.

## OSD options

| Option | |
|---|---|
| Aspect ratio, Scandoubler Fx, Stereo Mix | as in other cores |
| Sound Volume | master volume of sound effects and cutscene audio, on top of the game's own setting |
| Music Volume | master volume of the CD music, on top of the game's own setting |
| Renderer | **Optimized**: rewritten rasteriser and fog loops, same picture, about 1.6x faster. **Original**: the original rasteriser code |

## Controls

- **Keyboard:** the original PC controls.
- **Gamepad** (map the buttons in the OSD):
  - Menus: D-pad = cursor keys, Accelerate/Pause = Enter, Brake/Map = Esc
  - Race: D-pad/stick = steer, Up/Accelerate = accelerate, Down/Brake = brake, Handbrake, Change View, Repair, Recover, Map, Pause (Esc)

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
| `package/` | files shipped in the release next to the binary (launcher, README) |
| `releases/` | release packages |
| `toolchain/`, `tools/`, `bench/` | Docker toolchains, development helpers, benchmark scripts |

### Development notes

- `./build_host.sh` and `./verify.sh grid|drive` build the game for the PC and play a scripted race. Every call to the optimised rasteriser is checked against the original (`PENTPRIM_VERIFY=1`), and the two must produce byte-identical output. The scripted race needs a `DATA` folder in the repository root.
- The MiSTer platform driver can run headless with scripted input, screenshots and a sampling profiler. Its environment variables are documented at the top of `dethrace/src/harness/platforms/mister.c`.
- `touch /tmp/dethrace_nolaunch` on the MiSTer keeps the core loaded without starting the game, so you can start a development binary by hand.

## Credits

- **[dethrace](https://github.com/dethrace-labs/dethrace)** by Jeff Harris and the dethrace-labs contributors: the reimplementation of Carmageddon this port is built on.
- **[BRender](https://github.com/dethrace-labs/BRender-v1.3.2)** by Argonaut Software, released under the MIT license.
- **[MiSTer](https://github.com/MiSTer-devel)** by Sorgelig and the MiSTer-devel contributors: the framework and Template_MiSTer.

This project and its maintainers are in no way associated with or endorsed by SCi, Stainless Software or THQ Nordic. It does not include any Carmageddon game data, and it may only be used with assets from a copy of Carmageddon that you own.

## License

The top-level scripts, tools and documentation are licensed under the [GPL-3.0](LICENSE). The components keep their own licenses: dethrace (see `dethrace/LICENSE` and the Legal section of `dethrace/README.md`, including its non-commercial use condition), BRender is MIT (`dethrace/lib/BRender-v1.3.2/LICENSE`), and the FPGA core and the MiSTer framework are GPL-2.0 (`core/LICENSE`, with the core's own sources GPL-2.0-or-later).
