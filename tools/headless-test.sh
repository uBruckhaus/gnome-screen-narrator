#!/bin/bash
# Runs the extension in a throwaway headless GNOME Shell with its own D-Bus, dconf and
# data folders and prints the extension's log. The real session is never touched.
# Usage: tools/headless-test.sh [scenario]   (scenarios in tools/scenarios/)
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
UUID=screen-narrator@ubruckhaus.github.io
if [ -z "${SN_INNER:-}" ]; then
    T=$(mktemp -d)
    mkdir -p "$T/config" "$T/data" "$T/cache" "$T/state" "$T/run"
    chmod 700 "$T/run"
    # Its own runtime folder too, so a running reader (kindle-reader/control.sock) is never reached.
    export SN_INNER=1 T XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_CACHE_HOME=$T/cache XDG_STATE_HOME=$T/state XDG_RUNTIME_DIR=$T/run
    dbus-run-session -- "$0" "$@" 2> >(grep -v -e dbus-daemon -e fusermount >&2)
    exit $?
fi
EXT=$XDG_DATA_HOME/gnome-shell/extensions/$UUID
"$ROOT/tools/build.sh" >/dev/null && mkdir -p "$EXT" && unzip -q "$ROOT/dist/$UUID.shell-extension.zip" -d "$EXT"
gsettings set org.gnome.shell disable-user-extensions false
gsettings set org.gnome.shell enabled-extensions "['$UUID']"
gsettings set org.gnome.shell welcome-dialog-last-shown-version "$(gnome-shell --version | awk '{print $3}')"
[ "$(gsettings get org.gnome.shell enabled-extensions)" = "['$UUID']" ] || { echo "isolated dconf not working" >&2; exit 1; }
SCENARIO=${1:-menu}
[ -f "$ROOT/tools/scenarios/$SCENARIO.pre.sh" ] && . "$ROOT/tools/scenarios/$SCENARIO.pre.sh"

gnome-shell --headless --wayland --no-x11 --virtual-monitor ${MONITOR:-1920x1080} \
    --wayland-display sn-test >"$T/shell.log" 2>&1 &
SHELL_PID=$!
sleep 8
export WAYLAND_DISPLAY=sn-test
# No X fallback: an app that loses the test shell must not open in the real session.
unset DISPLAY
. "$ROOT/tools/scenarios/$SCENARIO.sh"
kill $SHELL_PID 2>/dev/null; sleep 1
grep -v -e Gtk-WARNING -e "^$" "$T/shell.log" | grep -i -e "narrator\|js\|error\|exception" | head -${LINES_MAX:-80}
