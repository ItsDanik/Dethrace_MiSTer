# Dethrace hybrid core for MiSTer (Carmageddon)

@hybrid/CLAUDE.md

## This core

- Name everywhere: `Dethrace` (the engine: core, folders `games/dnk/Dethrace/` and `logs/dnk/Dethrace/`, `_Other/dnk/dnk-Dethrace_*.rbf`, release), `dethrace` (game submodule, binary in `build/`, log, lock). The games and their menu entries (`_Other/dnk-<title>.mgl`): `package/games.txt`, (in the zip as `games/dnk/Dethrace/games.txt`, from which the database's build makes the launcher's catalogue).
- The game is the `dethrace/` submodule, branch `mister`. Its MiSTer code is behind the `MISTER_HYBRID` build option.
- Build: `./build.sh` (game), `./core/build_core.sh` (FPGA), `./package.sh` (zip in `dist/`), `MISTER=root@<address> tools/deploy.sh`.
- Release: the zip in `releases/`. Players get it once it is published to the database, only when Danik asks: `hybrid/launcher/distribution.py publish ~/dnk_Distribution_MiSTer releases/Dethrace_YYYYMMDD.zip` (the rule in `hybrid/CLAUDE.md`).
- Try a build on the MiSTer without installing it: `MISTER=root@<address> tools/test_on_mister.sh <id>|list|nodata|log|stop` (the rule in `hybrid/CLAUDE.md`).
- Lines marked `GAME:` in the scripts and `TODO` in the READMEs are the places the template left for this game.

<!-- Notes that are only true for this game go below. -->

- Dethrace predates the framework's template and kept some of its own ways: the game builds with its own toolchain image (`toolchain/`, `build.sh`, `build_host.sh`), not with SDL; the FPGA core is the template's.
- The game is the `dethrace/` submodule (`ItsDanik/dethrace`, branch `mister`) with BRender as its submodule `lib/BRender-v1.3.2` (`ItsDanik/BRender-v1.3.2`, branch `mister`: the optimised and fast rasterisers). The MiSTer platform is `src/harness/platforms/mister*.c`.

## MiSTer layer (host version 13)

- `mister_fpga.c` keeps the interface the rest of the platform uses (`mister_fpga.h`) and is built on the framework's library: the harness compiles `hybrid/hps/*.c` (`-DMISTER_HYBRID_HPS=<path>` from the build scripts, `src/harness/CMakeLists.txt`). Video, palette, input and the field counter are the `MH_` calls; audio is `MH_AudioWrite()` from the audio thread (`mister_audio.c`); Menu OK/Back `MH_MenuButtons()` (the game's own `mister_joymap.c` is gone).
- Games (`package/games.txt`): CARMA Carmageddon, its `DATA` in the game's folder; SPLAT Carmageddon: Splat Pack, its `DATA` in `SPLATPAK/` (Danik, 2026-10-16). `MiSTer_SelectGame()` in `mister.c`, called by `Harness_Init()` (`harness.c`) after it went into `--dir` and before `Harness_DetectGameMode()`: it finds what each `DATA` holds the way that function does (full game or demo), hands `MH_PickGame()` the table (a game not found `MH_NOT_THERE` with its message) and goes into the picked game's folder. Exit codes 42 (back to the list) and 43 (core loaded again) from `mister_at_exit()`; the game no longer loads the MiSTer menu itself, the launch script does.
- `mister_show_error_message()` shows the game's errors on the core's purple screen.

## Game data

- Which game a folder holds: `game_in()` in `mister.c` (DATA/GENERAL.TXT, then the race files that tell Carmageddon, its demo, the Splat Pack and its demo apart). For Carmageddon the check then looks for every file the game opens from the start through the menus and the first race (players copy whole folders, `hybrid/CLAUDE.md`): `carma_files` in `mister_files.h`, 628 files, generated from a trace of GOG's Carmageddon Max Pack on the MiSTer (2026-10-19) with `tools/openlog.c` (LD_PRELOAD, every `fopen` / `open`; the build and the run are in its header), the files opened with success under `DATA/`, but `OPTIONS.TXT` and `KEYMAP_0.TXT`, which the game writes. A name may be in any case, as `OS_fopen` opens them, a folder not. Each folder is read once: 14 ms in `/tmp`, 88 ms from a USB drive with nothing cached. A missing file: the message names the first and how many others, and waits. Not checked against the CD version or the German one (robots for pedestrians): a file of the list one of them does not have would stop it with that message. Files of the other races and cars are opened when they come up; a missing one stops the game with its own error, on the purple screen. The demos and the Splat Pack (not on the MiSTer here, so not traced) are known by `game_in()`'s files only.

## 240 lines

