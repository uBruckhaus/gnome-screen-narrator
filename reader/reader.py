#!/usr/bin/env python3
"""Local, active-window OCR narration with a StatusNotifier tray icon."""
import difflib
import importlib.util
import json
import os
import re
import shlex
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path
from highlighting import HighlightOverlay, chunk_rectangles, visible_ocr
from settings_ui import build_settings_layout, section_heading
from online_provider import endpoint_url, saved_token, store_token

from PySide6.QtCore import QObject, QProcess, QTimer, Qt, QLockFile
from PySide6.QtGui import QActionGroup, QColor, QIcon, QPainter, QPen, QPixmap
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from PySide6.QtWidgets import (QApplication, QSystemTrayIcon, QMenu, QDialog,
    QFormLayout, QHBoxLayout, QPushButton, QComboBox, QDoubleSpinBox, QCheckBox, QDialogButtonBox, QLabel)

HOME = Path.home()
DATA = HOME / '.local/share/kindle-reader'
CONFIG = HOME / '.config/kindle-reader/settings.json'
RUNTIME = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')) / 'kindle-reader'
QWEN_MODEL_DIR = Path(os.environ.get('QWEN_TTS_MODEL_DIR', DATA / 'models/Qwen3-TTS-1.7B'))
VOICES = {
    'kokoro-martin': ('Martin · male · Kokoro', 'kokoro', 'martin'),
    'kokoro-heart': ('Heart · female · Kokoro', 'kokoro', 'af_heart'),
    'kokoro-nicole': ('Nicole · female · Kokoro', 'kokoro', 'af_nicole'),
    'kokoro-adam': ('Adam · male · Kokoro', 'kokoro', 'am_adam'),
    'kerstin-fast': ('Kerstin · female · fast', 'piper', 'de_DE-kerstin-low.onnx'),
    'thorsten-fast': ('Thorsten · male · fast', 'piper', 'de_DE-thorsten-high.onnx'),
    'lessac-fast': ('Lessac · English · Piper Fast', 'piper', 'en_US-lessac-high.onnx'),
    'qwen-kerstin': ('Kerstin · female · Qwen 1.7B', 'qwen', 'kerstin-reference.wav'),
    'qwen-thorsten': ('Thorsten · male · Qwen 1.7B', 'qwen', 'thorsten-reference.wav'),
}
DEFAULTS = dict(voice='kokoro-martin', speed=1.0, language='de', follow=True, kindle_crop=True, auto_page_turn=True, kindle_area=None, highlight=True, provider='Local', online_endpoint='https://api.openai.com/v1', online_model='', online_voice='alloy', remember_token=False)


def voice_is_available(key):
    """Offer only voices with their own usable engine and required assets."""
    entry = VOICES.get(key)
    if not entry:
        return False
    _, engine, reference = entry
    def executable(path):
        return Path(path).is_file() and os.access(path, os.X_OK)
    def present(path):
        try:
            return Path(path).is_file() and Path(path).stat().st_size > 0
        except OSError:
            return False
    if engine == 'kokoro':
        if not executable(HOME / '.local/bin/kindle-kokoro-tts'):
            return False
        if not all(importlib.util.find_spec(name) is not None for name in ('kokoro_onnx', 'soundfile', 'onnxruntime')):
            return False
        files = ('kokoro-martin.onnx', 'voices-martin.npz') if reference == 'martin' else ('kokoro-v1.0.onnx', 'voices-v1.0.bin')
        return all(present(DATA / 'kokoro' / name) for name in files)
    if engine == 'piper':
        return executable(DATA / 'venv/bin/piper') and all(present(DATA / 'voices' / name) for name in (reference, reference + '.json'))
    if engine == 'qwen':
        runner = HOME / '.local/bin/llama-tts'
        if not executable(runner):
            return False
        models = ('Qwen3-TTS-12Hz-1.7B-Base-Q8_0.gguf', 'mmproj-Qwen3-TTS-12Hz-1.7B-Base-bf16.gguf')
        return all(present(QWEN_MODEL_DIR / name) for name in models) and present(DATA / 'voices' / reference)
    return False


def available_voices(language=None):
    def matches(value):
        _, engine, reference = value
        if not language or engine == 'qwen':
            return True
        if engine == 'kokoro':
            return (reference == 'martin') == (language == 'de')
        return reference.startswith(language + '_')
    return {key: value for key, value in VOICES.items() if voice_is_available(key) and matches(value)}


def clean_text(text):
    # Keep words and punctuation; fix hyphenated line wrapping.
    text = text.replace('\x0c', '').replace('\u00ad', '')
    # Rejoin hyphenated line wraps (e.g. 'Raum-\nschiffs' -> 'Raumschiffs')
    text = re.sub(r'(\b\w+)-\s*\n\s*(\w+\b)', r'\1\2', text)
    paragraphs = re.split(r'\n\s*\n', text.strip())
    cleaned_paras = []
    for p in paragraphs:
        lines = p.splitlines()
        filtered = []
        for line in lines:
            line_str = line.strip()
            # Ignore Kindle footer progress bar and pure symbol/divider lines
            if re.match(r'^Position \d+ von \d+', line_str):
                continue
            if re.match(r'^[—\s\-=_.*#~]+$', line_str) and len(line_str) > 2:
                continue
            filtered.append(line_str)
        if filtered:
            cleaned_paras.append(' '.join(' '.join(filtered).split()))
    return '\n\n'.join(p for p in cleaned_paras if p.strip())


def split_sentences(paragraph):
    pattern = r'([.!?]+[»"\'”’«]?)\s+(?=[A-ZÄÖÜ»„"\'“0-9])'
    parts = re.split(pattern, paragraph)
    sentences = []
    i = 0
    while i < len(parts):
        s = parts[i]
        if i + 1 < len(parts):
            punct = parts[i + 1]
            sentences.append((s + punct).strip())
            i += 2
        else:
            if s.strip():
                sentences.append(s.strip())
            i += 1
    return [s for s in sentences if s]


def split_clause(sentence, limit):
    if len(sentence) <= limit:
        return [sentence]
    clauses = re.split(r'(?<=[,;:\—])\s+', sentence)
    if len(clauses) <= 1:
        words = sentence.split()
        res = []
        cur = ''
        for w in words:
            if cur and len(cur) + len(w) + 1 > limit:
                res.append(cur)
                cur = w
            elif cur:
                cur += ' ' + w
            else:
                cur = w
        if cur:
            res.append(cur)
        return res
    res = []
    cur = ''
    for c in clauses:
        if cur and len(cur) + len(c) + 1 > limit:
            res.append(cur)
            cur = c
        elif cur:
            cur += ' ' + c
        else:
            cur = c
    if cur:
        res.append(cur)
    return res


