#!/bin/bash
#
# danik_hybrid_cores - starts the game of a MiSTer hybrid core when its core is loaded
#
# A hybrid core is an FPGA core whose game runs on the MiSTer's ARM CPU. This
# script is what connects the two: a small daemon watches which core is loaded
# (/tmp/CORENAME) and runs /media/fat/games/<core name>/danik_hybrid_launch.sh while it is.
# The launcher is stopped when another core is loaded.
#
#   Run it once from the MiSTer's Scripts menu. That starts the daemon and
#   adds it to /media/fat/linux/user-startup.sh, so it also runs after a
#   reboot. Every hybrid core ships this same file; running it again is
#   harmless and picks up a newer version.
#
# usage: danik_hybrid_cores.sh            set up (as from the Scripts menu)
#        danik_hybrid_cores.sh start      start the daemon (what user-startup.sh calls)
#        danik_hybrid_cores.sh stop       stop the daemon and the running game
#        danik_hybrid_cores.sh remove     stop it and take it out of user-startup.sh
#        danik_hybrid_cores.sh status
#
# For a danik_hybrid_launch.sh:
#   - it is run with bash in its own session; its output goes to the log below
#   - on a core switch its whole process group gets SIGTERM, and SIGKILL two
#     seconds later if it is still there
#   - when it exits it is not started again until the core is loaded again
#     (to leave, a launcher loads the menu core)
#
# The whole script is read before anything runs (see the last line), so it can
# be replaced while the daemon is running; the daemon restarts itself with the
# new file as soon as no game is running.

VERSION=1
SELF=$(readlink -f "$0")
GAMES=/media/fat/games
LAUNCHER=danik_hybrid_launch.sh
CORENAME=/tmp/CORENAME
STARTUP=/media/fat/linux/user-startup.sh
PIDFILE=/tmp/danik_hybrid_cores.pid
LOG=/tmp/danik_hybrid_cores.log
MARK="danik_hybrid_cores.sh"

log() {
    echo "$(date '+%H:%M:%S') $*" >> "$LOG"
}

daemon_pid() {
    local pid
    pid=$(cat "$PIDFILE" 2>/dev/null)
    [ -n "$pid" ] && grep -qs "$MARK" "/proc/$pid/cmdline" && echo "$pid"
}

# Launcher of a core name, if it is a hybrid core
launcher_of() {
    case "$1" in
        "" | */* | .*) return 1 ;;
    esac
    [ -f "$GAMES/$1/$LAUNCHER" ] && echo "$GAMES/$1/$LAUNCHER"
}

installed_cores() {
    local f
    for f in "$GAMES"/*/"$LAUNCHER"; do
        [ -f "$f" ] && basename "$(dirname "$f")"
    done
}

# ── daemon ───────────────────────────────────────────────────────────

CHILD=

child_alive() {
    [ -n "$CHILD" ] && kill -0 "$CHILD" 2>/dev/null
}

stop_child() {
    local _
    [ -z "$CHILD" ] && return
    # the launcher leads its own process group (setsid): this reaches the game too
    if kill -TERM -- "-$CHILD" 2>/dev/null; then
        for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
            kill -0 -- "-$CHILD" 2>/dev/null || break
            sleep 0.1
        done
        kill -KILL -- "-$CHILD" 2>/dev/null && log "had to kill the launcher of $CORE"
    fi
    wait "$CHILD" 2>/dev/null
    CHILD=
}

