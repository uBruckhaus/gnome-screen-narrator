# Screen Narrator

*Formerly Simple Reader.* The plugin ID `ubruckhaus.simple-reader`, the `simple-reader` command and all data paths are unchanged.

Read visible text aloud without leaving the Omarchy bar. Screen Narrator captures the active window with local OCR and narrates it with a selected voice. Its native popup includes voice, language, speed, pause, reading-area and Kindle page controls. The reader service is included; speech models are downloaded separately.

Click the headphones bar icon for reading, voice, language, speed, Kindle and area controls. Settings save immediately. Closing the popup leaves narration running; Stop ends it. User Manual opens integrated guidance. Existing reader shortcuts remain available; installation does not replace any desktop shortcuts.

The bridge uses only a private local Unix socket and Python standard library. Native Omarchy components are under `native/` with the upstream license. Removing this widget does not remove the reader or its preferences.


## Install

Install and enable the plugin on Omarchy Quattro:

```sh
omarchy plugin add https://github.com/uBruckhaus/omarchy-simple-reader.git
omarchy plugin enable ubruckhaus.simple-reader
```

Open the headphones widget and **Add / manage speech providers…**. Choose your
reading language and Kokoro or Piper, then install the voice. Then choose **Test provider
voice → Use provider**, focus your text window and press **▶ Start** (or right-click the bar icon; right-click again stops).

The main panel keeps the active provider, voice and audio output visible. Provider
setup stays separate from active settings until you test and activate it. Reading
options expand Kindle, following, highlighting and area controls. Advanced contains
manual files and maintenance. See [MANUAL.md](MANUAL.md) for the full setup flow.

**50 languages.** Kokoro speaks English, German, Spanish, French, Italian, Portuguese,
Hindi and Chinese (about 330–354 MB plus runtime packages). Piper covers all
50 languages with one voice each (60–122 MB plus a separate pinned runtime). Setup
installs the matching Tesseract OCR data. The popup defaults to your desktop locale. Progress, retry and cancellation
are built in; system package transactions request authorization and cannot be
cancelled from the popup. Setup does not start narration or add shortcuts.

Existing managed reader installations are upgraded with a backup of runtime and service files
in `~/.local/share/kindle-reader/backups/`. Settings, credentials, voices and models are retained.
An unrelated, unmanaged `ocrvox.service` is preserved and setup reports the conflict.
The existing plugin ID and data paths remain compatible with Simple Reader installations.

For terminal setup, `bash ~/.config/omarchy/plugins/ubruckhaus.simple-reader/setup.sh --language fr`
performs the same guided installation (any two-letter code from the language list;
Piper is chosen automatically when Kokoro has no voice for it). `--backend-only` installs or upgrades the backend without
downloading or selecting a voice.

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

Kokoro and Piper offer guided installation; Qwen offers a checklist for an existing
llama.cpp TTS runner, compatible backbone, audio projection and speaker recording.
Only available voices are selectable. Custom file paths remain under Advanced.
Installing a chat model does not install a speech voice; Whisper is speech-to-text.
See [MANUAL.md](MANUAL.md) for voice requirements and model update instructions.

## Online speech providers

Under **Add / manage speech providers…**, choose **Speech server**, enter an HTTPS endpoint, choose or enter a speech model ID and voice ID, enter an API key/bearer token if required, then **Test provider voice → Use provider**. **Refresh models** is optional; enter the model manually when discovery is unavailable. The provider must support the [OpenAI-compatible speech request](https://developers.openai.com/api/reference/resources/audio/subresources/speech/methods/create) at `/v1/audio/speech` with WAV output. Model discovery can also list chat models, so select a speech-capable model. HTTP is allowed only on loopback for local compatible servers.

OCR stays local. Online speech sends the text being read to the selected provider and can incur provider charges. Requests occur after ▶ Start or Test voice. Tokens remain in reader memory unless **Remember token on this device** is selected. Saved tokens are owner-only plaintext at `~/.config/kindle-reader/speech-credentials.json`, bound to the configured endpoint; they are not included in status responses, shell.json or process arguments. Clear token removes the stored token. Closing the popup leaves narration running; Stop cancels speech requests and playback.

## Marketplace summary

**Screen Narrator — visible text, spoken aloud.** Local OCR narration in 50 languages with Kokoro and Piper voices, adjustable reading speed, passage highlighting, selected reading areas and Kindle page controls. Optional OpenAI-compatible online speech supports API keys or bearer tokens. A native Omarchy bar popup keeps controls together. Guided one-button local Kokoro setup; optional Piper, Qwen via llama.cpp, and compatible speech servers. No voice model or credential is bundled.

## Development checks

```sh
omarchy plugin validate .
bash -n setup.sh
python3 -m unittest discover -s tests
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_STYLE_OVERRIDE=Fusion ~/.local/share/kindle-reader/venv/bin/python -m unittest discover -s reader -p 'test_*.py'
```

MIT license. Vendored Omarchy controls retain their upstream MIT notice in `native/LICENSE`; see `THIRD_PARTY_NOTICES.md`.

Kokoro keeps its selected model in a reusable subprocess during reading, so
successive chunks and pages avoid reloading the voice model. Turning the reader
off releases it; changing a page during synthesis cancels the old request before
reusing audio files. Automatic Kindle page turns scan after 250 ms, confirm that
the page image is stable, and then run one OCR pass.

## Reading shortcuts

Setup adds the **Screen Narrator** application entry with **Start / stop reading**,
**Start reading**, and **Stop reading** desktop actions. In Launch & Bind,
open **Apps → Screen Narrator → Shortcuts**, choose the action and assign your key.
The default application action opens the reading controls. Setup keeps the
existing `simple-reader.desktop` ID and `simple-reader` command so previous
bindings continue to work. It does not assign a key automatically.

The same actions are available from a terminal as `simple-reader toggle`,
`simple-reader on`, and `simple-reader off`.

Launch & Bind's **Plugins** view also exposes these controls through Screen Narrator's
tray menu. Choose **Screen Narrator** under **Running in the bar**, open its action
menu, then **Shortcut…** and select **Start / stop reading**, **Start reading**,
**Stop reading** or **Pause / resume**. Their menu labels stay fixed so saved
shortcuts work in both reading states. The menu also offers **Read active window
again**, the reading area, and the submenus **Voice**, **Text language**, **Audio
output** and **Reading speed**; each entry can be clicked or bound to a key. The
submenus follow the current settings (Voice lists the voices for the current
language). The separate shell-plugin entry continues to open the popup.

### Kokoro model updates

Open **Add / manage speech providers… → Kokoro → Advanced · files & maintenance**, select the voice language, and use
**Check for model updates**. The check compares your installed files with the
German model repository's SHA256 metadata or the standard Kokoro model releases.
If different verified files are available, **Update selected Kokoro model** appears.
Stop reading before checking or updating. Updates are never installed automatically.
Both downloaded files are checksum-verified and tested together before activation;
existing models stay available if downloading or validation fails. Updated models
are stored under `kokoro/versions/`, separately from the original default models.
Reader setup and repair retain the active updated model instead of reverting it.

Page changes now use two quick image captures to confirm a stable page, followed
by a single OCR pass. Unchanged pages skip OCR. The opening speech chunk is shorter
so narration can begin sooner while the remaining chunks are generated in advance.
