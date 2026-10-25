# The pinned book window: captured and turned while another window has the focus and covers
# it; refused while it is on another workspace or minimized. The "book" is a Chrome page
# whose title counts ticks and keys.
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
H="python3 $APP/gnome_desktop.py"
OUT=$XDG_RUNTIME_DIR/kindle-reader/window.png
DO() { busctl --user call io.github.ubruckhaus.ScreenNarrator /test io.github.ubruckhaus.ScreenNarrator.Test Do ss "$1" "$2" || echo "DO $1 failed"; }
field() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get(sys.argv[1], ""))' "$1"; }
ocr() { magick "$OUT" -alpha off -resize 200% "$T/ocr.png"; tesseract "$T/ocr.png" - --psm 6 2>/dev/null | tr -s '\n' ' '; }
busctl --user set-property org.gnome.Shell /org/gnome/Shell org.gnome.Shell OverviewActive b false
PAGE='data:text/html,<body style="font:60px sans-serif;margin:40px"><div id=c></div><script>let n=0,k=0;setInterval(()=>{n++;document.getElementById("c").textContent="tick "+n+" keys "+k;document.title="Book n="+n+" k="+k},500);addEventListener("keydown",()=>k++);</script>'
google-chrome-stable --ozone-platform=wayland --user-data-dir="$T/chrome" --no-first-run --no-default-browser-check \
    --password-store=basic --app="$PAGE" >/dev/null 2>&1 &
sleep 7
BOOK=$($H active-window | field address)
geom() { $H window "$BOOK" | python3 -c 'import json,sys; d=json.load(sys.stdin); x,y=d["at"]; print(f"{x+20},{y+60} 600x120")'; }
echo "book: $BOOK"
gnome-calculator >/dev/null 2>&1 &
sleep 4
DO cover Calculator
sleep 1
echo "focused: $($H active-window | field title)"
echo "book state: $($H window "$BOOK")"
$H capture-window "$BOOK" "$(geom)" "$OUT"; echo "capture covered book: $? text: $(ocr)"
sleep 2
$H capture-window "$BOOK" "$(geom)" "$OUT"; echo "2 s later: $? text: $(ocr)"
$H send-key "$BOOK" Right; echo "send-key to covered book: $?"
sleep 1
echo "after the key: book title $($H window "$BOOK" | field title), focused $($H active-window | field title)"
$H capture "$(geom)" "$OUT"; echo "the screen there shows the calculator, not the book: $? text: $(ocr)"
DO workspace2 Book
sleep 1
echo "on workspace 2: $($H window "$BOOK" | field shown)"
$H capture-window "$BOOK" "$(geom)" "$OUT"; echo "capture (must be 1): $?"
$H send-key "$BOOK" Right; echo "send-key (must be 1): $?"
echo "focus stayed: $($H active-window | field title), workspace $(busctl --user get-property org.gnome.Shell /org/gnome/Shell org.gnome.Shell OverviewActive >/dev/null; echo ok)"
DO workspace1 Book
DO minimize Book
sleep 1
$H capture-window "$BOOK" "$(geom)" "$OUT"; echo "minimized capture (must be 1): $?"
DO unminimize Book
sleep 1
$H capture-window "$BOOK" "$(geom)" "$OUT"; echo "back: $? text: $(ocr)"
$H capture-window 0x1 "0,0 100x100" "$OUT"; echo "unknown window (must be 1): $?"
python3 "$EXT/backend/reader/gnome_desktop.py" capture-window "$BOOK" "$(geom)" "$OUT"; echo "not the installed helper (must be 1): $?"
python3 "$EXT/backend/reader/gnome_desktop.py" send-key "$BOOK" Right; echo "key from another helper (must be 1): $?"
echo "closed window: $($H window 0x1)"
kill $FAKE
