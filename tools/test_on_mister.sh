#!/bin/sh
# Try the build on a MiSTer next to what is installed there, without
# installing it (hybrid/CLAUDE.md, "test on the MiSTer"). It runs what
# ./package.sh makes, with the port's own danik_hybrid_launch.sh, but:
#   - the game's folder is /tmp/dethrace_test (gone after a reboot): the
#     installed game's folder (games/dnk/Dethrace/ on a USB drive or the SD
#     card, or games/Dethrace/ of the old layout) mirrored, its folders made anew and its files links to the
#     installed ones, but those under 1MB (settings, saved games; COPY below)
#     copies, so that what the game writes stays in /tmp; and the package
#     over it
#   - the core is in a hidden folder, _Other/.dethrace_test/, loaded with the
#     set name Dethrace_TEST: the OSD settings are config/Dethrace_TEST.CFG, at
#     first a copy of the installed port's, and the game is told which game
#     it is through MISTER_HYBRID_SET
#   - the buttons are the core's defaults (its "jn"): the installed port's
#     mappings are not copied, and one made in an earlier test is removed at
#     every start (Danik, 2026-10-17: to test with the default mappings)
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
# TEST_USB=1 runs it with the game's data on the first USB drive, as a player
# who put the folder there: in games/dnk/.Dethrace_test/ (games/dnk/.Dethrace_empty/
# for nodata), the installed data copied there at the first such test; the
# package stays in /tmp (USB drives are noexec). "stop" removes it too.
# Each copy shows how far it is: pv's percentage and time left for what goes
# over the network (without pv, the name of every file), a percentage and the
# name of every file copied on the MiSTer.
set -e
cd "$(dirname "$0")/.."
NAME=Dethrace
LOWER=dethrace
HOST=${MISTER:?set MISTER=root@<address of the MiSTer>}
USAGE="usage: tools/test_on_mister.sh <id of package/games.txt>|list|nodata|log|stop"
WHAT=${1:?$USAGE}
T=/tmp/${LOWER}_test
# GAME: which of the installed game's files under 1MB are copies, not links
# (shell patterns of their paths in the game's folder; "*" is all of them).
# All, unless they do not fit in /tmp (246MB, with the package): then the
# files the game writes, its settings and saved games.
# Dethrace: all of them filled /tmp with both games installed. What the game
# writes, under DATA/ and SPLATPAK/DATA/ (gApplication_path): OPTIONS.TXT
# (loading.c), KEYMAP_<n>.TXT (options.c) and SAVEGAME/SAVE<n> (loadsave.c),
# a file's name in any case; saves/ and config/ are the launch script's.
COPY="*OPTIONS.TXT *options.txt *KEYMAP*.TXT *keymap*.txt */SAVEGAME/* saves/* config/*"

remote() {
    ssh -o LogLevel=ERROR "$HOST" "$@"
}

# send <folder> <folder on the MiSTer>: what is in it
send() {
    if command -v pv > /dev/null; then
        size=$(cd "$1" && tar cf - . | wc -c)
        (cd "$1" && tar cf - .) | pv -f -i 0.5 -s "$size" -N "${2#/media/fat/}" |
            remote "tar xf - --no-same-owner -C $2"
    else
        echo "${2#/media/fat/}:"
        (cd "$1" && tar cf - .) | remote "tar xvf - --no-same-owner -C $2"
    fi
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
                /media/fat/config/inputs/${NAME}_TEST_* \
                /media/usb[0-7]/games/dnk/.${NAME}_test /media/usb[0-7]/games/dnk/.${NAME}_test.part \
                /media/usb[0-7]/games/dnk/.${NAME}_empty
            for d in /media/usb[0-7]/games/dnk; do [ -d \$d ] && rmdir \$d 2>/dev/null; done
            true"
        echo "Stopped, and the test files are gone."
        exit 0 ;;
    list|nodata)
        SET=$NAME ;;
    *)
        printf '%s\n' "$IDS" | grep -qx "$WHAT" || { echo "$USAGE" >&2; exit 1; }
        # a core of one game has no set name in its menu entry
        if [ "$GAMES" -gt 1 ]; then SET=${NAME}_$WHAT; else SET=$NAME; fi ;;
esac

echo "Packaging..."
./package.sh > /dev/null
OUT=$(ls -d dist/${NAME}_[0-9]*/ | tail -n 1)
OUT=${OUT%/}

