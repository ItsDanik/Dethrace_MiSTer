# Dethrace hybrid core for MiSTer (Carmageddon)

@hybrid/CLAUDE.md

## This core

- Name everywhere: `Dethrace` (the engine: core, folders `games/dnk/Dethrace/` and `logs/dnk/Dethrace/`, `_Other/dnk/dnk-Dethrace_*.rbf`, release), `dethrace` (game submodule, binary in `build/`, log, lock). The games and their menu entries (`_Other/dnk-<title>.mgl`): `package/games.txt`, the same as in the catalogue of `hybrid/launcher/danik_hybrid_ports.sh`.
- The game is the `dethrace/` submodule, branch `mister`. Its MiSTer code is behind the `MISTER_HYBRID` build option.
- Build: `./build.sh` (game), `./core/build_core.sh` (FPGA), `./package.sh` (zip in `dist/`), `MISTER=root@<address> tools/deploy.sh`.
- Try a build on the MiSTer without installing it: `MISTER=root@<address> tools/test_on_mister.sh <id>|list|nodata|log|stop` (the rule in `hybrid/CLAUDE.md`).
- Lines marked `GAME:` in the scripts and `TODO` in the READMEs are the places the template left for this game.

<!-- Notes that are only true for this game go below. -->

- Dethrace predates the framework's template and kept some of its own ways: the game builds with its own toolchain image (`toolchain/`, `build.sh`, `build_host.sh`), not with SDL; the FPGA core is the template's.
- The game is the `dethrace/` submodule (`ItsDanik/dethrace`, branch `mister`) with BRender as its submodule `lib/BRender-v1.3.2` (`ItsDanik/BRender-v1.3.2`, branch `mister`: the optimised and fast rasterisers). The MiSTer platform is `src/harness/platforms/mister*.c`.

## MiSTer layer (host version 13)

- `mister_fpga.c` keeps the interface the rest of the platform uses (`mister_fpga.h`) and is built on the framework's library: the harness compiles `hybrid/hps/*.c` (`-DMISTER_HYBRID_HPS=<path>` from the build scripts, `src/harness/CMakeLists.txt`). Video, palette, input and the field counter are the `MH_` calls; audio is `MH_AudioWrite()` from the audio thread (`mister_audio.c`); Menu OK/Back `MH_MenuButtons()` (the game's own `mister_joymap.c` is gone).
- Games (`package/games.txt`): CARMA Carmageddon, its `DATA` in the game's folder; SPLAT Carmageddon: Splat Pack, its `DATA` in `SPLATPAK/` (Danik, 2026-10-16). `MiSTer_SelectGame()` in `mister.c`, called by `Harness_Init()` (`harness.c`) after it went into `--dir` and before `Harness_DetectGameMode()`: it finds what each `DATA` holds the way that function does (full game or demo), hands `MH_PickGame()` the table (a game not found `MH_NOT_THERE` with its message) and goes into the picked game's folder. Exit codes 42 (back to the list) and 43 (core loaded again) from `mister_at_exit()`; the game no longer loads the MiSTer menu itself, the launch script does.
- `mister_show_error_message()` shows the game's errors on the core's purple screen.

## 240 lines

- Only the view of a race from outside the car is drawn in 240 rows (`TallRenderPossible()` in `DETHRACE/common/graphics.c`: not the cockpit view, the map or a reduced view, whose artwork is drawn for 200 rows and stays 320x200; nor the menus). The rule's exception: the cockpit is a picture of the car's inside that covers the screen, drawn for 200 rows.
- The instruments keep their size and go down by the HUD margins: `gTall_top_shift` (HUD (Top)) for the Pratcam, the headups and the power-up bars, `gTall_bottom_shift` = 45 - HUD (Bottom) for the instruments at the bottom (they end 5 rows above the bottom of the 200, `pd/sys.h`), and the dimmed boxes behind each with them (`DimAFewBits()`). The 240-row buffer has 8 spare rows below (`TALL_SPARE_ROWS`, `pc-all/allsys.c`), for the rows of the 200 under the bottom instruments at small margins. `apply_hud_margins()` in `mister.c` reads the margins every frame and greys the two OSD lines while races are not in 320x240.

## Cheats

- Cheats page of the OSD (Danik, 2026-10-16): Invulnerability (status bit 29, the car's `invulnerable` flag while on), Instant Repair (T[56], power-up 9), Extra Credits (T[57], 10000), Finish Lap (T[58], the game's own `FinishLap()`). `Dethrace_Cheats()` at the end of `DETHRACE/common/controls.c`, called every frame by the platform; only in a race, not in a network game. Power-up numbers from `POWERUP.TXT`: 7 Invulnerability, 9 Instant repair.

## Analog control and rumble

- Analog steering (left stick), gas (right trigger) and brake (left trigger), hard mapped (Danik, 2026-10-16): `apply_analog()` in `mister.c` sets `gAnalog_steering`, `gAnalog_acc`, `gAnalog_dec` (`DETHRACE/common/controls.c`) every frame, which `PollCarControls()` puts into the car's joystick values (`tJoystick`: 0..65535, -1 unused) while the stick is out of its dead zone or a trigger is pressed; the game's own joystick axes (`gJoy_array`, `SetJoystickArrays()`) were never filled in by dethrace. The triggers are `MH_ReadTriggers()`. The game turns `joystick.dec` into the full brake whatever its value (`dec / 0x10000`), so the analog brake has its own line in `car.c` (force in proportion); gas was analog already (`joystick.acc / 54613`), steering too (curvature by the square of the value). Buttons and keys work as before.
- Rumble when the car is hit: the game's impact energy on the player's car (`gImpact_energy`, `crush.c`, where it shakes the screen) through `apply_rumble()` in `mister.c` to `MH_Rumble()`: 255 x sqrt(energy / 0.4), the light motor 1.5 times that, fading with 120ms. Energies in a scripted race: a scrape about 0.003, a solid hit 0.04, the hardest 1.2. OSD option Rumble (status bit 30, On by default).
- The triggers are only checked on a DualSense at rest (hybrid/CLAUDE.md): try them pressed on the MiSTer.

## FPGA rasteriser: paused

- The triangle rasteriser (`core/rtl/dethrace_rast*.sv`, `dethrace_ddr_arb.sv`, `core/sim/`, `mister_rast.c`, `tools/rast*`) is development that is paused (Danik, 2026-10-16). It is not in the core: `core/files.qip` and `core/Dethrace.sv` are the template's. Do not build it in or change it unless Danik picks it up again.

## Frame pacing (host version 13, measured 2026-10-16)

- The game's frame rate floats between 30 and 60 fps (most frames take more than a field), so drawing ahead, which helps a game that is a little slower than a field now and then, has nothing to give; the game's own *Lock to 30 FPS* is the steady pacing. Not built in.
- On the MiSTer, `bench/drive.txt` (a race at 320x240, Danik's settings), fps every 2 seconds from 40 to 100 seconds: this build (on the framework's library) about 50 (44 to 54), the released build 20261008 about 44 (38 to 49). No regression from the port.
