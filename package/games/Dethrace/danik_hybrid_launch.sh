#!/bin/bash
#
# Dethrace (Carmageddon) launcher. danik_hybrid_cores (Scripts/danik_hybrid_cores.sh) runs
# it when the Dethrace core is loaded and stops it, with SIGTERM to the process
# group, when another core is loaded.
#
# Laid out after the per-core handlers of MiSTer Frontier by MiSTer Organize
# (https://github.com/MiSTerOrganize/MiSTer_Frontier, GPL-3.0), with thanks
# for the inspiration. Licensed under the GPL-3.0.

GAMEDIR="/media/fat/games/Dethrace"
LOGDIR="/media/fat/logs/Dethrace"

cd "$GAMEDIR" || exit 1
mkdir -p "$LOGDIR"

# Only once
exec 9> /tmp/dethrace.lock
flock -n 9 || exit 0

# Development: keep the core loaded without starting the game
[ -f /tmp/dethrace_nolaunch ] && exit 0

if [ ! -f DATA/GENERAL.TXT ]; then
    echo "No game data: copy Carmageddon's DATA folder to $GAMEDIR/DATA" > "$LOGDIR/dethrace.log"
    exit 1
fi

# The launcher of releases before 20261004 is no longer used. If something is
# still running it, it must not end up starting a second game.
rm -f _handler.sh

# FPGA settle after the core was just loaded
sleep 1.5
[ -n "$(pidof Dethrace)" ] && exit 0

mv -f "$LOGDIR/dethrace.log" "$LOGDIR/dethrace.prev.log" 2>/dev/null

# No HOME: dethrace.ini (optional) is then read from the game directory.
# Both CPUs: the game pins its render thread to CPU0 (better DDR3 bandwidth,
# Main_MiSTer lives on CPU1) and runs audio and the frame copy on CPU1.
# The game loads the MiSTer menu itself when the player quits.
export DETHRACE_MISTER_QUIT_TO_MENU=1
exec env -u HOME -u XDG_DATA_HOME taskset 0x03 ./Dethrace --dir "$GAMEDIR" > "$LOGDIR/dethrace.log" 2>&1
