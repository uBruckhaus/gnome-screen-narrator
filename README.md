# Screen Narrator for GNOME

Reads any window, PDF or Kindle page aloud, and can **translate it first**. Screen Narrator
recognizes the text of a window with local OCR (Tesseract) and speaks it with a
local voice (Kokoro or Piper) in 51 languages. With **Translation → Speak in** it reads, say,
an English page and you hear it in German: translation runs through your own llama.cpp,
LM Studio or Ollama server, or offline with NLLB-200.

This is the GNOME Shell (51) version of the Omarchy plugin
[Screen Narrator](https://github.com/uBruckhaus/omarchy-simple-reader). The reader is the
same; the bar icon, menu and settings window are GNOME's, and the extension does what
Hyprland tools did on Omarchy (focused window, screenshots, area selection, page-turn keys,
passage highlighting).

## Use

- **Headphones icon in the top bar.** Left click: the menu with **Start**, **Pause**, **Stop**,
  the reader's status, **Read the active window**, **Select reading area…**, the reading speed and
  **Settings…**. Right click starts or stops reading; middle click pauses. The icon turns
  green while reading (yellow while paused).
- **First use.** The menu shows what is missing and a **Set up automatically** button: it
  installs the system packages (Tesseract with the text language, mpv, ImageMagick; you are
  asked for your password), a private Python runtime and a voice for your language.
- **Settings** (Reading, Voice, Translation) apply at once: text language, speed, reading
  new pages, passage highlighting, PDF page only, Kindle toolbar crop, automatic
  page turning, reading area, voice and audio output, voices for other languages, and
  translation (language, server and model, or the offline translator, and a test).
- Focus the window to read and press **Start**. That window stays the book: you can work in
  other windows meanwhile, even over it, and it is still read, including pages you turn
  yourself. **Read the active window** makes the focused window the book instead; closing
  the book stops reading. In Document Viewer (Evince) and Papers only the page is read, without page
  numbers; with page turning on, it moves on to the next page and stops at the end.
- **Page turning with the book in the background.** Keys only reach the focused window, so
  the book gets the focus for a tenth of a second for the key (it is not raised) and the
  window you work in gets it back; a key you type in exactly that moment can land in the
  book. A book on another workspace or minimized stops drawing: the page being read is
  finished, and the next one is turned and read once the book is back on screen.

Keyboard shortcuts: the reader adds `simple-reader toggle`, `simple-reader on`,
`simple-reader off` and `simple-reader read` commands; bind one in **Settings → Keyboard →
Custom Shortcuts**.

## Translation

Choose **Speak in**, then a translator:

| Server | Start | Choose |
| --- | --- | --- |
| llama.cpp | `llama-server` (port 8080) | llama.cpp |
| LM Studio | load a chat model, **Developer → Start server** (port 1234) | LM Studio |
| Ollama | `ollama serve` (port 11434) | Ollama |

Then **Model → Refresh** and pick a chat/instruct model; **Test** translates a sample
sentence. A server that needs a key gets it in **API key / token** (kept in memory, or with
**Remember the token** in the owner-only file `~/.config/kindle-reader/translation-credentials.json`). The offline translator (NLLB-200 1.3B, about 1.4 GB) needs no server; its license
is CC-BY-NC 4.0, non-commercial use only.

## Speech servers

Instead of the voices on this computer, an OpenAI-compatible speech server can speak
(`/v1/audio/speech` with WAV output: OpenAI, or a local server such as Kokoro-FastAPI or
LocalAI). In **Settings → Speech server** enter the address, the speech model (**Find
models** lists what the server offers; chat models cannot speak), the voice and, if the
server needs one, an API key. **Test** speaks a sample sentence; **Use** is possible only
for exactly what was tested. **Use voices on this computer** switches back.

Remote servers must use HTTPS and receive the text being read (and may charge for it);
plain HTTP is allowed only on this computer. A key is kept in memory unless **Remember the
token** is on: then it is stored, bound to that server, in the owner-only file
`~/.config/kindle-reader/speech-credentials.json`.

## Qwen voice

Qwen3-TTS speaks with the voice of a recording you choose, through llama.cpp. In **Settings
→ Qwen voice** choose the llama.cpp TTS program (`llama-tts`), the Qwen3-TTS 1.7B model, its
audio projection (`mmproj-….gguf`) and a clear `.wav` recording of the speaker, then **Test**
and **Use**. Nothing is downloaded for it. Qwen speaks Chinese, English, Japanese, Korean,
German, French, Russian, Portuguese, Spanish and Italian.

## Kokoro model updates

**Settings → Voice → Kokoro model updates → Check** compares the installed Kokoro model of the
spoken language with the official sources (SHA256). When a newer verified model exists,
**Update** downloads and tests it before it is used; the old one stays if anything fails.
Updates are never installed on their own.

## What setup installs

Nothing is installed with the extension. **Set up automatically** / **Install** runs
`backend/setup_backend.py`:

- missing system packages with `pkexec pacman -S --needed`: `imagemagick`, `tesseract`,
  `tesseract-data-<language>`, `mpv`, `libpulse`, `libnotify`;
- the user service `~/.config/systemd/user/ocrvox.service` (with a drop-in), a private
  Python runtime and the reader in `~/.local/share/kindle-reader`, the `simple-reader`
  command and its desktop entry;
- the chosen voice (Kokoro or Piper), downloaded from pinned revisions and checked with
  SHA256.

Settings are in `~/.config/kindle-reader/settings.json`, the same paths as on Omarchy.
Disabling the extension leaves the reader service as it is; stop it with
`systemctl --user stop ocrvox.service`.

## Privacy

OCR and local speech stay on your computer. Screenshots and audio go to a private runtime
folder and are removed when reading stops. The extension takes screenshots and sends
page-turn keys only while reading is on, only when the installed reader asks, and a
screenshot only into the reader's runtime folder. Page-turn keys (Right for Kindle, `n` or
Page Down for PDF viewers) go only to the book window, and only while it is on the current
workspace. Screenshots of the book are taken from the window itself, so windows over it are
not read. Nothing leaves
your computer unless you choose a remote translation or speech server.

## Development

```sh
tools/build.sh                       # dist/screen-narrator@ubruckhaus.github.io.shell-extension.zip
tools/headless-test.sh menu          # isolated headless shell: screenshots of the menu and settings
tools/headless-test.sh desktop       # the D-Bus service the reader uses
tools/headless-test.sh capture       # a screenshot and a key through the installed helper, and refusals
tools/headless-test.sh keys          # page-turn keys reach the window, the first one too
tools/headless-test.sh pin           # the book read and turned behind another window; refused off screen
MONITOR=1600x2500 tools/headless-test.sh prefs   # the whole settings window in one screenshot
PYTHON=<python with PySide6> tools/provider-test.sh   # speech server, Qwen voice, translation token (real reader)
cd screen-narrator@ubruckhaus.github.io/backend
QT_QPA_PLATFORM=offscreen python -m unittest discover -s reader -p 'test_*.py'   # needs PySide6, numpy
PYTHONPATH=.:reader python -m unittest test_setup
```

MIT license.