- Only the view of a race from outside the car is drawn in 240 rows (`TallRenderPossible()` in `DETHRACE/common/graphics.c`: not the cockpit view, the map or a reduced view, whose artwork is drawn for 200 rows and stays 320x200; nor the menus). The rule's exception: the cockpit is a picture of the car's inside that covers the screen, drawn for 200 rows.
- The instruments keep their size and go down by the HUD margins: `gTall_top_shift` (HUD (Top)) for the Pratcam, the headups and the power-up bars, `gTall_bottom_shift` = 45 - HUD (Bottom) for the instruments at the bottom (they end 5 rows above the bottom of the 200, `pd/sys.h`), and the dimmed boxes behind each with them (`DimAFewBits()`). The 240-row buffer has 8 spare rows below (`TALL_SPARE_ROWS`, `pc-all/allsys.c`), for the rows of the 200 under the bottom instruments at small margins. `apply_hud_margins()` in `mister.c` reads the margins every frame and greys the two OSD lines while races are not in 320x240.

## Cheats

- Cheats page of the OSD (Danik, 2026-10-16): Invulnerability (status bit 29, the car's `invulnerable` flag while on), Instant Repair (T[56], power-up 9), Extra Credits (T[57], 10000), Finish Lap (T[58], the game's own `FinishLap()`). `Dethrace_Cheats()` at the end of `DETHRACE/common/controls.c`, called every frame by the platform; only in a race, not in a network game. Power-up numbers from `POWERUP.TXT`: 7 Invulnerability, 9 Instant repair.

## Analog control and rumble

- Analog steering (left stick), gas (right trigger) and brake (left trigger), hard mapped (Danik, 2026-10-16): `apply_analog()` in `mister.c` sets `gAnalog_steering`, `gAnalog_acc`, `gAnalog_dec` (`DETHRACE/common/controls.c`) every frame, which `PollCarControls()` puts into the car's joystick values (`tJoystick`: 0..65535, -1 unused) while the stick is out of its dead zone or a trigger is pressed; the game's own joystick axes (`gJoy_array`, `SetJoystickArrays()`) were never filled in by dethrace. The triggers are `MH_ReadTriggers()`. The game turns `joystick.dec` into the full brake whatever its value (`dec / 0x10000`), so the analog brake has its own line in `car.c` (force in proportion); gas was analog already (`joystick.acc / 54613`), steering too (curvature by the square of the value). Buttons and keys work as before.
- Rumble when the car is hit: the game's impact energy on the player's car (`gImpact_energy`, `crush.c`, where it shakes the screen) through `apply_rumble()` in `mister.c` to `MH_Rumble()`: 255 x sqrt(energy / 0.4), the light motor 1.5 times that, fading with 120ms. Energies in a scripted race: a scrape about 0.003, a solid hit 0.04, the hardest 1.2. OSD option Rumble (status bit 30, On by default).
- The triggers are only checked on a DualSense at rest (hybrid/CLAUDE.md): try them pressed on the MiSTer.
- Racing wheels (host version 14 rebuild, 2026-10-18): the framework's (`hybrid/CLAUDE.md`, "Racing wheels"): a wheel Main_MiSTer knows has its pedals as the triggers and its wheel on the left stick's X. `apply_analog()` steers with whichever player's stick is further out, so a wheel that is player 2 (a pad connected first) steers as well, as the framework's SDL driver does for the SDL ports while a wheel is connected (`MH_WheelConnected()`). In a race the left stick's up / down is no d-pad (`mister_input.c`, `PDIsRacing()`): it would be the accelerate / brake keys, and a wheel's gas pedal is on that axis. Tested on the MiSTer with a virtual G29 (`046d:c24f`, uinput) as player 2 next to a DualSense: gas revs and drives, brake stops and reverses, steering left and right took the car to the left and the right of the street from the grid. Not with a real wheel.

## FPGA rasteriser: paused

- The triangle rasteriser (`core/rtl/dethrace_rast*.sv`, `dethrace_ddr_arb.sv`, `core/sim/`, `mister_rast.c`, `tools/rast*`) is development that is paused (Danik, 2026-10-16). It is not in the core: `core/files.qip` and `core/Dethrace.sv` are the template's. Do not build it in or change it unless Danik picks it up again.

## Frame pacing (host version 13, measured 2026-10-16)

- The game's frame rate floats between 30 and 60 fps (most frames take more than a field), so drawing ahead, which helps a game that is a little slower than a field now and then, has nothing to give; the game's own *Lock to 30 FPS* is the steady pacing. Not built in.
- On the MiSTer, `bench/drive.txt` (a race at 320x240, Danik's settings), fps every 2 seconds from 40 to 100 seconds: this build (on the framework's library) about 50 (44 to 54), the released build 20261008 about 44 (38 to 49). No regression from the port.