def chunks(text, limit=250):
    """Whole-sentence chunks keep speech completely natural and avoid model token limits."""
    result = []
    for paragraph in text.split('\n\n'):
        sentences = split_sentences(paragraph)
        current = ''
        for sentence in sentences:
            sentence = sentence.strip()
            if not sentence:
                continue
            if len(sentence) > limit:
                if current:
                    result.append(current)
                    current = ''
                for sub in split_clause(sentence, limit):
                    result.append(sub)
                continue
            if current and len(current) + len(sentence) + 1 > limit:
                result.append(current)
                current = sentence
            elif current:
                current = current + ' ' + sentence
            else:
                current = sentence
        if current:
            result.append(current)
    return [chunk for chunk in result if any(c.isalnum() for c in chunk)]


def same_text(a, b, threshold=0.90):
    a, b = ' '.join(a.split()), ' '.join(b.split())
    if a == b:
        return True
    if not a or not b:
        return False
    return bool(difflib.SequenceMatcher(None, a, b, autojunk=False).ratio() >= threshold)


def make_icon(state):
    """Render a crisp, high-contrast StatusNotifier icon for off, on, and paused states."""
    pix = QPixmap(64, 64)
    pix.fill(Qt.GlobalColor.transparent)
    painter = QPainter(pix)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)

    if state == 'on':
        color = QColor('#a6e3a1')  # Green
    elif state == 'paused':
        color = QColor('#f9e2af')  # Amber yellow
    else:
        color = QColor('#cdd6f4')  # Light lavender/white

    # Open book outline
    painter.setPen(QPen(color, 5, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin))
    painter.drawRoundedRect(8, 13, 48, 38, 5, 5)
    painter.drawLine(32, 15, 32, 49)

    # Book lines
    painter.setPen(QPen(color, 3, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap))
    painter.drawLine(16, 24, 25, 24)
    painter.drawLine(39, 24, 48, 24)
    painter.drawLine(16, 33, 25, 33)
    painter.drawLine(39, 33, 48, 33)

    if state == 'on':
        painter.setBrush(color)
        painter.setPen(Qt.PenStyle.NoPen)
        painter.drawEllipse(45, 43, 14, 14)
    elif state == 'paused':
        painter.setBrush(color)
        painter.setPen(Qt.PenStyle.NoPen)
        painter.drawRect(45, 43, 4, 13)
        painter.drawRect(52, 43, 4, 13)

    painter.end()
    return QIcon(pix)


class Task(QObject):
    """One cancellable subprocess. A killed process never invokes its callback."""
    def __init__(self, owner, args, done, timeout=180, stdin_data=None, close_stdin=False):
        super().__init__(owner)
        self.owner, self.done, self.cancelled = owner, done, False
        if close_stdin:
            # QProcess hands every child a pipe on stdin. slurp treats a piped stdin as
            # "restrict boxes from stdin" mode: it blocks reading stdin and never grabs
            # the pointer. Redirect stdin from /dev/null (QProcess cannot attach a file
            # to stdin) to force interactive mode. `exec` keeps the PID stable so
            # Task.cancel()/expire() still kill the real process directly.
            script = 'exec ' + ' '.join(shlex.quote(str(a)) for a in args) + ' </dev/null'
            args = ['sh', '-c', script]
        self.proc = QProcess(self)
        self.proc.setProgram(str(args[0]))
        self.proc.setArguments([str(a) for a in args[1:]])
        self.proc.finished.connect(self.finish)
        self.proc.errorOccurred.connect(self.error)
        self.timer = QTimer(self)
        self.timer.setSingleShot(True)
        self.timer.timeout.connect(self.expire)
        owner.tasks.add(self)
        self.proc.start()
        if stdin_data is not None:
            data = stdin_data.encode('utf-8') if isinstance(stdin_data, str) else stdin_data
            self.proc.write(data)
            self.proc.closeWriteChannel()
        self.timer.start(timeout * 1000)

    def error(self, error):
        if error == QProcess.ProcessError.FailedToStart:
            self.finish(-1)

    def expire(self):
        self.proc.kill()

    def finish(self, code, *_):
        if self not in self.owner.tasks:
            return
        self.timer.stop()
        self.owner.tasks.discard(self)
        out = bytes(self.proc.readAllStandardOutput()).decode(errors='replace')
        err = bytes(self.proc.readAllStandardError()).decode(errors='replace')
        if not self.cancelled:
            try:
                self.done(code, out, err)
            except Exception as e:
                print(f'Task callback error: {e}', file=sys.stderr, flush=True)
        self.deleteLater()

    def cancel(self):
        self.cancelled = True
        self.proc.kill()
        self.proc.waitForFinished(1000)


