# Test-only: the settings window tall enough to show every section in one screenshot.
. "$ROOT/tools/scenarios/menu.pre.sh"
sed -i 's/window.set_default_size(640, 820);/window.set_default_size(700, 2450);/' "$EXT/prefs.js"
