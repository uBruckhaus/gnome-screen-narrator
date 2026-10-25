# Page-turn keys: does each SendKey reach the focused window, including the first one?
APP=$XDG_DATA_HOME/kindle-reader/app
mkdir -p "$APP" "$XDG_RUNTIME_DIR/kindle-reader"
cp "$EXT/backend/reader/gnome_desktop.py" "$APP/"
python3 -c '
import json, socket, sys
server = socket.socket(socket.AF_UNIX); server.bind(sys.argv[1]); server.listen()
while True:
    client, _ = server.accept()
    client.recv(4096)
    client.sendall((json.dumps(dict(enabled=True, paused=False, status="Reading")) + "\n").encode())
    client.close()
' "$XDG_RUNTIME_DIR/kindle-reader/control.sock" &
FAKE=$!
# The shell starts in the overview; a window opened there does not get the focus.
busctl --user set-property org.gnome.Shell /org/gnome/Shell org.gnome.Shell OverviewActive b false
sleep 1
gnome-calculator >/dev/null 2>&1 &
sleep 6
ADDRESS=$(python3 "$APP/gnome_desktop.py" active-window | python3 -c 'import json,sys; print(json.load(sys.stdin).get("address", ""))')
echo "focused window: $ADDRESS"
# Digits show up in the calculator's display: a dropped key is a missing digit.
for key in 1 2 3; do
    python3 "$APP/gnome_desktop.py" send-key "$ADDRESS" $key; echo "send-key $key exit: $?"
    sleep ${KEY_GAP:-1}
done
sleep 1
python3 "$APP/gnome_desktop.py" capture "0,0 1920x1080" "$XDG_RUNTIME_DIR/kindle-reader/window.png"
mkdir -p "$ROOT/dist/screenshots"; cp "$XDG_RUNTIME_DIR/kindle-reader/window.png" "$ROOT/dist/screenshots/keys.png"
magick "$ROOT/dist/screenshots/keys.png" -alpha off -crop 120x50+785+532 +repage -colorspace Gray -negate -resize 400% "$T/display.png"
echo "display (must show 123): $(tesseract "$T/display.png" - --psm 7 2>/dev/null)"
kill $FAKE
