#!/usr/bin/env bash
set -euo pipefail
umask 077
source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
data_dir="$HOME/.local/share/kindle-reader"
unit_dir="$HOME/.config/systemd/user"
if systemctl --user cat ocrvox.service >/dev/null 2>&1; then
  echo 'Existing ocrvox.service found; keeping its service, runtime and settings.'
  echo 'Enable the widget and use its existing reader installation.'
  exit 0
fi
for dependency in uv grim slurp magick tesseract mpv wtype quickshell hyprctl; do
  command -v "$dependency" >/dev/null || { echo "Missing dependency: $dependency. See README.md." >&2; exit 1; }
done
mkdir -p "$data_dir/app" "$unit_dir"
if [[ ! -x "$data_dir/venv/bin/python" ]]; then
  uv venv --python 3.14 --seed "$data_dir/venv"
fi
uv pip install --python "$data_dir/venv/bin/python" -r "$source_dir/requirements.txt"
cp "$source_dir"/reader/*.py "$source_dir"/reader/*.qml "$data_dir/app/"
cat > "$unit_dir/ocrvox.service" <<'UNIT'
[Unit]
Description=Simple Reader OCR and speech
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/share/kindle-reader/venv/bin/python %h/.local/share/kindle-reader/app/reader.py
Environment=OCRVOX_BAR_WIDGET=1
Environment=PYTHONDONTWRITEBYTECODE=1
Restart=on-failure
RestartSec=3
KillMode=control-group
TimeoutStopSec=5
UMask=0077
UNIT
systemctl --user daemon-reload
echo 'Reader installed. Enable the plugin, select a language and install Kokoro from its popup.'
echo 'Narration starts only after Start reader. No shortcuts or login autostart were changed.'
