#!/bin/sh
# Try the build on a MiSTer next to what is installed there, without
# installing it (hybrid/CLAUDE.md, "test on the MiSTer"). It runs what
# ./package.sh makes, with the port's own danik_hybrid_launch.sh, but:
#   - the game's folder is /tmp/dethrace_test (gone after a reboot): the
#     installed game's folder (games/dnk/Dethrace/, or games/Dethrace/ of the old
#     layout) mirrored, its folders made anew and its files links to the
#     installed ones, but those under 1MB (settings, saved games) copies, so
#     that what the game writes stays in /tmp; and the package over it
#   - the core is in a hidden folder, _Other/.dethrace_test/, loaded with the
#     set name Dethrace_TEST: the OSD settings are config/Dethrace_TEST.CFG, at
#     first a copy of the installed port's, and the game is told which game
#     it is through MISTER_HYBRID_SET
#   - /tmp/dethrace_nolaunch keeps a launcher from starting the installed port
# No launcher is involved and none is touched. "stop" removes all of it.
# usage: MISTER=root@<address> tools/test_on_mister.sh <what>
#   <id>     a game of package/games.txt, as from its menu entry
#   list     as the core started by itself (Recent, the .rbf): the list
#   nodata   in a folder without the game's data: the core's message
#   log      the game's log so far
#   stop     stop the game, back to the menu, remove all of it
# TEST_ENV="VAR=value ..." in the environment goes to the game as well, e.g.
# MISTER_HYBRID_PACE=1 to measure the frame pacing (see the log).
set -e
cd "$(dirname "$0")/.."
NAME=Dethrace
LOWER=dethrace
HOST=${MISTER:?set MISTER=root@<address of the MiSTer>}
USAGE="usage: tools/test_on_mister.sh <id of package/games.txt>|list|nodata|log|stop"
WHAT=${1:?$USAGE}
T=/tmp/${LOWER}_test

remote() {
    ssh -o LogLevel=ERROR "$HOST" "$@"
}

# the launch script, which stops the game (and saves its log) on SIGTERM
stop_game() {
    remote "if [ -f $T.pid ]; then
            p=\$(cat $T.pid); kill \$p 2>/dev/null
            for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 \$p 2>/dev/null || break; sleep 1; done
            rm -f $T.pid
        fi"
}

IDS=$(grep -v '^#' package/games.txt | grep '|' | cut -d'|' -f1)
GAMES=$(printf '%s\n' "$IDS" | grep -c .)
case $WHAT in
    log)
        remote "cat $T.logs/$LOWER.log $T.runlog 2>/dev/null"
        exit 0 ;;
    stop)
        stop_game
        remote "echo 'load_core /media/fat/menu.rbf' > /dev/MiSTer_cmd
            rm -rf $T $T.empty $T.logs $T.mgl $T.runlog /tmp/${LOWER}_nolaunch /tmp/${LOWER}_test.lock \
                /media/fat/_Other/.${LOWER}_test /media/fat/screenshots/${NAME}_TEST \
                /media/fat/config/${NAME}_TEST.CFG /media/fat/config/${NAME}_TEST_volume.cfg \
                /media/fat/config/inputs/${NAME}_TEST_*"
        echo "Stopped, and the test files are gone."
        exit 0 ;;
    list|nodata)
        SET=$NAME ;;
    *)
        printf '%s\n' "$IDS" | grep -qx "$WHAT" || { echo "$USAGE" >&2; exit 1; }
        # a core of one game has no set name in its menu entry
        if [ "$GAMES" -gt 1 ]; then SET=${NAME}_$WHAT; else SET=$NAME; fi ;;
esac

./package.sh > /dev/null
OUT=$(ls -d dist/${NAME}_[0-9]*/ | tail -n 1)
OUT=${OUT%/}

stop_game
# the installed game's folder and settings, once
if ! remote "[ -d $T ]"; then
    echo "Mirroring the installed $NAME in $T on the MiSTer..."
    remote "mkdir -p $T $T.empty
        for d in /media/fat/games/dnk/$NAME /media/fat/games/$NAME; do
            [ -d \$d ] || continue
            cp -rs \$d/. $T/
            find $T -type l | while IFS= read -r f; do
                t=\$(readlink \"\$f\")
                [ -f \"\$t\" ] && [ \$(stat -c %s \"\$t\") -lt 1048576 ] && cp --remove-destination \"\$t\" \"\$f\"
            done
            break
        done
        cd /media/fat/config
        [ -f $NAME.CFG ] && [ ! -f ${NAME}_TEST.CFG ] && cp $NAME.CFG ${NAME}_TEST.CFG
        [ -f ${NAME}_volume.cfg ] && [ ! -f ${NAME}_TEST_volume.cfg ] && cp ${NAME}_volume.cfg ${NAME}_TEST_volume.cfg
        for f in inputs/${NAME}_input_* inputs/${NAME}_advanced_input_*; do
            [ -f \"\$f\" ] && cp \"\$f\" \"inputs/${NAME}_TEST\${f#inputs/$NAME}\"
        done
        true"
fi
# the package, every time: over the copy, and alone in the folder without data
for d in $T $T.empty; do
    (cd "$OUT/games/dnk/$NAME" && tar cf - .) | remote "tar xf - --no-same-owner -C $d"
done
remote "mkdir -p /media/fat/_Other/.${LOWER}_test && rm -f /media/fat/_Other/.${LOWER}_test/*.rbf"
(cd "$OUT/_Other/dnk" && tar cf - .) | remote "tar xf - --no-same-owner -C /media/fat/_Other/.${LOWER}_test"
remote "printf '%s\n' '<mistergamedescription><rbf>_Other/.${LOWER}_test/dnk-$NAME</rbf><setname>${NAME}_TEST</setname></mistergamedescription>' > $T.mgl"

DIR=$T
[ "$WHAT" = nodata ] && DIR=$T.empty
# the port's launch script, for this folder (it must be the template's)
remote "cd $DIR && sed -e 's|^GAMEDIR=.*|GAMEDIR=\"$DIR\"|' -e 's|^LOGDIR=.*|LOGDIR=\"$T.logs\"|' \
        -e 's|/tmp/$LOWER.lock|/tmp/${LOWER}_test.lock|' -e 's|^RUNLOG=.*|RUNLOG=$T.runlog|' \
        -e '/_nolaunch/d' danik_hybrid_launch.sh > .test_launch.sh
    grep -q '^GAMEDIR=\"$DIR\"' .test_launch.sh && grep -q '^RUNLOG=$T.runlog' .test_launch.sh ||
        { echo 'danik_hybrid_launch.sh is not like the template one: GAMEDIR= / RUNLOG= lines' >&2; exit 1; }
    touch /tmp/${LOWER}_nolaunch
    echo 'load_core $T.mgl' > /dev/MiSTer_cmd
    sleep 4
    setsid env MISTER_HYBRID_SET=$SET $TEST_ENV bash .test_launch.sh > /dev/null 2>&1 < /dev/null &
    echo \$! > $T.pid"
echo "Started ($WHAT, set name $SET). The OSD settings are the test's own (${NAME}_TEST)."
