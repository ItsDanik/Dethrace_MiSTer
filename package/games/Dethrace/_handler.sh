#!/bin/bash
#
# Dethrace (Carmageddon) handler, started by MiSTer Frontier's Master_Daemon
# when the Dethrace core loads. The daemon kills us on core switch and
# respawns us if the game exits while the core is still loaded.

GAMEDIR="/media/fat/games/Dethrace"
LOGDIR="/media/fat/logs/Dethrace"

cd "$GAMEDIR" || exit 1
mkdir -p "$LOGDIR"

# Development: keep the core loaded without starting the game
if [ -f /tmp/dethrace_nolaunch ]; then
    exec sleep 2147483647
fi

if [ ! -f DATA/GENERAL.TXT ]; then
    echo "No game data: copy Carmageddon's DATA folder to $GAMEDIR/DATA" > "$LOGDIR/dethrace.log"
    exec sleep 2147483647
fi

# FPGA settle after the core was just loaded
sleep 1

mv -f "$LOGDIR/dethrace.log" "$LOGDIR/dethrace.prev.log" 2>/dev/null

# No HOME: dethrace.ini (optional) is then read from the game directory.
# Both CPUs: the game pins its render thread to CPU0 (better DDR3 bandwidth,
# Main_MiSTer lives on CPU1) and runs audio and the frame copy on CPU1.
export DETHRACE_MISTER_QUIT_TO_MENU=1
exec env -u HOME -u XDG_DATA_HOME taskset 0x03 ./Dethrace --dir "$GAMEDIR" > "$LOGDIR/dethrace.log" 2>&1
