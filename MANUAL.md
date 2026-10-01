# Simple Reader user manual

Click the headphones icon in the Omarchy bar to open reading controls. Start reader begins local OCR narration of the active window; Stop ends it. Pause/Resume controls playback and Read again restarts the current page. Closing the popup leaves narration running.

Choose voice, German/English text language and reading speed (60–200%). Changes save immediately. Enable following window/page changes, Kindle cropping, page turning and passage highlighting as needed. Select area closes the popup before region selection; Reset area clears it.

The integrated User Manual explains these controls in section cards. Existing reader shortcuts continue to work; this plugin does not install or replace shortcuts. The application launcher opens the bar popup. Speech engines and OCR stay in the existing local reader service.

## Voice availability

Kokoro is the baseline speech engine; install a language model from the popup. Voice choices are filtered against installed runtimes and their specific model/voice files. Piper needs its executable, ONNX model and JSON configuration. Qwen needs a working llama.cpp TTS launcher, the compatible 1.7B backbone and audio projection models, and its speaker recording. Installing a chat server or a chat model does not add a speech voice. This reader currently uses the llama.cpp TTS runner for Qwen; it has no Ollama speech adapter, so Ollama-only voices are not advertised. Existing settings and shortcuts remain compatible.

## Kokoro language installation

Choose **Kokoro language model**: **German · Martin** or **English / multilingual · Kokoro v1.0**. If the selected model/runtime is missing, **Install Kokoro for selected language** appears. Only the selected model and voice files are downloaded; progress and errors appear in the popup. Cancel stops installation. Existing model files are preserved until replacement downloads pass SHA256 verification. Install before starting narration. Successful installation selects the matching reading language and voice.

German model source: [German Martin ONNX](https://huggingface.co/Godelaune/Kokoro-82M-ONNX-German-Martin). Standard model source: [Kokoro ONNX model files](https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.0).

## Online speech providers

Choose **Online**, enter an HTTPS endpoint, choose or enter a speech model ID and voice ID, then apply an API key/bearer token. **Refresh models** is optional; enter the model manually when discovery is unavailable. The provider must support the [OpenAI-compatible speech request](https://developers.openai.com/api/reference/resources/audio/subresources/speech/methods/create) at `/v1/audio/speech` with WAV output. Model discovery can also list chat models, so select a speech-capable model. HTTP is allowed only on loopback for local compatible servers.

OCR stays local. Online speech sends the text being read to the selected provider and can incur provider charges. Requests occur after Start reader. Tokens remain in reader memory unless **Save token locally** is selected. Saved tokens are owner-only plaintext at `~/.config/kindle-reader/speech-credentials.json`, bound to the configured endpoint; they are not included in status responses, shell.json or process arguments. Clear token removes the stored token. Closing the popup leaves narration running; Stop cancels speech requests and playback.