stop_game
# the installed game's folder and settings, once
if ! remote "[ -d $T ]"; then
    echo "Mirroring the installed $NAME in $T on the MiSTer..."
    remote "mkdir -p $T $T.empty
        for d in /media/usb[0-7]/games/dnk/$NAME /media/fat/games/dnk/$NAME /media/fat/games/$NAME; do
            [ -d \$d ] || continue
            echo \"  links to the files of \$d\"
            cp -rs \$d/. $T/
            set -f
            n=\$(find $T -type l | wc -l)
            i=0
            find $T -type l | while IFS= read -r f; do
                i=\$((i + 1))
                t=\$(readlink \"\$f\")
                [ -f \"\$t\" ] && [ \$(stat -c %s \"\$t\") -lt 1048576 ] || continue
                for p in $COPY; do
                    case \"\${f#$T/}\" in \$p)
                        cp --remove-destination \"\$t\" \"\$f\"
                        echo \"  [\$((i * 100 / n))%] copied \${f#$T/}\"
                        break ;;
                    esac
                done
            done
            set +f
            break
        done
        cd /media/fat/config
        [ -f $NAME.CFG ] && [ ! -f ${NAME}_TEST.CFG ] && cp $NAME.CFG ${NAME}_TEST.CFG
        [ -f ${NAME}_volume.cfg ] && [ ! -f ${NAME}_TEST_volume.cfg ] && cp ${NAME}_volume.cfg ${NAME}_TEST_volume.cfg
        true"
fi
# the package, every time: over the copy, and alone in the folder without data
echo "Copying $OUT to $HOST..."
for d in $T $T.empty; do
    send "$OUT/games/dnk/$NAME" $d
done
remote "mkdir -p /media/fat/_Other/.${LOWER}_test && rm -f /media/fat/_Other/.${LOWER}_test/*.rbf"
send "$OUT/_Other/dnk" /media/fat/_Other/.${LOWER}_test
remote "printf '%s\n' '<mistergamedescription><rbf>_Other/.${LOWER}_test/dnk-$NAME</rbf><setname>${NAME}_TEST</setname></mistergamedescription>' > $T.mgl"

DIR=$T
[ "$WHAT" = nodata ] && DIR=$T.empty
DATA=$DIR
if [ -n "$TEST_USB" ]; then
    # the package alone in /tmp, the data on the first USB drive
    DIR=$T.empty
    USB=$(remote "awk '\$2 ~ /^\/media\/usb[0-7]\$/ { print \$2; exit }' /proc/mounts")
    [ -n "$USB" ] || { echo "TEST_USB: no USB drive on the MiSTer" >&2; exit 1; }
    if [ "$WHAT" = nodata ]; then
        DATA=$USB/games/dnk/.${NAME}_empty
        remote "mkdir -p $DATA"
    else
        DATA=$USB/games/dnk/.${NAME}_test
        if ! remote "[ -d $DATA ]"; then
            echo "Copying the installed $NAME's data to $DATA on the MiSTer..."
            remote "mkdir -p $USB/games/dnk && rm -rf $DATA.part
                for d in /media/usb[0-7]/games/dnk/$NAME /media/fat/games/dnk/$NAME /media/fat/games/$NAME; do
                    [ -d \$d ] || continue
                    n=\$(find \$d -type f | wc -l)
                    i=0
                    (cd \$d && find . -type d) | while IFS= read -r s; do mkdir -p \"$DATA.part/\$s\"; done
                    (cd \$d && find . -type f) | while IFS= read -r s; do
                        i=\$((i + 1))
                        echo \"  [\$((i * 100 / n))%] \${s#./}\"
                        cp \"\$d/\$s\" \"$DATA.part/\$s\" || exit 1
                    done && mv $DATA.part $DATA
                    break
                done
                mkdir -p $DATA"
        fi
    fi
fi
# the port's launch script, for these folders (it must be the template's)
echo "Loading the test core and starting the game..."
remote "cd $DIR && sed -e 's|^GAMEDIR=.*|GAMEDIR=\"$DIR\"|' -e 's|^DATADIR=.*|DATADIR=\"$DATA\"|' \
        -e 's|^LOGDIR=.*|LOGDIR=\"$T.logs\"|' \
        -e 's|/tmp/$LOWER.lock|/tmp/${LOWER}_test.lock|' -e 's|^RUNLOG=.*|RUNLOG=$T.runlog|' \
        -e '/_nolaunch/d' danik_hybrid_launch.sh > .test_launch.sh
    grep -q '^GAMEDIR=\"$DIR\"' .test_launch.sh && grep -q '^DATADIR=\"$DATA\"' .test_launch.sh &&
        grep -q '^RUNLOG=$T.runlog' .test_launch.sh ||
        { echo 'danik_hybrid_launch.sh is not like the template one: GAMEDIR= / DATADIR= / RUNLOG= lines' >&2; exit 1; }
    rm -f /media/fat/config/inputs/${NAME}_TEST_*
    touch /tmp/${LOWER}_nolaunch
    echo 'load_core $T.mgl' > /dev/MiSTer_cmd
    sleep 4
    setsid env MISTER_HYBRID_SET=$SET $TEST_ENV bash .test_launch.sh > /dev/null 2>&1 < /dev/null &
    echo \$! > $T.pid"
echo "Started ($WHAT, set name $SET, data in $DATA). The OSD settings are the test's own (${NAME}_TEST)."
