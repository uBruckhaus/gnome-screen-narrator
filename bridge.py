"""One-shot private IPC and first-use setup for Screen Narrator."""
import json
import os
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path
from setup_backend import DATA, ROOT, missing_packages, runtime_ready, setup_state, setup_pid
import languages

COMMANDS = {'status', 'on', 'off', 'toggle', 'read', 'pause', 'select-area', 'clear-area',
            'configure', 'configure-token', 'online-models', 'install-kokoro',
            'cancel-kokoro-install', 'setup', 'cancel-setup', 'test-voice',
            'check-kokoro-updates', 'update-kokoro', 'test-provider', 'use-provider', 'probe-provider'}


def socket_request(payload):
    endpoint = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'kindle-reader/control.sock'
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(8)
        for attempt in range(50):
            try:
                client.connect(str(endpoint))
                break
            except (FileNotFoundError, ConnectionRefusedError):
                if attempt == 0:
                    subprocess.run(['systemctl', '--user', 'start', 'ocrvox.service'], check=True,
                                   timeout=10, stdout=subprocess.DEVNULL)
                time.sleep(.1)
        else:
            raise ValueError('Reader did not become ready. Run setup to repair it.')
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


def readiness(language):
    app = DATA / 'app'
    current = True
    for source in (ROOT / 'reader').glob('*.py'):
        if source.name.startswith('test_'):
            continue
        try:
            if source.read_bytes() != (app / source.name).read_bytes():
                current = False
                break
        except OSError:
            current = False
            break
    return dict(backend_ready=runtime_ready() and current,
                missing_packages=missing_packages(language))


def request(payload):
    command = payload.get('command', 'status')
    if command not in COMMANDS:
        raise ValueError('Unknown command')
    setup = setup_state()
    if command == 'setup':
        language = payload.get('language', languages.default_language())
        if not languages.valid(language):
            raise ValueError('Choose a supported language')
        backend_only = payload.get('backend_only', False)
        if not isinstance(backend_only, bool):
            raise ValueError('Invalid setup option')
        engine = payload.get('engine')
        if engine not in (None, 'piper'):
            raise ValueError('Unsupported installer')
        if engine == 'piper' and language not in languages.PIPER:
            raise ValueError('Piper has no voice for this language; use Kokoro')
        ocr_language = payload.get('ocr_language')
        if ocr_language is not None and not languages.valid(ocr_language):
            raise ValueError('Choose a supported language')
        if not setup.get('busy'):
            DATA.mkdir(parents=True, exist_ok=True)
            with (DATA / 'setup.log').open('a') as log:
                args = [sys.executable, str(ROOT / 'setup_backend.py'), '--language', language]
                if backend_only:
                    args.append('--backend-only')
                if engine:
                    args.extend(['--engine', engine])
                if ocr_language:
                    args.extend(['--ocr-language', ocr_language])
                subprocess.Popen(args,
                                 stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
            return dict(setup_busy=True, setup_message='Starting setup…', enabled=False, settings={})
    elif command == 'cancel-setup':
        if setup.get('busy') and setup.get('phase') == 'packages':
            raise ValueError('Wait for the package transaction to finish before cancelling.')
        if setup.get('busy') and setup_pid(setup.get('pid')):
            os.kill(setup['pid'], signal.SIGTERM)
    elif command != 'status' and setup.get('busy'):
        raise ValueError('Wait for setup to finish before reading or changing settings.')
    endpoint = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'kindle-reader/control.sock'
    if setup.get('busy') or (command in ('status', 'cancel-setup', 'setup') and not endpoint.exists() and not runtime_ready()):
        try:
            config = json.loads((Path.home() / '.config/kindle-reader/settings.json').read_text())
        except (OSError, ValueError):
            config = {}
        response = dict(enabled=False, status='Ready to set up local reading', settings=config)
    else:
        try:
            response = socket_request(payload if command not in ('setup', 'cancel-setup') else {'command': 'status'})
        except (OSError, subprocess.SubprocessError) as error:
            if command != 'status':
                raise
            response = dict(enabled=False, status='Reader could not start. Run setup to repair it. ' + str(error), settings={})
    response.setdefault('settings', {}).setdefault('language', languages.default_language())
    response.setdefault('languages', languages.options())
    response.update(readiness(response['settings']['language']))
    setup = setup_state()
    response.update(setup_busy=setup.get('busy', False), setup_message=setup.get('message', ''),
                    setup_phase=setup.get('phase', 'idle'))
    return response


if __name__ == '__main__':
    os.umask(0o077)
    try:
        print(json.dumps(request(json.loads(sys.stdin.readline()))))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(json.dumps({'error': str(error)}))
