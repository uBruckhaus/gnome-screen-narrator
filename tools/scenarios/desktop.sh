# The D-Bus service the reader uses: a focused window, the window list, refusals.
gnome-calculator >/dev/null 2>&1 &
sleep 4
B="busctl --user --json=short call io.github.ubruckhaus.ScreenNarrator /io/github/ubruckhaus/ScreenNarrator io.github.ubruckhaus.ScreenNarrator.Desktop"
echo "ActiveWindow: $($B ActiveWindow)"
echo "Clients: $($B Clients)"
echo "Capture (reading off, must be false): $($B Capture ss '0,0 100x100' "$XDG_RUNTIME_DIR/kindle-reader/window.png")"
echo "SendKey (must be false): $($B SendKey ss 0x1 Right)"
sleep 1
