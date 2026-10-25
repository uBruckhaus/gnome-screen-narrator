# A screenshot through the reader's helper, as the installed reader takes it: the helper at
# its installed path, and a stand-in reader socket that says reading is on.
APP=$XDG_DATA_HOME/kindle-reader/app
mkdir -p "$APP" "$XDG_RUNTIME_DIR/kindle-reader"
cp "$EXT/backend/reader/gnome_desktop.py" "$APP/"
python3 -c '
import json, socket, os, sys
path = sys.argv[1]
server = socket.socket(socket.AF_UNIX); server.bind(path); server.listen()
while True:
    client, _ = server.accept()
    client.recv(4096)
    client.sendall((json.dumps(dict(enabled=True, paused=False, status="Reading")) + "\n").encode())
    client.close()
' "$XDG_RUNTIME_DIR/kindle-reader/control.sock" &
FAKE=$!
gnome-calculator >/dev/null 2>&1 &
sleep 4
OUT=$XDG_RUNTIME_DIR/kindle-reader/window.png
python3 "$APP/gnome_desktop.py" capture "700,200 500x400" "$OUT"; echo "helper capture exit: $?"
file "$OUT"
mkdir -p "$ROOT/dist/screenshots"; cp "$OUT" "$ROOT/dist/screenshots/capture.png"
python3 "$APP/gnome_desktop.py" capture "700,200 500x400" "$XDG_RUNTIME_DIR/elsewhere.png"; echo "other path exit (must be 1): $?"
python3 "$EXT/backend/reader/gnome_desktop.py" capture "700,200 500x400" "$OUT"; echo "not the installed helper (must be 1): $?"
ADDRESS=$(python3 "$APP/gnome_desktop.py" active-window | python3 -c 'import json,sys; print(json.load(sys.stdin).get("address", ""))')
echo "focused window: $ADDRESS"
python3 "$APP/gnome_desktop.py" send-key "$ADDRESS" Right; echo "send-key to the focused window: $?"
python3 "$APP/gnome_desktop.py" send-key 0x1 Right; echo "send-key to another window (must be 1): $?"
printf '{"rectangles": [{"x": 820, "y": 330, "width": 280, "height": 22}, {"x": 820, "y": 360, "width": 200, "height": 22}], "target": "%s"}' "${ADDRESS#0x}" > "$XDG_RUNTIME_DIR/kindle-reader/highlight.json"
sleep 3
kill $FAKE
