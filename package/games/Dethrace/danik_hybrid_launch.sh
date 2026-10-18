#!/bin/bash
#
# Dethrace (Carmageddon) launcher. danik_hybrid_ports (Scripts/danik_hybrid_ports.sh)
# runs it when the Dethrace core is loaded (also with a game's set name, from
# its menu entry: MISTER_HYBRID_SET, which the game reads) and stops it, with
# SIGTERM to the process group, when another core is loaded.
#
# Laid out after the per-core handlers of MiSTer Frontier by MiSTer Organize
# (https://github.com/MiSTerOrganize/MiSTer_Frontier, GPL-3.0), with thanks
# for the inspiration. Licensed under the GPL-3.0.

CORE="Dethrace"
GAMEDIR="/media/fat/games/dnk/$CORE"
LOGDIR="/media/fat/logs/dnk/$CORE"
LOG="$LOGDIR/dethrace.log"
# The game's data, settings and saved games: games/dnk/Dethrace/ on a USB drive
# if the player put the folder there (the first of usb0..usb7 that has it,
# as Main_MiSTer looks for a core's games there before the SD card), else on
# the SD card. The game runs in that folder. Its programs stay in GAMEDIR on
# the SD card, where Downloader installs them: USB drives are mounted noexec.
DATADIR=$(for d in /media/usb[0-7]/games/dnk/"$CORE" "$GAMEDIR"; do [ -d "$d" ] && { echo "$d"; break; }; done)

cd "$DATADIR" || exit 1
mkdir -p "$LOGDIR" config saves

# Only once
exec 9> /tmp/dethrace.lock
flock -n 9 || exit 0

# Development: keep the core loaded without starting the game
[ -f /tmp/dethrace_nolaunch ] && exit 0

# FPGA settle after the core was just loaded
sleep 1

mv -f "$LOG" "$LOGDIR/dethrace.prev.log" 2>/dev/null
echo "Game data in $DATADIR" > "$LOG"

# What the game prints is kept in memory while it runs and goes to the log on
# the SD card when it has left. The card is mounted "sync": a line printed
# straight to it is a write that waits for the card, about 9ms in which the
# game stands still. (A game that is still running when the MiSTer is
# switched off leaves no log of that run.)
RUNLOG=/tmp/dethrace.log
: > "$RUNLOG"
savelog() {
    cat "$RUNLOG" >> "$LOG" 2>/dev/null
    : > "$RUNLOG"
}

# For the hybrid core drivers in the binary: which core to attach to and its
# default button mapping ("jn" in core/Dethrace.sv)
export MISTER_HYBRID_CORE="$CORE"
export MISTER_HYBRID_JN="B,Y,A,X,L,Select,R,Start"
# Everything the game writes stays in its folder
export HOME="$DATADIR"
export XDG_CONFIG_HOME="$DATADIR/config"
export XDG_DATA_HOME="$DATADIR/config"

# Both CPUs: the game takes CPU0 (better DDR3 bandwidth, Main_MiSTer lives on
# CPU1) and runs audio and the frame copy on CPU1. Everything else on the
# MiSTer (scripts, daemons, interrupts) lands on CPU0 as well: without the
# higher priority the game waits for it a quarter of the time and misses fields.
# Exit code 42: the player quit a game picked from a list (MH_UI_Menu), start
# again to show the list. Exit code 43: the core was loaded again while the
# game ran (MH_CoreReloaded), start again once it has settled, unless it was
# another core after all.
GAME=
# The game must not outlive us: on SIGTERM it saves its settings and quits
trap '[ -n "$GAME" ] && kill "$GAME" 2>/dev/null && wait "$GAME"; savelog; exit 0' TERM INT
while :; do
    # GAME: its command line (where it finds data, settings and saved games:
    # DATADIR, the current folder; what came with the port, libraries the game
    # loads among them: GAMEDIR). No HOME: dethrace.ini (optional) is read
    # from the game's folder. The game pins its render thread to CPU0 and runs
    # audio and the frame copy on CPU1; it goes into SPLATPAK/ itself for the
    # Splat Pack.
    nice -n -20 taskset 0x03 env -u HOME -u XDG_DATA_HOME "$GAMEDIR/Dethrace" --dir "$DATADIR" >> "$RUNLOG" 2>&1 &
    GAME=$!
    wait "$GAME"
    RC=$?
    savelog
    if [ $RC -eq 43 ]; then
        sleep 1
        grep -q "^$CORE" /tmp/CORENAME 2>/dev/null || break
    elif [ $RC -ne 42 ]; then
        break
    fi
done
GAME=

# Unless another core was loaded meanwhile: a game that left with an error
# (one that crashed: 128 + the signal) and put no message up says so on the
# core's picture (./mh_message, host version 13), and a message stays there
# until the player leaves the core. Else back to the MiSTer menu.
if grep -q "^$CORE" /tmp/CORENAME 2>/dev/null; then
    if [ $RC -ne 0 ] && ! "$GAMEDIR/mh_message" --shown >> "$LOG" 2>&1; then
        "$GAMEDIR/mh_message" --error "The game stopped unexpectedly (exit code $RC).\nIts log: ${LOG#/media/fat/}" >> "$LOG" 2>&1
        sleep 0.1
    fi
    "$GAMEDIR/mh_message" --shown >> "$LOG" 2>&1 || echo "load_core /media/fat/menu.rbf" > /dev/MiSTer_cmd
fi