run_daemon() {
    local cur stamp launcher self_stamp

    echo $$ > "$PIDFILE"
    trap 'stop_child; rm -f "$PIDFILE"; exit 0' TERM INT
    [ "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt 200000 ] && mv -f "$LOG" "$LOG.prev"
    log "daemon started (version $VERSION, pid $$), hybrid cores: $(installed_cores | tr '\n' ' ')"
    self_stamp=$(stat -c %Y "$SELF" 2>/dev/null)
    CORE=
    STAMP=

    while :; do
        cur=$(cat "$CORENAME" 2>/dev/null)
        # Main_MiSTer writes the file again whenever a core is loaded
        stamp=$(stat -c %Y "$CORENAME" 2>/dev/null)

        # Another core, or the same core loaded again after its launcher ended
        if [ "$cur" != "$CORE" ] || { [ "$stamp" != "$STAMP" ] && ! child_alive; }; then
            if [ -n "$CHILD" ]; then
                child_alive && log "$CORE -> $cur: stopping its launcher"
                stop_child
            fi
            CORE=$cur
            STAMP=$stamp
            if launcher=$(launcher_of "$cur"); then
                log "$cur loaded: starting $launcher"
                setsid bash "$launcher" >> "$LOG" 2>&1 < /dev/null &
                CHILD=$!
            fi
        elif child_alive; then
            STAMP=$stamp
        elif [ -n "$CHILD" ]; then
            wait "$CHILD" 2>/dev/null
            log "launcher of $CORE ended (exit code $?)"
            CHILD=
        fi

        # A newer version of this file was installed: switch to it between games
        if [ -z "$CHILD" ] && [ "$(stat -c %Y "$SELF" 2>/dev/null)" != "$self_stamp" ] && [ -f "$SELF" ]; then
            if launcher_of "$CORE" > /dev/null; then
                : # a hybrid core is still loaded and would be started again
            else
                log "restarting with the new $SELF"
                exec bash "$SELF" daemon
            fi
        fi
        sleep 0.5
    done
}

# ── commands ─────────────────────────────────────────────────────────

start_daemon() {
    [ -n "$(daemon_pid)" ] && return 0
    setsid bash "$SELF" daemon > /dev/null 2>&1 < /dev/null &
    sleep 0.3
}

stop_daemon() {
    local pid _
    pid=$(daemon_pid)
    [ -z "$pid" ] && return 0
    kill -TERM "$pid" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    kill -KILL "$pid" 2>/dev/null
    rm -f "$PIDFILE"
}

register() {
    grep -qsF "$MARK" "$STARTUP" && return 0
    [ -f "$STARTUP" ] || printf '#!/bin/sh\n' > "$STARTUP"
    # shellcheck disable=SC2016  # $1 is for user-startup.sh
    printf '\n# Hybrid cores: starts the game when its core is loaded\n[[ -e %s ]] && %s $1\n' "$SELF" "$SELF" >> "$STARTUP"
    chmod +x "$STARTUP" 2>/dev/null
}

unregister() {
    [ -f "$STARTUP" ] || return 0
    sed -i "/# Hybrid cores: starts the game when its core is loaded/d; /$MARK/d" "$STARTUP"
}

status() {
    local pid cores
    pid=$(daemon_pid)
    cores=$(installed_cores | tr '\n' ' ')
    echo "danik_hybrid_cores version $VERSION"
    if [ -n "$pid" ]; then echo "  running (pid $pid)"; else echo "  not running"; fi
    if grep -qsF "$MARK" "$STARTUP"; then echo "  starts with the MiSTer"; else echo "  does not start with the MiSTer"; fi
    echo "  hybrid cores installed: ${cores:-none}"
}

main() {
    case "$1" in
        daemon)
            run_daemon
            ;;
        start)
            start_daemon
            ;;
        stop)
            stop_daemon
            ;;
        restart)
            stop_daemon
            start_daemon
            ;;
        remove)
            stop_daemon
            unregister
            echo "danik_hybrid_cores is stopped and removed from $STARTUP."
            echo "Hybrid cores no longer start their games."
            ;;
        status)
            status
            ;;
        "")
            # set up; a running daemon is replaced so a new version takes over,
            # unless a game is being played
            register
            if [ -n "$(daemon_pid)" ] && launcher_of "$(cat "$CORENAME" 2>/dev/null)" > /dev/null; then
                : # the daemon switches to the new file by itself after the game
            else
                stop_daemon
            fi
            start_daemon
            status
            echo
            echo "Done. Load a hybrid core and its game starts."
            sleep 3
            ;;
        *)
            echo "usage: $0 [start|stop|restart|remove|status]"
            return 1
            ;;
    esac
}

# keep this on one line: bash must have read the whole file before it runs
main "$@"; exit $?
