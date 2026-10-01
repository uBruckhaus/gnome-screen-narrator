# Simple Reader

Read visible text aloud without leaving the Omarchy bar. Simple Reader captures the active window with local OCR and narrates it with a selected voice. Its native popup includes voice, language, speed, pause, reading-area and Kindle page controls. The reader service is included; speech models are downloaded separately.

Click the headphones bar icon for reading, voice, language, speed, Kindle and area controls. Settings save immediately. Closing the popup leaves narration running; Stop ends it. User Manual opens integrated guidance. Existing reader shortcuts remain available; installation does not replace any desktop shortcuts.

The bridge uses only a private local Unix socket and Python standard library. Native Omarchy components are under `native/` with the upstream license. Removing this widget does not remove the reader or its preferences.


## Install

Requires Omarchy Quattro with Quickshell plugins and Hyprland 0.56.2 (Lua API), a working PipeWire audio session, and the following system packages:

```sh
sudo pacman -S --needed uv grim slurp imagemagick tesseract tesseract-data-deu tesseract-data-eng mpv wtype
omarchy plugin add https://github.com/uBruckhaus/omarchy-simple-reader.git
bash ~/.config/omarchy/plugins/ubruckhaus.simple-reader/setup.sh
omarchy plugin enable ubruckhaus.simple-reader
```

Setup creates an isolated Python 3.14 environment with the versions in `requirements.txt`, copies the reader into `~/.local/share/kindle-reader/app`, and creates a user `ocrvox.service`. An existing reader service is reused without overwriting its runtime, settings or configuration. Setup never changes keybindings or enables login autostart. Models, API credentials and recordings are not bundled.

Open the headphones widget, select **German · Martin** or **English / multilingual · Kokoro v1.0**, then use **Install Kokoro for selected language**. Wait for installation to finish before pressing **Start reader**. Model downloads are verified against SHA256 digests. German and English OCR packages are required for their respective reading languages. Online speech is optional; local OCR still needs the system packages above.

## Remove

Press **Stop** before removing the widget:

```sh
omarchy plugin disable ubruckhaus.simple-reader
omarchy plugin remove ubruckhaus.simple-reader
```

Removing the widget preserves reader settings, models and an existing reader service. To stop the backend too, run `systemctl --user stop ocrvox.service`. For a backend installed by this plugin, its files are `~/.local/share/kindle-reader/app` and `~/.config/systemd/user/ocrvox.service`; remove those only if you no longer use the reader. Do not remove a pre-existing service belonging to another reader installation.

## Privacy and lifecycle

OCR and local speech stay on your machine. Screenshots and generated audio use a private runtime directory and are cleaned when reading stops. The reader follows the active window, optionally follows page changes and can highlight the passage being read. Automatic page turning sends a Right-arrow key to the target Kindle window. Closing the popup leaves narration running; Stop cancels reader-owned work and playback. Online speech sends recognized text to your chosen HTTPS provider after Start, as described below.

## Voice availability

Kokoro is the baseline speech engine; install a language model from the popup. Voice choices are filtered against installed runtimes and their specific model/voice files. Piper needs its executable, ONNX model and JSON configuration. Qwen needs a working llama.cpp TTS launcher, the compatible 1.7B backbone and audio projection models, and its speaker recording. Installing a chat server or a chat model does not add a speech voice. This reader currently uses the llama.cpp TTS runner for Qwen; it has no Ollama speech adapter, so Ollama-only voices are not advertised. Existing reader settings remain compatible. Optional Qwen models can be located through the `QWEN_TTS_MODEL_DIR` service environment variable; the default is `~/.local/share/kindle-reader/models/Qwen3-TTS-1.7B`. A compatible `~/.local/bin/llama-tts` runner and reference recordings in `~/.local/share/kindle-reader/voices` are required.

## Kokoro language installation

Choose **Kokoro language model**: **German · Martin** or **English / multilingual · Kokoro v1.0**. If the selected model/runtime is missing, **Install Kokoro for selected language** appears. Only the selected model and voice files are downloaded; progress and errors appear in the popup. Cancel stops installation. Existing model files are preserved until replacement downloads pass SHA256 verification. Install before starting narration. Successful installation selects the matching reading language and voice.

German model source: [German Martin ONNX](https://huggingface.co/Godelaune/Kokoro-82M-ONNX-German-Martin). Standard model source: [Kokoro ONNX model files](https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.0).

## Online speech providers

Choose **Online**, enter an HTTPS endpoint, choose or enter a speech model ID and voice ID, then apply an API key/bearer token. **Refresh models** is optional; enter the model manually when discovery is unavailable. The provider must support the [OpenAI-compatible speech request](https://developers.openai.com/api/reference/resources/audio/subresources/speech/methods/create) at `/v1/audio/speech` with WAV output. Model discovery can also list chat models, so select a speech-capable model. HTTP is allowed only on loopback for local compatible servers.

OCR stays local. Online speech sends the text being read to the selected provider and can incur provider charges. Requests occur after Start reader. Tokens remain in reader memory unless **Save token locally** is selected. Saved tokens are owner-only plaintext at `~/.config/kindle-reader/speech-credentials.json`, bound to the configured endpoint; they are not included in status responses, shell.json or process arguments. Clear token removes the stored token. Closing the popup leaves narration running; Stop cancels speech requests and playback.

## Marketplace summary

**Simple Reader — visible text, spoken aloud.** Local OCR narration with German and English Kokoro voices, adjustable reading speed, passage highlighting, selected reading areas and Kindle page controls. Optional OpenAI-compatible online speech supports API keys or bearer tokens. A native Omarchy bar popup keeps controls together. One-time backend and voice setup is required; no model or credential is included.

## Development checks

```sh
omarchy plugin validate .
bash -n setup.sh
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=none ~/.local/share/kindle-reader/venv/bin/python -m unittest discover -s reader -p 'test_*.py'
```

MIT license. Vendored Omarchy controls retain their upstream MIT notice in `native/LICENSE`; see `THIRD_PARTY_NOTICES.md`.
