#!/bin/sh
# Builds dist/screen-narrator@ubruckhaus.github.io.shell-extension.zip: the extension and its
# reader backend, without the backend's tests.
set -eu
cd "$(dirname "$0")/.."
UUID=screen-narrator@ubruckhaus.github.io
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -r "$UUID" "$STAGE/"
find "$STAGE/$UUID/backend" \( -name 'test_*.py' -o -name '__pycache__' \) -prune -exec rm -rf {} +
mkdir -p dist
gnome-extensions pack "$STAGE/$UUID" --force --out-dir dist \
    --extra-source=bridge.js --extra-source=desktop.js --extra-source=highlight.js \
    --extra-source=indicator.js --extra-source=backend
echo "dist/$UUID.shell-extension.zip"
