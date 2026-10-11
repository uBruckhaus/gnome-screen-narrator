# Screen Narrator user manual

Click the headphones icon in the Omarchy bar to open reading controls; right-click it to start or stop reading directly. In the popup, **▶ Start**, **❚❚ Pause** and **■ Stop** sit right under the summary. Start begins local OCR narration of the active window; Stop ends it. Pause/Resume controls playback and Read again restarts the current page. Closing the popup leaves narration running.

Choose voice, text language (51 languages) and reading speed (60–200%). Reading controls save immediately; provider setup applies after a successful test and Use provider. Enable following window/page changes, Kindle cropping, page turning and passage highlighting as needed. Select area closes the popup before region selection; Reset area clears it.

The integrated User Manual explains these controls in section cards. Existing reader shortcuts continue to work; this plugin does not install or replace shortcuts. The application launcher opens the bar popup. Speech engines and OCR stay in the existing local reader service.

## Provider, voice and audio output

The main panel always shows the **active provider**, voice, language and readiness.
**Speech provider** opens setup for your choice; it does not switch immediately.
**Voice / speaker** selects a voice for the active provider. **Audio output** selects
speakers or headphones for every engine. **System default** follows the desktop
output. A disconnected selected device requires reconnection or another selection;
playback does not silently move to a different output. **Reading options** expands
Kindle, following, highlighting and reading-area controls.

## Add or switch a provider

Open **Add / manage speech providers…** and follow **Set up → Test provider voice →
Use provider**. The test speaks a short sample without OCR or page turns. Setup,
file browsing and testing keep the current provider selected. **Use provider**
becomes available after a successful test and saves the new selection.

- **Kokoro:** choose the reading language and **Install Kokoro voice & reader**.
  Kokoro speaks English (US and British voices), German (Martin), Spanish, French,
  Italian, Brazilian Portuguese, Hindi, Japanese and Mandarin Chinese. Japanese adds a
  pronunciation dictionary (misaki with UniDic, about 270 MB) that reads kanji correctly.
  Downloads are about 330–354 MB plus runtime packages, verified with SHA256.
  No llama.cpp or Ollama is needed. Repair is available for installed languages.
- **Piper:** choose the reading language, then **Install / repair Piper voice &
  reader**. Piper has one curated voice for each language except Japanese, from Arabic
  to Vietnamese. The installer uses a separate
  Python runtime with pinned Piper 1.8.0, downloads the voice (60–122 MB), verifies the model and configuration
  using SHA256, and checks speech generation. It preserves the active voice and
  existing reader packages. Existing Piper voices remain available.
- **Qwen:** follow the four-file checklist for an existing llama.cpp TTS runner,
  compatible 1.7B backbone, audio projection and WAV speaker recording. Files are
  drafted until activation. Automatic Qwen downloads are not provided. Chat models
  in Ollama or a chat server do not supply a speech voice.
- **Speech server:** enter a server address, speech model, voice and optional token,
  then test and activate the connection. Remote servers receive the text and may
  charge for speech. A compatible localhost server can keep speech local.

Setup displays progress and supports cancellation outside system package
transactions. Retry reuses verified downloads. Missing system packages request
system authorization. Reader updates keep backups, models, voices and preferences.
Installing another language does not change the active provider or language.
Setup also installs the Tesseract OCR data for the chosen language
(`tesseract-data-<code>`). If Kokoro has no voice for a language, the popup offers
Piper instead, and the reverse. Thai and Lithuanian are not offered yet, because no
local voice here pronounces them correctly. A speech server can still read any language
your OCR data supports.

**Advanced · files & maintenance** contains manual Piper/Qwen paths, Kokoro model
update checks, and active speech-server model discovery and token clearing.

German Kokoro source: [German Martin ONNX](https://huggingface.co/Godelaune/Kokoro-82M-ONNX-German-Martin).
English Kokoro source: [Kokoro ONNX model files](https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.0).
Piper sources: [Piper runtime](https://github.com/OHF-Voice/piper1-gpl),
[Piper voice models and their model cards](https://huggingface.co/rhasspy/piper-voices).
Whisper is speech recognition, so it is not offered as a reading voice.

## Translation (optional)

Translation is **off** by default. When it is on, the reader recognizes the text in
the *text language* and speaks it in the *Speak in* language: for example German
pages read in Japanese, or Russian pages read in English. Any two of the 51
languages work.

1. **Voice for the spoken language.** Open **Add / manage speech providers…**. While
   translation is on, setup installs and tests voices for the spoken language.
2. **Translator.** Open **Translation**, choose *Speak in* and one translator:

   **A. Local LLM server** (best quality; a GPU helps). Any OpenAI-compatible chat
   server works. Recognized text stays on your computer when the server runs locally.

   | Server | Install | Start | Choose |
   | --- | --- | --- | --- |
   | llama.cpp | `sudo pacman -S llama-cpp`, or a GPU build from the [llama.cpp releases](https://github.com/ggml-org/llama.cpp/releases) | `llama-server -m ~/models/<model>.gguf --port 8080` | Server: llama.cpp |
   | LM Studio | [lmstudio.ai](https://lmstudio.ai) | load a chat model, **Developer → Start server** (port 1234) | Server: LM Studio |
   | Ollama | `sudo pacman -S ollama` | `ollama serve`, then `ollama pull gemma3` | Server: Ollama |

   Use an instruct/chat model; 2–4B models (Gemma, Qwen, Llama) translate well
   enough for reading along, larger ones read more naturally. **Refresh models**
   lists what the server offers. A token is needed only for servers that require
   one; a remote server must use HTTPS and receives the recognized text.

   **B. Offline NLLB-200.** **Install offline translator** downloads Meta's NLLB-200
   1.3B model (OpenNMT CTranslate2 conversion, about 1.4 GB, SHA256-verified) and a
   small runtime. It runs on the CPU without any server. Its license is
   **CC-BY-NC 4.0: non-commercial use only**.
3. **Test translation** translates a sample sentence and shows the result without
   speaking. Then use **Start reading** as usual.

Each passage is translated just before it is spoken, while the previous one plays.
Highlighting marks the original sentence. If the translator fails, reading stops
with the server's message; turn translation off to read in the text language again.

## Online speech providers

Open **Add / manage speech providers… → Speech server**, enter an HTTPS endpoint, choose or enter a speech model ID and voice ID, then enter an API key/bearer token if needed, **Test provider voice**, and **Use provider**. **Refresh models** is optional; enter the model manually when discovery is unavailable. The provider must support the [OpenAI-compatible speech request](https://developers.openai.com/api/reference/resources/audio/subresources/speech/methods/create) at `/v1/audio/speech` with WAV output. Model discovery can also list chat models, so select a speech-capable model. HTTP is allowed only on loopback for local compatible servers.

OCR stays local. Online speech sends the text being read to the selected provider and can incur provider charges. Requests occur after ▶ Start or Test voice. Tokens remain in reader memory unless **Remember token on this device** is selected. Saved tokens are owner-only plaintext at `~/.config/kindle-reader/speech-credentials.json`, bound to the configured endpoint; they are not included in status responses, shell.json or process arguments. Clear token removes the stored token. Closing the popup leaves narration running; Stop cancels speech requests and playback.

## Check for Kokoro model updates

Stop reading, then open **Add / manage speech providers… → Kokoro → Advanced · files & maintenance**. Choose the language
and press **Check for model updates**. If an update is available, use
**Update selected Kokoro model**. Downloads show progress and can be cancelled.
The old model remains selected until both new files pass checksum and speech
validation. Checking never installs an update automatically.
