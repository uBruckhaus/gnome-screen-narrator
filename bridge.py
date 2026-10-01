"""One-shot JSON bridge to the local Simple Reader reader service."""
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path


def request(payload):
    command = payload.get('command', 'status')
    if command not in {'status', 'on', 'off', 'toggle', 'read', 'pause', 'select-area', 'clear-area', 'configure', 'configure-token', 'online-models', 'install-kokoro', 'cancel-kokoro-install'}:
        raise ValueError('Unknown command')
    endpoint = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'kindle-reader/control.sock'
    if not endpoint.exists():
        if command == 'status':
            return {'enabled': False, 'status': 'Reader service is stopped. Click Start reader.', 'settings': {}}
        subprocess.run(['systemctl', '--user', 'start', 'ocrvox.service'], check=True, timeout=10, stdout=subprocess.DEVNULL)
        for _ in range(50):
            if endpoint.exists():
                break
            time.sleep(.1)
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(8)
        client.connect(str(endpoint))
        client.sendall((json.dumps(payload) + '\n').encode())
        chunks = bytearray()
        while b'\n' not in chunks:
            part = client.recv(65536)
            if not part:
                break
            chunks.extend(part)
            if len(chunks) > 1048576:
                raise ValueError('Reader response too large')
        return json.loads(chunks.split(b'\n', 1)[0])


if __name__ == '__main__':
    try:
        print(json.dumps(request(json.loads(sys.stdin.readline()))))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(json.dumps({'error': str(error)}))