class Reader(QObject):
    def __init__(self, app):
        super().__init__()
        self.app = app
        self.tasks = set()
        self.speech_tasks = set()
        self.settings = DEFAULTS.copy()
        try:
            saved = json.loads(CONFIG.read_text())
            self.settings.update({k: saved[k] for k in DEFAULTS if k in saved})
        except (OSError, ValueError, TypeError):
            pass
        if not voice_is_available(self.settings['voice']):
            self.settings['voice'] = next((key for key, value in available_voices().items() if value[1] == 'kokoro'), DEFAULTS['voice'])
        if self.settings['language'] not in ('de', 'en'):
            self.settings['language'] = 'de'
        try:
            self.settings['speed'] = min(2., max(.6, float(self.settings['speed'])))
        except (TypeError, ValueError):
            self.settings['speed'] = 1.
        self.online_token = saved_token(CONFIG.with_name('speech-credentials.json'), self.settings['online_endpoint']) if self.settings.get('remember_token') else ''
        self.online_models = []
        self.provider_status = ''
        self.models_loading = False
        self.installing_kokoro = False
        self.install_task = None
        self.enabled = self.paused = self.scanning = False
        self.status = 'Off'
        self.target = ''
        self.target_title = ''
        self.target_class = ''
        self.last_text = self.candidate = ''
        self.last_error = ''
        self.queue = []
        self.epoch = 0
        self.custom_area = None
        self.overlay = HighlightOverlay(self, RUNTIME)
        self.highlight_queue = []
        self.audio_highlights = {}
        self.capture_area = None
        self.capture_window_geometry = None

        # Pipelined playback state
        self.player = None           # mpv Task currently playing
        self.playing_file = None     # Path to file currently playing
        self.tts_task = None         # Task generating the next chunk
        self.ready_file = None       # Path to .wav file that finished generating and waits to play
        self.dialog = None

        # Pre-render static icons to prevent DBus/Quickshell churn
        self.icons = {
            'off': make_icon('off'),
            'on': make_icon('on'),
            'paused': make_icon('paused')
        }
        self.current_icon_state = None

        self.tray = QSystemTrayIcon(self)
        self.menu = QMenu()
        self.toggle_action = self.menu.addAction('Turn ON Simple Reader')
        self.toggle_action.setCheckable(True)
        self.toggle_action.triggered.connect(lambda: self.set_enabled(not self.enabled, notify=True))
        self.stop_action = self.menu.addAction('Turn OFF Simple Reader (Stop)', lambda: self.set_enabled(False, notify=True))
        self.status_action = self.menu.addAction('Off')
        self.status_action.setEnabled(False)
        self.menu.addSeparator()
        self.read_action = self.menu.addAction('Read active window again', self.read_again)
        self.pause_action = self.menu.addAction('Pause', self.pause)
        self.menu.addSeparator()
        self.select_area_action = self.menu.addAction('Select reading area…', self.select_area)
        self.clear_area_action = self.menu.addAction('Reset area (Full window)', self.clear_area)
        self.menu.addSeparator()
        self.voice_menu = self.menu.addMenu('Voice')
        self.voice_group = QActionGroup(self)
        self.voice_actions = {}
        for key, (name, *_rest) in available_voices(self.settings['language']).items():
            action = self.voice_menu.addAction(name)
            action.setCheckable(True)
            self.voice_group.addAction(action)
            action.triggered.connect(lambda checked=False, k=key: self.set_voice(k))
            self.voice_actions[key] = action
        self.speed_menu = self.menu.addMenu('Reading speed')
        self.speed_group = QActionGroup(self)
        self.speed_actions = {}
        for rate in (.75, .9, 1., 1.1, 1.25, 1.5, 1.75, 2.):
            action = self.speed_menu.addAction(f'{rate:g}×')
            action.setCheckable(True)
            self.speed_group.addAction(action)
            action.triggered.connect(lambda checked=False, r=rate: self.set_speed(r))
            self.speed_actions[rate] = action
        self.menu.addAction('Settings…', self.show_settings)
        self.menu.addSeparator()
        self.menu.addAction('Quit Simple Reader', self.app.quit)
        self.tray.setContextMenu(self.menu)
        self.tray.activated.connect(self.activated)

        self.timer = QTimer(self)
        self.timer.timeout.connect(self.scan)
        self.timer.setInterval(2000)

        self.server = QLocalServer(self)
        self.server.newConnection.connect(self.connection)
        self.clients = set()
        self.server.listen(str(RUNTIME / 'control.sock'))

        self.update()
        if os.environ.get("OCRVOX_BAR_WIDGET") != "1":
            self.tray.show()

    def is_speaking(self):
        return bool(self.player or self.tts_task or self.ready_file or self.queue)

    def activated(self, reason):
        if reason == QSystemTrayIcon.ActivationReason.Trigger:
            self.set_enabled(not self.enabled, notify=True)
        elif reason == QSystemTrayIcon.ActivationReason.MiddleClick:
            self.pause()

    def save(self):
        CONFIG.parent.mkdir(parents=True, exist_ok=True)
        temp = CONFIG.with_suffix('.tmp')
        temp.write_text(json.dumps(self.settings, indent=2) + '\n')
        temp.replace(CONFIG)

    def update(self, status=None):
        if status:
            self.status = status
        if hasattr(self, 'toggle_action'):
            self.toggle_action.setText('Turn OFF Simple Reader' if self.enabled else 'Turn ON Simple Reader')
            self.toggle_action.setChecked(self.enabled)
        if hasattr(self, 'stop_action'):
            self.stop_action.setEnabled(self.enabled)
        self.status_action.setText(self.status)
        self.pause_action.setText('Resume' if self.paused else 'Pause')
        self.pause_action.setEnabled(self.enabled)
        if self.settings['voice'] in self.voice_actions:
            self.voice_actions[self.settings['voice']].setChecked(True)
        for rate, action in self.speed_actions.items():
            action.setChecked(abs(rate - self.settings['speed']) < .01)

        if hasattr(self, 'clear_area_action'):
            has_area = (self.custom_area is not None) or bool(self.settings.get('kindle_area'))
            self.clear_area_action.setEnabled(has_area)

        # Only update the tray icon if the visual state changes
        state = 'paused' if self.paused else ('on' if self.enabled else 'off')
        if state != self.current_icon_state:
            self.current_icon_state = state
            self.tray.setIcon(self.icons[state])

        area_info = ''
        if self.settings.get('kindle_area'):
            rw, rh = self.settings['kindle_area'][2], self.settings['kindle_area'][3]
            area_info = f' [Kindle: {round(rw*100)}%×{round(rh*100)}%]'
        elif self.custom_area:
            area_info = f' [Area: {self.custom_area[2]}×{self.custom_area[3]}]'
        self.tray.setToolTip(f'Simple Reader — {self.status}{area_info}\n{VOICES[self.settings["voice"]][0]} · {self.settings["speed"]:g}×')

    def fail(self, message):
        print(message, file=sys.stderr, flush=True)
        self.update('Error — open tray to retry')
        if message != self.last_error:
            # Qt tray messages set NeedsAttention and a themed attention icon.
            # The desktop shell crashed loading that icon after a Piper error.
            subprocess.Popen(['notify-send', '-a', 'Simple Reader', 'Simple Reader', message[:350]],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.last_error = message

    def stop_speech(self):
        self.models_loading = False
        self.installing_kokoro = False
        self.epoch += 1
        self.overlay.show([])
        self.highlight_queue = []
        self.audio_highlights = {}
        self.mpv_command(['quit'])
        for task in list(self.speech_tasks):
            if task in self.tasks:
                task.cancel()
        self.speech_tasks.clear()
        for task in list(self.tasks):
            task.cancel()
        # Cancelled OCR callbacks cannot clear this flag themselves.
        self.scanning = False
        try:
            subprocess.run(['pkill', '-9', '-u', str(os.getuid()), '-f', str(RUNTIME / 'mpv.sock')],
                           stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
        except Exception:
            pass
        self.player = None
        self.playing_file = None
        self.tts_task = None
        self.ready_file = None
        self.queue = []

    def set_enabled(self, enabled, notify=False):
        self.provider_status = ""
        if enabled and self.installing_kokoro:
            raise ValueError("Wait for Kokoro installation or cancel it before reading")
        if enabled and self.settings.get('provider', 'Local') == 'Online':
            endpoint_url(self.settings['online_endpoint'])
            if not self.settings.get('online_model') or not self.settings.get('online_voice'):
                raise ValueError('Choose an online speech model and voice')
        if enabled and self.settings.get('provider', 'Local') == 'Local' and not voice_is_available(self.settings['voice']):
            raise ValueError('Selected voice is unavailable. Install its runtime and required models.')
        was = self.enabled
        self.enabled = bool(enabled)
        self.paused = False
        self.stop_speech()
        for task in list(self.tasks):
            task.cancel()
        self.scanning = False
        self.target = self.last_text = self.candidate = ''
        self.update('Looking for text…' if self.enabled else 'Off')
        if notify or was != self.enabled:
            msg = 'Simple Reader: ON' if self.enabled else 'Simple Reader: OFF'
            subprocess.Popen(['notify-send', '-a', 'Simple Reader', '-i', 'audio-headphones', '-t', '1500', msg],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if self.enabled:
            self.timer.start()
            QTimer.singleShot(350, self.scan)
        else:
            self.timer.stop()
            self.overlay.close()
            for name in ('window.png', 'ocr.png', 'ocr.txt', 'ocr.tsv', 'speech_0.txt', 'speech_0.wav', 'speech_1.txt', 'speech_1.wav'):
                (RUNTIME / name).unlink(missing_ok=True)

    def read_again(self):
        if not self.enabled:
            self.set_enabled(True, notify=True)
        else:
            self.stop_speech()
            self.paused = False
            self.last_text = self.candidate = ''
            self.update('Looking for text…')
            self.scan()

    def mpv_command(self, command):
        try:
            with socket.socket(socket.AF_UNIX) as client:
                client.settimeout(.2)
                client.connect(str(RUNTIME / 'mpv.sock'))
                client.sendall((json.dumps({'command': command}) + '\n').encode())
        except OSError:
            pass

    def pause(self):
        if not self.enabled:
            return
        self.paused = not self.paused
        self.mpv_command(['set_property', 'pause', self.paused])
        self.update('Paused' if self.paused else 'Reading')
        if not self.paused:
            self.pump_pipeline()

    def set_voice(self, key):
        if not voice_is_available(key):
            raise ValueError('Voice runtime or required model is not installed')
        self.settings['voice'] = key
        self.save()
        self.update()
        if self.enabled:
            self.read_again()

    def set_speed(self, speed):
        self.settings['speed'] = max(.6, min(2., float(speed)))
        self.save()
        self.mpv_command(['set_property', 'speed', self.settings['speed']])
        self.update()

    def select_area(self):
        self.stop_speech()
        self.update('Select reading area with mouse…')
        subprocess.Popen(['notify-send', '-a', 'Simple Reader', '-i', 'edit-select-all', '-t', '4000',
                          'Simple Reader', 'Drag a box around the reading area with your mouse (Esc to cancel)'],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        slurp_args = ['slurp', '-d', '-b', '#00000050', '-c', '#a6e3a1', '-s', '#a6e3a125', '-w', '2']
        # 150ms delay lets any active Qt popup menu unmap from Wayland so pointer grab succeeds cleanly
        # close_stdin: a piped stdin puts slurp into "boxes from stdin" mode and it never grabs the pointer
        QTimer.singleShot(150, lambda: Task(self, slurp_args, self.area_selected, timeout=60, close_stdin=True))

    def area_selected(self, code, out, err):
        if code or not out.strip():
            self.update('Looking for text…' if self.enabled else 'Off')
            subprocess.Popen(['notify-send', '-a', 'Simple Reader', '-i', 'dialog-information', '-t', '2000',
                              'Simple Reader', 'Area selection cancelled'],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return
        match = re.match(r'^(\d+),(\d+)\s+(\d+)x(\d+)$', out.strip())
        if not match:
            self.update('Looking for text…' if self.enabled else 'Off')
            return
        x, y, w, h = map(int, match.groups())
        if w < 20 or h < 20:
            self.update('Looking for text…' if self.enabled else 'Off')
            subprocess.Popen(['notify-send', '-a', 'Simple Reader', '-i', 'dialog-warning', '-t', '2500',
                              'Simple Reader', 'Selected area was too small. Drag a box over the text to read.'],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return

        # Always save the exact selected box for active reading across any application/browser!
        self.custom_area = (x, y, w, h)

        # In addition, check if this area was selected on the Kindle PWA to memorize relative proportions
        Task(self, ['hyprctl', 'clients', '-j'], lambda c, o, e: self.apply_selected_area(x, y, w, h, o))

    def apply_selected_area(self, x, y, w, h, clients_json):
        cx = x + w / 2
        cy = y + h / 2
        kindle_win = None
        try:
            clients = json.loads(clients_json)
            for win in clients:
                cls = win.get('class', '').lower()
                title = win.get('title', '').lower()
                if 'kindle' in (title + cls) or 'klmgdcdnnefbfkpmkcmocagbihobefnh' in cls:
                    wx, wy = win['at']
                    ww, wh = win['size']
                    if wx <= cx < wx + ww and wy <= cy < wy + wh:
                        kindle_win = win
                        break
            if not kindle_win and self.is_kindle_target():
                for win in clients:
                    if win.get('address') == self.target:
                        kindle_win = win
                        break
        except Exception:
            pass

        if kindle_win:
            wx, wy = kindle_win['at']
            ww, wh = kindle_win['size']
            # Window-relative proportions (0.0 to 1.0)
            rx = max(0.0, (x - wx) / ww)
            ry = max(0.0, (y - wy) / wh)
            rw = min(1.0 - rx, w / ww)
            rh = min(1.0 - ry, h / wh)
            self.settings['kindle_area'] = [round(rx, 4), round(ry, 4), round(rw, 4), round(rh, 4)]
            self.save()
            msg = f'Reading area set & memorized for Kindle ({round(rw*100)}% × {round(rh*100)}%)'
        else:
            msg = f'Reading area set: {w}×{h} px'

        subprocess.Popen(['notify-send', '-a', 'Simple Reader', '-i', 'edit-select-all', '-t', '2000',
                          'Simple Reader', msg],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.update()
        if not self.enabled:
            self.set_enabled(True, notify=True)
        else:
            self.read_again()

    def clear_area(self):
        had_area = (self.custom_area is not None) or bool(self.settings.get('kindle_area'))
        self.custom_area = None
        if self.settings.get('kindle_area'):
            self.settings['kindle_area'] = None
            self.save()
        if had_area:
            subprocess.Popen(['notify-send', '-a', 'Simple Reader', '-i', 'view-fullscreen', '-t', '1500',
                              'Simple Reader', 'Reading area reset to default'],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.update()
            if self.enabled:
                self.read_again()

    def is_kindle_target(self):
        title = (self.target_title or '').lower()
        cls = (self.target_class or '').lower()
        return 'kindle' in (title + cls) or 'klmgdcdnnefbfkpmkcmocagbihobefnh' in cls

    def scan(self):
        if not self.enabled or self.paused or self.scanning or self.menu.isVisible() or (self.dialog and self.dialog.isVisible()):
            return
        if not self.settings['follow'] and self.last_text:
            return
        # Keep checking visible text during playback: manual page turns do not
        # change the window address, but invalidate queued and generated audio.
        self.scanning = True
        Task(self, ['hyprctl', 'activewindow', '-j'], self.got_window, timeout=5)

    def check_window_focus(self, code, out, err):
        if code:
            return
        try:
            window = json.loads(out)
            address = window.get('address', '')
            geometry = (window.get('at'), window.get('size'))
            if address == self.target and geometry != self.capture_window_geometry:
                # Existing focus poll also detects moves/resizes: old boxes are invalid.
                self.overlay.show([])
                self.audio_highlights.clear()
                self.highlight_queue = [[] for _ in self.queue]
            if address and address != self.target:
                # User switched windows! Stop speech.
                self.stop_speech()
                self.target = address
                self.last_text = self.candidate = ''
                self.update('Looking for text…')
                self.scan()
        except Exception:
            pass

    def got_window(self, code, out, err):
        if code:
            self.scanning = False
            self.fail('Cannot access the active window: ' + err)
            return
        try:
            window = json.loads(out)
            address = window.get('address', '')
            if not address or window.get('pid') == os.getpid():
                self.scanning = False
                return
            x, y = window['at']
            width, height = window['size']
            if width < 60 or height < 60:
                self.scanning = False
                return
        except (ValueError, KeyError, TypeError):
            self.scanning = False
            return

        self.target_title = window.get('title', '')
        self.target_class = window.get('class', '')
        self.capture_window_geometry = (window['at'], window['size'])

        if self.target != address:
            # Switched window focus
            self.stop_speech()
            self.target = address
            self.last_text = self.candidate = ''
            self.update('Looking for text…')

        if self.custom_area:
            cx, cy, cw, ch = self.custom_area
            geom = f'{cx},{cy} {cw}x{ch}'
        else:
            is_kindle = self.is_kindle_target()
            if is_kindle and self.settings.get('kindle_area'):
                rx, ry, rw, rh = self.settings['kindle_area']
                cx = round(x + rx * width)
                cy = round(y + ry * height)
                cw = round(rw * width)
                ch = round(rh * height)
                # Kindle's first baseline can sit above a memorized crop after
                # toolbar/layout changes. Include a line of headroom so the
                # clipped-glyph filter does not discard the first book line.
                headroom = min(32, max(0, cy - y))
                cy -= headroom
                ch += headroom
                geom = f'{cx},{cy} {cw}x{ch}'
            elif is_kindle and self.settings['kindle_crop']:
                # Safe crop: only trim narrow top toolbar and bottom progress bar, preserving all text
                x += round(width * .04)
                y += round(height * .045)
                width = round(width * .92)
                height = round(height * .895)
            else:
                y += 32
                height -= 32
            if not (is_kindle and self.settings.get('kindle_area')):
                geom = f'{x},{y} {width}x{height}'
        self.capture_area = tuple(map(int, re.findall(r'-?\d+', geom)))
        self.scanning = True
        self.capture_highlight = (self.epoch, self.playing_file, self.overlay.last_payload)
        self.overlay.show([])
        Task(self, ['grim', '-g', geom, RUNTIME / 'window.png'], self.captured, timeout=5)

    def captured(self, code, out, err):
        epoch, playing_file, payload = self.capture_highlight
        if payload and epoch == self.epoch and playing_file == self.playing_file:
            highlight = json.loads(payload)
            self.overlay.show(highlight['rectangles'], highlight['target'])
        if code:
            self.scanning = False
            self.fail('Screen capture failed: ' + err)
            return
        Task(self, ['magick', RUNTIME / 'window.png', '-colorspace', 'Gray', '-normalize', RUNTIME / 'ocr.png'], self.prepared, timeout=5)

    def prepared(self, code, out, err):
        if code:
            self.scanning = False
            self.fail('Could not prepare screen text: ' + err)
            return
        args = ['tesseract', RUNTIME / 'ocr.png', RUNTIME / 'ocr', '--psm', '6']
        if self.settings['language'] == 'de':
            args += ['--tessdata-dir', DATA / 'tessdata', '-l', 'deu']
        else:
            args += ['-l', 'eng']
        # Speech and highlights share the same words from one recognition pass.
        args += ['-c', 'tessedit_create_txt=1']
        args += ['-c', 'tessedit_create_tsv=1']
        Task(self, args, self.recognized, timeout=15)

    def recognized(self, code, out, err):
        self.scanning = False
        if code:
            self.fail('OCR failed: ' + err)
            return
        try:
            raw, aligned_tsv = visible_ocr((RUNTIME / 'ocr.tsv').read_text())
            text = clean_text(raw)
        except (OSError, ValueError, KeyError, StopIteration) as error:
            self.fail('Could not read OCR output: ' + str(error))
            return
        if len(re.findall(r'\w', text)) < 12:
            if not self.is_speaking():
                self.update('Waiting for readable text')
            return

        # Idle or waiting for next page
        if same_text(text, self.last_text, threshold=0.90):
            self.candidate = ''
            return
        if not same_text(text, self.candidate, threshold=0.90):
            if self.is_speaking():
                # Stop stale speech as soon as a changed page is observed, then
                # require a second stable capture before reading the new page.
                self.stop_speech()
                self.update('Waiting for the page to settle…')
            self.candidate = text
            QTimer.singleShot(400, self.scan)
            return
        self.last_text = text
        self.candidate = ''
        self.stop_speech()
        self.queue = chunks(text)
        self.highlight_queue = [[] for _ in self.queue]
        if self.settings['highlight'] and self.capture_area:
            try:
                self.highlight_queue = chunk_rectangles(
                    aligned_tsv, self.queue, self.capture_area)
            except OSError:
                pass
        self.last_error = ''
        self.pump_pipeline()

    def speech_task(self, args, done, timeout=180, stdin_data=None):
        epoch = self.epoch
        def finished(code, out, err):
            self.speech_tasks.discard(task)
            if self.enabled and self.epoch == epoch:
                done(code, out, err)
        task = Task(self, args, finished, timeout, stdin_data=stdin_data)
        self.speech_tasks.add(task)
        return task

    def pump_pipeline(self):
        """Zero-gap audio pipeline: plays ready chunk and pre-generates next chunk concurrently."""
        if not self.enabled or self.paused:
            return

        # 1. Play ready chunk if player is idle
        if self.player is None:
            if self.ready_file and self.ready_file.exists():
                next_file = self.ready_file
                self.ready_file = None
                self.start_player(next_file)
            elif self.tts_task is None and self.queue:
                # First chunk of the page
                self.start_tts()
            elif not self.queue and self.tts_task is None and self.ready_file is None:
                # Page complete
                self.on_page_finished()
                return

        # 2. Pre-generate next chunk in parallel while playing
        if self.tts_task is None and self.ready_file is None and self.queue:
            self.start_tts()

    def start_tts(self):
        if not self.queue or not self.enabled or self.paused:
            return
        text = self.queue.pop(0)
        slot = '1' if self.playing_file == (RUNTIME / 'speech_0.wav') else '0'
        wav_file = RUNTIME / f'speech_{slot}.wav'
        self.audio_highlights[wav_file] = self.highlight_queue.pop(0) if self.highlight_queue else []
        txt_file = RUNTIME / f'speech_{slot}.txt'
        txt_file.write_text(text)

        _, engine, reference = VOICES[self.settings['voice']]
        online_payload = None
        if self.settings.get('provider', 'Local') == 'Online':
            args = [sys.executable, Path(__file__).with_name('online_provider.py')]
            online_payload = json.dumps({'settings': self.settings, 'token': self.online_token, 'input': str(txt_file), 'output': str(wav_file)})
        elif engine == 'kokoro':
            args = [HOME / '.local/bin/kindle-kokoro-tts',
                    '-m', reference,
                    '-i', txt_file, '-o', wav_file,
                    '-s', '1.0',  # Playback applies speed once, consistently across engines.
                    '-l', self.settings['language']]
        elif engine == 'qwen':
            args = [HOME / '.local/bin/llama-tts',
                    '-m', QWEN_MODEL_DIR / 'Qwen3-TTS-12Hz-1.7B-Base-Q8_0.gguf',
                    '-mm', QWEN_MODEL_DIR / 'mmproj-Qwen3-TTS-12Hz-1.7B-Base-bf16.gguf',
                    '--tts-lang', self.settings['language'],
                    '--tts-speaker-file', DATA / 'voices' / reference,
                    '-ngl', '99', '-c', '4096', '-n', '1536', '-t', '8', '--seed', '42',
                    '-f', txt_file, '-o', wav_file]
        else:
            args = [DATA / 'venv/bin/piper', '-m', DATA / 'voices' / reference,
                    '-i', txt_file, '-f', wav_file]

        if self.player is None:
            self.update('Preparing voice…')

        epoch = self.epoch
        def on_done(code, out, err):
            self.tts_task = None
            if not self.enabled or self.epoch != epoch:
                return
            if code:
                self.queue.clear()
                self.fail('Voice generation failed. Select Read active window again to retry.\n' + err[-500:])
                return
            self.ready_file = wav_file
            self.pump_pipeline()

        self.tts_task = self.speech_task(args, on_done, stdin_data=online_payload)

    def start_player(self, wav_file):
        self.playing_file = wav_file
        args = ['mpv', '--no-video', '--no-terminal', '--audio-pitch-correction=yes',
                f'--speed={self.settings["speed"]}', f'--input-ipc-server={RUNTIME / "mpv.sock"}',
                '--pause=yes' if self.paused else '--pause=no', str(wav_file)]
        self.update('Paused' if self.paused else 'Reading')

        epoch = self.epoch
        def on_done(code, out, err):
            self.overlay.show([])
            self.player = None
            self.playing_file = None
            if not self.enabled or self.epoch != epoch:
                return
            if code:
                self.queue.clear()
                self.fail('Audio playback failed: ' + err[-300:])
            else:
                self.pump_pipeline()

        self.player = self.speech_task(args, on_done, timeout=600)
        self.overlay.show(self.audio_highlights.pop(wav_file, []) if self.settings['highlight'] else [], self.target)
        # While player is playing, trigger lookahead pre-generation of the next chunk
        self.pump_pipeline()

    def on_page_finished(self):
        if self.settings.get('auto_page_turn', True) and self.is_kindle_target():
            self.update('Turning to next page…')
            epoch = self.epoch
            QTimer.singleShot(400, lambda: self.do_page_turn() if self.epoch == epoch else None)
        else:
            self.update('On — waiting for a new page')

    def do_page_turn(self):
        if not self.enabled or self.paused:
            return
        # Send Right arrow key to advance Kindle page
        Task(self, ['wtype', '-k', 'Right'], self.page_turn_sent, timeout=3)

    def page_turn_sent(self, code, out, err):
        if not self.enabled or self.paused:
            return
        if code:
            self.fail('Could not turn the Kindle page: ' + err)
            return
        # Wait 800ms for Kindle's page transition animation to settle, then scan
        QTimer.singleShot(800, self.scan)

    def show_settings(self):
        if os.environ.get("OCRVOX_BAR_WIDGET") == "1":
            subprocess.Popen(['omarchy-shell', 'shell', 'toggle', 'ubruckhaus.simple-reader', '{}'],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return
        if self.dialog and self.dialog.isVisible():
            self.dialog.raise_()
            return
        self.dialog = QDialog()
        self.dialog.setWindowTitle('Simple Reader settings')
        form = build_settings_layout(self.dialog)
        form.addRow(section_heading("Voice & Language"))
        voice = QComboBox()
        for key, (name, *_rest) in available_voices(self.settings['language']).items():
            voice.addItem(name, key)
        voice.setCurrentIndex(voice.findData(self.settings['voice']))
        form.addRow('Voice', voice)
        language = QComboBox()
        language.addItem('German', 'de')
        language.addItem('English', 'en')
        language.setCurrentIndex(language.findData(self.settings['language']))
        form.addRow('Text language', language)
        speed = QDoubleSpinBox()
        speed.setRange(.6, 2.)
        speed.setSingleStep(.05)
        speed.setSuffix('×')
        speed.setValue(self.settings['speed'])
        form.addRow('Reading speed', speed)
        form.addRow(section_heading("Reading & Kindle"))
        follow = QCheckBox('Follow active window and page changes')
        follow.setChecked(self.settings['follow'])
        form.addRow(follow)
        crop = QCheckBox('Skip Kindle toolbar, margins and progress bar')
        crop.setChecked(self.settings['kindle_crop'])
        form.addRow(crop)
        auto_page = QCheckBox('Turn Kindle pages after reading')
        auto_page.setChecked(self.settings.get('auto_page_turn', True))
        form.addRow(auto_page)
        highlight = QCheckBox('Highlight the passage being read')
        highlight.setChecked(self.settings['highlight'])
        form.addRow(highlight)
        form.addRow(section_heading("Reading Area"))
        area_layout = QHBoxLayout()
        if self.custom_area:
            area_text = f'Custom Area ({self.custom_area[2]}×{self.custom_area[3]} px)'
        elif self.settings.get('kindle_area'):
            rw, rh = self.settings['kindle_area'][2], self.settings['kindle_area'][3]
            area_text = f'Kindle PWA ({round(rw*100)}% × {round(rh*100)}%)'
        else:
            area_text = 'Full active window'
        area_label = QLabel(area_text)
        area_label.setWordWrap(True)
        btn_select = QPushButton('Select area…')
        btn_reset = QPushButton('Reset')
        has_area = (self.custom_area is not None) or bool(self.settings.get('kindle_area'))
        btn_reset.setEnabled(has_area)
        area_layout.addWidget(area_label, 1)
        area_layout.addWidget(btn_select)
        area_layout.addWidget(btn_reset)
        form.addRow('Reading area', area_layout)

        def do_select():
            self.dialog.close()
            QTimer.singleShot(300, self.select_area)

        def do_reset():
            self.clear_area()
            area_label.setText('Full active window')
            btn_reset.setEnabled(False)

        btn_select.clicked.connect(do_select)
        btn_reset.clicked.connect(do_reset)
        note = QLabel('Reads visible text continuously.\nVoice selection: Kokoro (neural) or Piper Fast (ONNX).\nOff stops speech.')
        note.setWordWrap(True)
        form.addRow(note)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Save | QDialogButtonBox.StandardButton.Cancel)
        form.addRow(buttons)
        def apply():
            selected_voice = voice.currentData()
            voice_changed = (selected_voice != self.settings['voice'])
            self.settings.update(
                voice=selected_voice,
                language=language.currentData(),
                follow=follow.isChecked(),
                kindle_crop=crop.isChecked(),
                auto_page_turn=auto_page.isChecked(),
                highlight=highlight.isChecked()
            )
            if not self.settings['highlight']:
                self.overlay.close()
            self.set_speed(speed.value())
            self.save()
            self.update()
            self.dialog.accept()
            if self.enabled and voice_changed:
                self.read_again()
        buttons.accepted.connect(apply)
        buttons.rejected.connect(self.dialog.reject)
        self.dialog.show()

    def configure_settings(self, values):
        if not isinstance(values, dict):
            raise ValueError('Settings must be an object')
        allowed = {'voice', 'language', 'speed', 'follow', 'kindle_crop', 'auto_page_turn', 'highlight', 'provider', 'online_endpoint', 'online_model', 'online_voice'}
        if set(values) - allowed:
            raise ValueError('Unknown setting')
        next_settings = self.settings.copy()
        for key, value in values.items():
            if key == 'provider' and value not in ('Local', 'Online'):
                raise ValueError('Unknown speech provider')
            if key == 'online_endpoint':
                value = endpoint_url(value)
            if key in {'online_model', 'online_voice'} and (not isinstance(value, str) or len(value) > 256):
                raise ValueError('Enter a valid model or voice ID')
            if key == 'voice' and (not isinstance(value, str) or not voice_is_available(value)):
                raise ValueError('Voice runtime or required model is not installed')
            if key == 'language' and value not in ('de', 'en'):
                raise ValueError('Unknown language')
            if key == 'speed':
                if isinstance(value, bool) or not isinstance(value, (int, float)) or not .6 <= value <= 2.:
                    raise ValueError('Speed must be between 0.6 and 2')
            if key in {'follow', 'kindle_crop', 'auto_page_turn', 'highlight'} and not isinstance(value, bool):
                raise ValueError('Expected a boolean setting')
            next_settings[key] = value
        if next_settings['language'] != self.settings['language'] and next_settings['provider'] == 'Local':
            choices = available_voices(next_settings['language'])
            if next_settings['voice'] not in choices:
                next_settings['voice'] = next((k for k, v in choices.items() if v[1] == 'kokoro'), next(iter(choices), DEFAULTS['voice']))
        restart = any(next_settings[k] != self.settings[k] for k in ('voice', 'language', 'provider', 'online_endpoint', 'online_model', 'online_voice'))
        if next_settings['online_endpoint'] != self.settings['online_endpoint']:
            self.online_token = ''
            self.online_models = []
        self.settings = next_settings
        if not self.settings['highlight']:
            self.overlay.close()
        self.mpv_command(['set_property', 'speed', self.settings['speed']])
        self.save()
        self.update()
        if self.enabled and restart:
            self.read_again()

    def configure_token(self, token, remember):
        if not isinstance(token, str) or '\n' in token or '\r' in token or not isinstance(remember, bool):
            raise ValueError('Invalid token settings')
        store_token(CONFIG.with_name('speech-credentials.json'), self.settings['online_endpoint'], token, remember)
        self.online_token = token
        self.settings['remember_token'] = remember
        self.save()
        self.provider_status = 'Token applied' if token else 'Token cleared'

    def refresh_online_models(self):
        if self.enabled:
            raise ValueError("Stop reading before refreshing speech models")
        if self.models_loading:
            return
        self.models_loading = True
        self.provider_status = 'Refreshing online models…'
        def done(code, out, err):
            self.models_loading = False
            if code:
                self.provider_status = err.strip() or 'Model discovery failed; enter a model ID manually.'
                return
            try:
                self.online_models = json.loads(out)['models']
                self.provider_status = 'Models refreshed. Select a speech model; chat models cannot generate audio.'
            except (ValueError, KeyError, TypeError):
                self.provider_status = 'Cannot read provider model list.'
        Task(self, [sys.executable, Path(__file__).with_name('online_provider.py')], done, timeout=70,
             stdin_data=json.dumps({'action': 'models', 'settings': self.settings, 'token': self.online_token}))

    def kokoro_install_status(self):
        if self.installing_kokoro:
            try:
                return json.loads((RUNTIME / 'kokoro-install.json').read_text()).get('message', 'Installing Kokoro…')
            except (OSError, ValueError):
                return 'Installing Kokoro…'
        return self.provider_status

    def install_kokoro(self, language):
        if language not in ('de', 'en'):
            raise ValueError('Choose German or English / multilingual')
        if self.enabled:
            raise ValueError('Stop reading before installing a speech model')
        if self.installing_kokoro:
            return
        self.installing_kokoro = True
        progress = RUNTIME / 'kokoro-install.json'
        progress.unlink(missing_ok=True)
        def done(code, out, err):
            self.installing_kokoro = False
            self.install_task = None
            if code:
                self.provider_status = err.strip()[-500:] or 'Kokoro installation failed. Retry when your network is available.'
                return
            preferred = 'kokoro-martin' if language == 'de' else 'kokoro-heart'
            if voice_is_available(preferred):
                self.settings.update(voice=preferred, language=language)
                self.save()
                self.update()
            self.provider_status = 'Kokoro installed for ' + ('German' if language == 'de' else 'English / multilingual')
        self.install_task = Task(self, [sys.executable, Path(__file__).with_name('install_kokoro.py'),
                                        '--language', language, '--progress', progress], done, timeout=1800)

    def cancel_kokoro_install(self):
        if self.install_task:
            self.install_task.cancel()
        self.install_task = None
        self.installing_kokoro = False
        self.provider_status = 'Kokoro installation cancelled'

    def connection(self):
        client = self.server.nextPendingConnection()
        self.clients.add(client)
        client.readyRead.connect(lambda: self.command(client))
        client.disconnected.connect(lambda: self.clients.discard(client))
        client.disconnected.connect(client.deleteLater)

    def command(self, client):
        if not client.canReadLine():
            return
        try:
            request = json.loads(bytes(client.readLine()))
            command = request['command']
            if command == 'on': self.set_enabled(True, notify=True)
            elif command == 'off': self.set_enabled(False, notify=True)
            elif command == 'toggle': self.set_enabled(not self.enabled, notify=True)
            elif command == 'read': self.read_again()
            elif command == 'pause': self.pause()
            elif command == 'select-area': self.select_area()
            elif command == 'clear-area': self.clear_area()
            elif command == 'voice': self.set_voice(request['value'])
            elif command == 'speed': self.set_speed(request['value'])
            elif command == 'configure': self.configure_settings(request['settings'])
            elif command == 'configure-token': self.configure_token(request.get('token', ''), request.get('remember_token', False))
            elif command == 'online-models': self.refresh_online_models()
            elif command == 'install-kokoro': self.install_kokoro(request.get('language', self.settings['language']))
            elif command == 'cancel-kokoro-install': self.cancel_kokoro_install()
            elif command == 'settings': self.show_settings()
            elif command == 'quit': QTimer.singleShot(100, self.app.quit)
            elif command != 'status': raise ValueError('Unknown command')
            response = dict(enabled=self.enabled, paused=self.paused, status=self.status,
                            custom_area=self.custom_area,
                            settings=self.settings, key_ready=bool(self.online_token), online_models=self.online_models, models_loading=self.models_loading, provider_status=self.kokoro_install_status(), installing_kokoro=self.installing_kokoro, kokoro_languages={'de': voice_is_available('kokoro-martin'), 'en': voice_is_available('kokoro-heart')}, voices=[dict(value=k, label=v[0]) for k, v in available_voices(self.settings['language']).items()], window=self.target_title,
                            queued=len(self.queue), processes=[t.proc.processId() for t in self.speech_tasks])
        except (ValueError, KeyError, TypeError) as error:
            response = {'error': str(error)}
        client.write((json.dumps(response) + '\n').encode())
        client.flush()
        client.disconnectFromServer()

    def shutdown(self):
        self.set_enabled(False)
        self.server.close()
        self.tray.hide()


def main():
    RUNTIME.mkdir(mode=0o700, parents=True, exist_ok=True)
    if len(sys.argv) > 1:
        # Small CLI for desktop launchers and lifecycle verification.
        if not (RUNTIME / 'control.sock').exists() and sys.argv[1] in ('settings', 'on', 'toggle', 'read', 'select-area', 'clear-area'):
            subprocess.run(['systemctl', '--user', 'start', 'ocrvox.service'], check=True)
            for _ in range(50):
                if (RUNTIME / 'control.sock').exists():
                    break
                time.sleep(.1)
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(5)
            try:
                client.connect(str(RUNTIME / 'control.sock'))
            except OSError:
                print('Simple Reader is not running.', file=sys.stderr)
                return 1
            request = {'command': sys.argv[1]}
            if len(sys.argv) > 2:
                request['value'] = sys.argv[2]
            client.sendall((json.dumps(request) + '\n').encode())
            print(client.recv(65536).decode().strip())
        return 0
    app = QApplication([])
    app.setApplicationName('ocrvox')
    app.setQuitOnLastWindowClosed(False)
    lock = QLockFile(str(RUNTIME / 'reader.lock'))
    if not lock.tryLock(0):
        return 0
    QLocalServer.removeServer(str(RUNTIME / 'control.sock'))
    reader = Reader(app)
    app.aboutToQuit.connect(reader.shutdown)
    signal.signal(signal.SIGTERM, lambda *_: app.quit())
    signal.signal(signal.SIGINT, lambda *_: app.quit())
    return app.exec()


if __name__ == '__main__':
    sys.exit(main())
