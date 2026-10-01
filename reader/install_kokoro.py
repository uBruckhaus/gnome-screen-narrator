"""Install only the selected Kokoro language model into the reader runtime."""
import argparse
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

STANDARD = 'https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/'
GERMAN = 'https://huggingface.co/Godelaune/Kokoro-82M-ONNX-German-Martin/resolve/main/'
ASSETS = {
    'de': [('kokoro-martin.onnx', GERMAN, 'c302f1d8bc7adf40a842cb550e18c39a5026bdb1afdd29dbb700b501cb49276b'),
           ('voices-martin.npz', GERMAN, '5b9c8553398d7abf67498ce500c186cefaa7b68fed3e3d415da5380670105acd')],
    'en': [('kokoro-v1.0.onnx', STANDARD, 'beb0d1848dee9a49da392cc3df26958d46cfa35d321edf434f52949153f0df3a'),
           ('voices-v1.0.bin', STANDARD, 'bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d')]
}


def valid_asset(path, expected):
    try:
        with Path(path).open('rb') as data:
            return hashlib.file_digest(data, 'sha256').hexdigest() == expected
    except OSError:
        return False


def download_asset(name, base, digest, folder, report):
    target = folder / name
    if valid_asset(target, digest):
        report(f'{name}: already installed')
        return
    fd, temporary = tempfile.mkstemp(prefix='.kokoro-download-', dir=folder)
    try:
        with os.fdopen(fd, 'wb') as out, urllib.request.urlopen(base + name, timeout=60) as response:
            total = int(response.headers.get('Content-Length', 0))
            received, last_percent = 0, -1
            while chunk := response.read(1024 * 1024):
                out.write(chunk)
                received += len(chunk)
                percent = int(received * 100 / total) if total else 0
                if percent != last_percent:
                    report(f'Downloading {name}: {percent}%' if total else f'Downloading {name}: {received // (1024 * 1024)} MB')
                    last_percent = percent
        if not valid_asset(temporary, digest):
            raise ValueError(f'{name}: checksum verification failed')
        os.replace(temporary, target)
    finally:
        Path(temporary).unlink(missing_ok=True)


def install(language, progress=None, check_only=False):
    if language not in ASSETS:
        raise ValueError('Choose German or English / multilingual')
    folder = Path.home() / '.local/share/kindle-reader/kokoro'
    def report(message):
        print(message, flush=True)
        if progress:
            path = Path(progress)
            temp = path.with_suffix('.tmp')
            temp.write_text(json.dumps({'message': message}))
            temp.replace(path)
    dependencies = all(importlib.util.find_spec(name) for name in ('kokoro_onnx', 'soundfile', 'onnxruntime'))
    if check_only:
        return dependencies and all(valid_asset(folder / name, digest) for name, _, digest in ASSETS[language])
    folder.mkdir(parents=True, exist_ok=True)
    if not dependencies:
        report('Installing Kokoro runtime dependencies…')
        subprocess.run([sys.executable, '-m', 'pip', 'install', 'kokoro-onnx==0.4.7', 'soundfile==0.14.0'],
                       check=True, timeout=900)
    for asset in ASSETS[language]:
        download_asset(*asset, folder, report)
    launcher = Path.home() / '.local/bin/kindle-kokoro-tts'
    if not launcher.exists():
        launcher.parent.mkdir(parents=True, exist_ok=True)
        source = Path(__file__).with_name('kokoro_tts.py').read_text().split('\n', 1)[1]
        launcher.write_text('#!' + sys.executable + '\n' + source)
        launcher.chmod(0o755)
    report('Kokoro installed. Select a voice to start reading.')
    return True


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--language', choices=ASSETS, required=True)
    parser.add_argument('--progress')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    try:
        sys.exit(0 if install(args.language, args.progress, args.check) else 1)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f'Kokoro installation failed: {error}', file=sys.stderr)
        sys.exit(1)
