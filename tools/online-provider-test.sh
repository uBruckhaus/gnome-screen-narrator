#!/bin/bash
# The speech-server flow end to end, without GNOME: the real reader (from the repo) with a
# throwaway HOME and runtime folder, a stand-in OpenAI-compatible speech server on localhost,
# a stand-in mpv, and the requests the settings window sends through bridge.py.
# Usage: PYTHON=/path/to/venv/bin/python tools/online-provider-test.sh   (a Python with PySide6)
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BACKEND=$ROOT/screen-narrator@ubruckhaus.github.io/backend
PYTHON=${PYTHON:-python3}
T=$(mktemp -d)
mkdir -p "$T/home" "$T/run" "$T/bin" && chmod 700 "$T/run"
export HOME=$T/home XDG_RUNTIME_DIR=$T/run QT_QPA_PLATFORM=offscreen PYTHONDONTWRITEBYTECODE=1 PATH=$T/bin:$PATH
printf '#!/bin/sh\nexit 0\n' > "$T/bin/mpv"; printf '#!/bin/sh\nexit 0\n' > "$T/bin/notify-send"; chmod +x "$T/bin/"*
PORT=18931
python3 - "$PORT" "$T/requests.log" <<'PY' &
import http.server, io, json, struct, sys, wave
port, log = int(sys.argv[1]), sys.argv[2]
def wav():
    out = io.BytesIO()
    with wave.open(out, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000); w.writeframes(b'\0\0' * 1600)
    return out.getvalue()
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, body, kind):
        self.send_response(200); self.send_header('Content-Type', kind); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        open(log, 'a').write(f'GET {self.path} auth={self.headers.get("Authorization")}\n')
        self.reply(json.dumps({'data': [{'id': 'tts-1'}, {'id': 'chat-model'}]}).encode(), 'application/json')
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        open(log, 'a').write(f'POST {self.path} model={body["model"]} voice={body["voice"]} auth={self.headers.get("Authorization")}\n')
        self.reply(wav(), 'audio/wav')
http.server.HTTPServer(('127.0.0.1', port), Handler).serve_forever()
PY
SERVER=$!
"$PYTHON" "$BACKEND/reader/reader.py" 2>"$T/reader.log" &
READER=$!
for _ in $(seq 50); do [ -S "$T/run/kindle-reader/control.sock" ] && break; sleep 0.1; done
ask() { echo "$1" | python3 "$BACKEND/bridge.py"; }
field() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
URL=http://127.0.0.1:$PORT/v1
CANDIDATE="{\"provider\": \"Online\", \"online_endpoint\": \"$URL\", \"online_model\": \"tts-1\", \"online_voice\": \"alloy\"}"

echo "models: $(ask "{\"command\": \"online-models\", \"endpoint\": \"$URL\", \"token\": \"secret\"}" >/dev/null; sleep 1; ask '{"command": "status"}' | field "d['online_models']")"
echo "use before test (must fail): $(ask "{\"command\": \"use-provider\", \"settings\": $CANDIDATE}" | field "d.get('error')")"
ask "{\"command\": \"test-provider\", \"settings\": $CANDIDATE, \"token\": \"secret\"}" >/dev/null
sleep 2
echo "after test: $(ask '{"command": "status"}' | field "(d['status'], d['verified_provider'] is not None)")"
echo "use with another token (must fail): $(ask "{\"command\": \"use-provider\", \"settings\": $CANDIDATE, \"token\": \"other\"}" | field "d.get('error')")"
echo "use: $(ask "{\"command\": \"use-provider\", \"settings\": $CANDIDATE, \"token\": \"secret\", \"remember_token\": true}" | field "(d.get('error'), d['settings']['provider'], d['settings']['online_model'], d['key_ready'])")"
echo "saved token file mode: $(stat -c %a "$HOME/.config/kindle-reader/speech-credentials.json" 2>/dev/null)"
echo "back to local: $(ask '{"command": "configure", "settings": {"provider": "Local"}}' | field "d.get('error') or d['settings']['provider']")"
echo "--- server saw:"; cat "$T/requests.log"
kill $READER $SERVER 2>/dev/null; wait 2>/dev/null
rm -rf "$T"
