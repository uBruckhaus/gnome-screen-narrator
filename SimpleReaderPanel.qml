import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import "native/Commons"
import qs.Commons as Theme
import "native/Ui" as Ui

Ui.Panel {
  id: root
  moduleName: "ubruckhaus.simple-reader"
  manageIpc: false
  property var anchorItem: null
  property var hostWidget: null
  property var state: ({})
  property var config: state.settings || ({})
  property var pending: []
  property var currentRequest: ({})
  property string message: "Ready"
  property string actionError: ""
  property bool showManualView: false
  property bool loaded: false
  property string candidateLanguage: ""
  property bool rememberToken: false
  property bool showAdvanced: false
  property string engineChoice: ""
  property bool showProviders: false
  property bool showReadingOptions: false
  property string candidateVoice: ""
  property var draftPaths: ({})
  property bool draftUseManaged: false
  property string onlineEndpoint: ""
  property string onlineModel: ""
  property string onlineVoice: ""
  readonly property string activeEngine: config.provider === "Online" ? "Online" : engineForVoice(config.voice)
  readonly property var activeVoices: (state.voices || []).filter(function(v) { return v.engine === root.activeEngine.toLowerCase() })
  readonly property var candidateVoices: (sameSettings(state.probed_settings || {}, candidateBase()) ? state.probed_voices || [] : []).filter(function(v) { return v.engine === root.selectedEngine.toLowerCase() })
  function sameSettings(a, b) {
    var keys = Object.keys(b)
    return Object.keys(a).length === keys.length && keys.every(function(k) { return a[k] === b[k] })
  }
  function candidatePath(key) {
    var managed = (state.piper_installations || {})[installLanguage] || {}
    return draftUseManaged && selectedEngine === "Piper" ? managed[key] || draftPaths[key] || "" : draftPaths[key] || ""
  }
  function candidateBase() {
    var settings = {provider: "Local", language: installLanguage}
    var keys = selectedEngine === "Piper" ? ["piper_runner", "piper_model", "piper_config"] : selectedEngine === "Qwen" ? ["qwen_runner", "qwen_model", "qwen_projection", "qwen_speaker"] : []
    keys.forEach(function(k) { settings[k] = root.candidatePath(k) })
    return settings
  }
  function probeCandidate() {
    if (backendReady && selectedEngine !== "Online" && showProviders) request({command: "probe-provider", settings: candidateBase()})
  }
  function setCandidatePath(key, value) {
    var copy = Object.assign({}, draftPaths, candidateBase())
    copy[key] = value
    draftPaths = copy
    draftUseManaged = false
    candidateVoice = ""
    probeCandidate()
  }
  readonly property var languageOptions: state.languages && state.languages.length ? state.languages : [{value: "en", label: "English", kokoro: true, piper: true, piper_mb: 109}]
  function languageInfo(code) {
    for (var i = 0; i < languageOptions.length; i++) if (languageOptions[i].value === code) return languageOptions[i]
    return {value: code, label: code || "Unknown language", kokoro: false, piper: false, piper_mb: 0}
  }
  readonly property bool kokoroSupportsLanguage: languageInfo(installLanguage).kokoro === true
  readonly property bool piperSupportsLanguage: languageInfo(installLanguage).piper === true
  // The chosen local engine cannot speak the reading language; offer the other one.
  readonly property bool engineLacksLanguage: selectedEngine === "Kokoro" ? !kokoroSupportsLanguage : selectedEngine === "Piper" && !piperSupportsLanguage
  readonly property string installLanguageName: languageInfo(installLanguage).label.split(" · ")[0]
  readonly property string activeVoiceLabel: config.provider === "Online" ? (config.online_voice || "No voice") : voiceLabel(config.voice)
  readonly property string providerSummary: "Active: " + (activeEngine === "Online" ? "Speech server · " + (config.online_endpoint || "") : activeEngine + " · Local") + "\n" + activeVoiceLabel + " · " + languageInfo(config.language).label + " · " + (backendReady && voiceReady ? "Ready" : "Setup needed")
  function engineForVoice(voice) {
    var id = voice || ""
    return id.indexOf("piper") >= 0 || id.indexOf("fast") >= 0 ? "Piper" : id.indexOf("qwen") >= 0 ? "Qwen" : "Kokoro"
  }
  function voiceLabel(id) {
    var voices = state.voices || []
    for (var i = 0; i < voices.length; i++) if (voices[i].value === id) return voices[i].label
    return id || "No voice selected"
  }
  function providerOptions() {
    return [{value: "Kokoro", label: "Kokoro · local · " + (languageInfo(installLanguage).kokoro ? "recommended" : "no " + languageInfo(installLanguage).label.split(" · ")[0] + " voice")},
      {value: "Piper", label: "Piper · local · " + ((Object.keys(state.piper_installations || {}).length || (state.voices || []).some(function(v) { return v.engine === "piper" })) ? "installed" : "install available")},
      {value: "Qwen", label: "Qwen · local · " + ((state.voices || []).some(function(v) { return v.engine === "qwen" }) ? "installed" : "requires existing TTS files")},
      {value: "Online", label: "Speech server · online or localhost"}]
  }
  function manageProvider(engine) {
    engineChoice = engine || activeEngine
    candidateLanguage = config.language || "en"
    draftPaths = Object.assign({}, config)
    draftUseManaged = !config.piper_model
    candidateVoice = ""
    providerToken.text = ""
    testedToken = ""
    onlineEndpoint = config.online_endpoint || "https://api.openai.com/v1"
    onlineModel = config.online_model || ""
    onlineVoice = config.online_voice || "alloy"
    showProviders = true
    showAdvanced = false
    probeCandidate()
    Qt.callLater(function() { panelScroll.contentY = Math.min(providerSettings.mapToItem(content, 0, 0).y, Math.max(0, panelScroll.contentHeight - panelScroll.height)) })
  }
  function candidateSettings() {
    if (selectedEngine === "Online") return {provider: "Online", online_endpoint: onlineEndpoint, online_model: onlineModel, online_voice: onlineVoice, language: installLanguage}
    var voice = candidateVoice || (candidateVoices.length ? candidateVoices[0].value : "")
    return Object.assign(candidateBase(), {voice: voice})
  }
  function candidateReady() {
    if (!backendReady) return false
    if (selectedEngine === "Online") return !!onlineEndpoint && !!onlineModel.trim() && !!onlineVoice.trim()
    return candidateVoices.some(function(v) { return v.value === (candidateVoice || (candidateVoices.length ? candidateVoices[0].value : "")) })
  }
  function candidateVerified() {
    var verified = state.verified_provider || {}, desired = candidateSettings()
    var keys = Object.keys(desired)
    return keys.length > 0 && keys.every(function(key) { return verified[key] === desired[key] }) && providerToken.text === testedToken
  }
  property string testedToken: ""
  function testCandidate() {
    testedToken = providerToken.text
    request({command: "test-provider", settings: candidateSettings(), token: selectedEngine === "Online" ? providerToken.text : null})
  }
  function useCandidate() {
    request({command: "use-provider", settings: candidateSettings(), token: selectedEngine === "Online" ? providerToken.text : null, remember_token: rememberToken})
  }
  readonly property bool setupBusy: state.setup_busy === true
  readonly property bool backendReady: state.backend_ready === true && !(state.missing_packages || []).length
  readonly property bool voiceReady: config.provider === "Online" ? !!config.online_model && !!config.online_voice : (state.voices || []).some(function(v) { return v.value === config.voice })
  readonly property string selectedEngine: engineChoice || activeEngine
  function switchInstallEngine() {
    engineChoice = selectedEngine === "Kokoro" ? "Piper" : "Kokoro"
    candidateVoice = ""
    probeCandidate()
  }
  function chooseFile(key) { filePicker.settingKey = key; filePicker.open() }
  function setup() {
    if (state.installing_kokoro || state.kokoro_checking) { message = "Wait for the model operation to finish."; return }
    request({command: "setup", language: installLanguage})
  }

  readonly property string installLanguage: candidateLanguage || config.language || "en"
  readonly property bool kokoroSelectedInstalled: (state.kokoro_languages || {})[installLanguage] === true
  readonly property bool enabledReader: state.enabled === true
  onShowManualViewChanged: panelScroll.contentY = 0
  function open() { controller.show(); request({command: "status"}) }
  function close() { controller.hide() }
  function toggle() { opened ? close() : open() }
  function set(key, value) {
    if (!backendReady || setupBusy) { message = "Finish reader setup before changing settings."; return }
    var changes = {}; changes[key] = value
    request({command: "configure", settings: changes})
  }
  function request(payload) {
    if (payload.command !== "status" && payload.command !== "probe-provider") actionError = ""
    if (payload.command === "status" && (bridge.running || pending.length)) return
    pending = pending.concat([payload]); nextRequest()
  }
  function nextRequest() {
    if (bridge.running || !pending.length) return
    currentRequest = pending[0]; pending = pending.slice(1); bridge.running = true
  }
  function acceptResponse(text) {
    try {
      var data = JSON.parse(text)
      if (data.error) { actionError = data.error; message = actionError; return }
      if (currentRequest.command === "use-provider") {
        providerToken.text = ""
        showProviders = false
        engineChoice = ""
      }
      if (!loaded) rememberToken = (data.settings || {}).remember_token === true
      state = data; message = actionError || (data.setup_busy || data.setup_phase === "error" || data.setup_phase === "cancelled" ? data.setup_message : data.provider_status || data.status || "Ready"); loaded = true
      if (showProviders && selectedEngine !== "Online" && backendReady && !setupBusy && !sameSettings(state.probed_settings || {}, candidateBase())) probeCandidate()
    } catch (e) { message = "Cannot read Screen Narrator response." }
  }
  Process {
    id: bridge
    command: ["python3", Qt.resolvedUrl("bridge.py").toString().replace(/^file:\/\//, "")]
    stdinEnabled: true
    onStarted: write(JSON.stringify(root.currentRequest) + "\n")
    stdout: StdioCollector { onStreamFinished: root.acceptResponse(text) }
    onExited: Qt.callLater(root.nextRequest)
  }
  Timer { interval: 1500; repeat: true; running: root.opened; onTriggered: root.request({command: "status"}) }
  Ui.PopupCard {
    id: popup
    bar: root.bar
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    open: root.opened
    contentWidth: fittedContentWidth(Style.space(460))
    contentHeight: fittedContentHeight(content.implicitHeight)
    Flickable {
      id: panelScroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: content.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
      Column {
        id: content
        width: parent.width
        focus: root.opened
        spacing: Style.space(12)
        Keys.onEscapePressed: root.close()
        Item {
          width: parent.width
          height: Style.space(28)
          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Screen Narrator"
            color: Theme.Color.accent
            font.family: Theme.Style.font.family
            font.pixelSize: Theme.Style.font.title
            font.bold: true
          }
          Ui.Button { focusable: true;
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: Style.space(24)
            text: root.showManualView ? "✕ Close Manual" : "📖 User Manual"
            fontSize: Style.font.caption
            bordered: true
            selected: root.showManualView
            onClicked: root.showManualView = !root.showManualView
          }
        }
        Text { width: parent.width; text: "Read screen text and Kindle pages aloud."; color: Color.foreground; opacity: 0.65; font.family: Style.font.family; font.pixelSize: Style.font.body }
        Column {
          width: parent.width
          spacing: Style.spacing.md
          visible: !root.showManualView
          Rectangle {
            width: parent.width
            height: activeSummary.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: Qt.rgba(Theme.Color.accent.r, Theme.Color.accent.g, Theme.Color.accent.b, 0.12)
            border.color: Theme.Color.accent
            Text { id: activeSummary; anchors.fill: parent; anchors.margins: Style.space(10); text: root.providerSummary; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
          }
          Ui.Dropdown { id: activeProviderPicker; width: parent.width; label: "Speech provider"; options: root.providerOptions(); value: root.activeEngine; enabled: !root.enabledReader && !root.setupBusy; onChanged: { root.manageProvider(value); activeProviderPicker.value = Qt.binding(function() { return root.activeEngine }) } }
          Ui.Dropdown { width: parent.width; label: "Voice / speaker"; visible: root.activeEngine !== "Online"; options: root.activeVoices; value: root.config.voice || ""; enabled: root.backendReady && !root.setupBusy && !root.enabledReader; onChanged: root.request({command: "configure", settings: {provider: "Local", voice: value}}) }
          Column {
            width: parent.width; spacing: Style.space(4); visible: root.activeEngine === "Online"
            Ui.PanelSectionHeader { text: "Voice / speaker" }
            Ui.TextField { width: parent.width; text: root.config.online_voice || ""; enabled: root.backendReady && !root.setupBusy && !root.enabledReader; placeholderText: "Speech server voice ID"; onEditingFinished: root.set("online_voice", text) }
          }
          Ui.Dropdown { width: parent.width; label: "Audio output · speakers / headphones"; options: root.state.audio_outputs || [{value: "auto", label: "System default"}]; value: root.config.audio_output || "auto"; enabled: root.backendReady && !root.setupBusy; onChanged: root.set("audio_output", value) }
          Text { width: parent.width; visible: (root.config.audio_output || "auto") !== "auto" && !(root.state.audio_outputs || []).some(function(v) { return v.value === root.config.audio_output }); text: "Selected audio output is disconnected. Reconnect it or choose System default."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          Ui.Dropdown { width: parent.width; id: textLanguagePicker; label: "Text language"; enabled: root.backendReady && !root.setupBusy && !root.enabledReader; options: root.languageOptions; value: root.config.language || "en"; onChanged: { root.set("language", value); textLanguagePicker.value = Qt.binding(function() { return root.config.language || "en" }) } }
          Ui.NumberField { label: "Reading speed (%)"; enabled: root.backendReady && !root.setupBusy; from: 60; to: 200; stepSize: 5; value: Math.round((root.config.speed || 1) * 100); onModified: root.set("speed", value / 100) }
          Ui.Button { focusable: true; width: parent.width; text: root.showProviders ? "Close provider setup" : "Add / manage speech providers…"; bordered: true; enabled: !root.enabledReader && !root.setupBusy; onClicked: root.showProviders ? root.showProviders = false : root.manageProvider(root.activeEngine) }
          Text { width: parent.width; visible: !root.backendReady || !root.voiceReady; text: "Set up your chosen provider below before reading."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          Ui.Button { focusable: true; width: parent.width; visible: (!root.backendReady || !root.voiceReady) && !root.showProviders; text: "Set up speech provider…"; bordered: true; enabled: !root.setupBusy; onClicked: root.manageProvider(root.activeEngine) }
          Text { width: parent.width; visible: root.setupBusy; text: root.state.setup_message || "Setting up…"; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          Ui.Button { focusable: true; text: "Cancel setup"; visible: root.setupBusy; enabled: root.state.setup_phase !== "packages"; onClicked: root.request({command: "cancel-setup"}) }
          Flow {
            width: parent.width
            spacing: Style.spacing.md
            Ui.Button { focusable: true; text: root.enabledReader ? "Stop" : "Read active window"; bordered: true;  enabled: root.loaded && !root.setupBusy && !root.state.kokoro_checking && !root.state.installing_kokoro && (root.enabledReader || root.backendReady && root.voiceReady); onClicked: root.request({command: root.enabledReader ? "off" : "on"}) }
            Ui.Button { focusable: true; text: root.state.paused ? "Resume" : "Pause"; bordered: true;  enabled: root.enabledReader; onClicked: root.request({command: "pause"}) }
            Ui.Button { focusable: true; text: "Test voice"; bordered: true; enabled: root.backendReady && root.voiceReady && !root.enabledReader && !root.setupBusy && !root.state.installing_kokoro && !root.state.kokoro_checking; onClicked: root.request({command: "test-voice"}) }
            Ui.Button { focusable: true; text: "Read again";  enabled: root.enabledReader && !root.state.testing_voice; onClicked: root.request({command: "read"}) }
          }
          Text { width: parent.width; text: root.message; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          Ui.Button { focusable: true; width: parent.width; text: root.showReadingOptions ? "▾ Reading options" : "▸ Reading options"; bordered: true; onClicked: root.showReadingOptions = !root.showReadingOptions }
          Column {
            width: parent.width; spacing: Style.spacing.md; visible: root.showReadingOptions
          Text { text: "Reading & Kindle"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Theme.Style.font.bodySmall; font.bold: true }
          Ui.Toggle { width: parent.width; enabled: root.backendReady && !root.setupBusy; label: "Follow active window and page changes"; checked: root.config.follow !== false; onClicked: root.set("follow", !checked) }
          Ui.Toggle { width: parent.width; enabled: root.backendReady && !root.setupBusy; label: "Skip Kindle toolbar and margins"; checked: root.config.kindle_crop !== false; onClicked: root.set("kindle_crop", !checked) }
          Ui.Toggle { width: parent.width; enabled: root.backendReady && !root.setupBusy; label: "Turn Kindle pages after reading"; checked: root.config.auto_page_turn !== false; onClicked: root.set("auto_page_turn", !checked) }
          Ui.Toggle { width: parent.width; enabled: root.backendReady && !root.setupBusy; label: "Highlight the passage being read"; checked: root.config.highlight !== false; onClicked: root.set("highlight", !checked) }
          Ui.PanelSeparator {}
          Text { text: "Reading Area"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Theme.Style.font.bodySmall; font.bold: true }
          Text { width: parent.width; text: root.state.custom_area ? "Custom reading area selected" : root.config.kindle_area ? "Saved Kindle reading area" : "Full active window"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          Flow {
            width: parent.width
            spacing: Style.spacing.md
            Ui.Button { focusable: true; text: "Select area…"; enabled: root.backendReady && !root.setupBusy; bordered: true;  onClicked: { root.close(); selectionDelay.start() } }
            Ui.Button { focusable: true; text: "Reset area"; enabled: root.backendReady && !root.setupBusy; bordered: true;  onClicked: root.request({command: "clear-area"}) }
          }
          }
          Ui.PanelSeparator { visible: root.showProviders }
          Column {
            id: providerSettings
            width: parent.width
            spacing: Style.spacing.md
            visible: root.showProviders
            enabled: !root.enabledReader && !root.setupBusy
            Text { text: "Set up speech provider"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
            Text { width: parent.width; text: "1. Choose and set up  ·  2. Test voice  ·  3. Use provider\nYour active provider stays selected until you choose Use provider."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Ui.Dropdown { id: setupProviderPicker; width: parent.width; label: "Provider to set up"; options: root.providerOptions(); value: root.selectedEngine; onChanged: { root.engineChoice = value; root.candidateVoice = ""; root.showAdvanced = false; root.probeCandidate(); setupProviderPicker.value = Qt.binding(function() { return root.selectedEngine }) } }
            Ui.Button { focusable: true; width: parent.width; text: "Set up reader runtime"; visible: !root.backendReady && root.selectedEngine !== "Kokoro" && root.selectedEngine !== "Piper"; bordered: true; onClicked: root.request({command: "setup", language: root.installLanguage, backend_only: true}) }
            Column {
              width: parent.width; spacing: Style.spacing.md
              visible: root.selectedEngine === "Kokoro" || root.selectedEngine === "Piper"
              Text { width: parent.width; text: root.selectedEngine === "Kokoro" ? (root.kokoroSupportsLanguage ? "Local speech. Download about 330–354 MB plus runtime packages. No separate AI server needed." : "Kokoro has no " + root.installLanguageName + " voice. Piper offers a local " + root.installLanguageName + " voice (about " + root.languageInfo(root.installLanguage).piper_mb + " MB).") : !root.piperSupportsLanguage ? "Piper has no working " + root.installLanguageName + " voice. Kokoro offers local " + root.installLanguageName + " voices." : "Local speech. Install Piper and a " + root.installLanguageName + " voice. Voice download about " + root.languageInfo(root.installLanguage).piper_mb + " MB plus runtime packages. Existing reader packages stay separate."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              Ui.Dropdown { id: installLanguagePicker; width: parent.width; label: "Reading language"; options: root.languageOptions; value: root.installLanguage; onChanged: { root.candidateLanguage = value; root.candidateVoice = ""; root.probeCandidate(); installLanguagePicker.value = Qt.binding(function() { return root.installLanguage }) } }
              Ui.Button { focusable: true; width: parent.width; text: root.engineLacksLanguage ? "Set up " + (root.selectedEngine === "Kokoro" ? "Piper" : "Kokoro") + " for " + root.installLanguageName + " instead" : root.selectedEngine === "Kokoro" ? (root.kokoroSelectedInstalled ? "Repair Kokoro / reader" : "Install Kokoro voice & reader") : "Install / repair Piper voice & reader"; bordered: true; onClicked: root.engineLacksLanguage ? root.switchInstallEngine() : root.selectedEngine === "Kokoro" ? root.setup() : root.request({command: "setup", engine: "piper", language: root.installLanguage, backend_only: true}) }

            }
            Ui.Dropdown { width: parent.width; visible: root.selectedEngine === "Qwen" || root.selectedEngine === "Online"; id: serverLanguagePicker; label: "Text language"; options: root.languageOptions; value: root.installLanguage; onChanged: { root.candidateLanguage = value; root.candidateVoice = ""; root.probeCandidate(); serverLanguagePicker.value = Qt.binding(function() { return root.installLanguage }) } }
            Column {
              width: parent.width; spacing: Style.spacing.md; visible: root.selectedEngine === "Qwen"
              Text { width: parent.width; text: "Qwen uses an existing llama.cpp TTS runner, two compatible models and a speaker recording. Automatic Qwen downloads are not available. Complete the checklist below; existing files are detected automatically."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              Repeater {
                model: [{key: "qwen_runner", label: "1. Speech runner", help: "Choose the llama.cpp TTS executable."}, {key: "qwen_model", label: "2. Voice model", help: "Choose the Qwen 1.7B backbone (.gguf)."}, {key: "qwen_projection", label: "3. Audio model", help: "Choose its matching audio projection (.gguf)."}, {key: "qwen_speaker", label: "4. Speaker recording", help: "Choose a clear voice recording (.wav)."}]
                delegate: Column {
                  required property var modelData
                  width: parent.width; spacing: Style.space(4)
                  Ui.PanelSectionHeader { text: modelData.label }
                  Text { width: parent.width; text: modelData.help; wrapMode: Text.Wrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                  Ui.Button { focusable: true; width: parent.width; text: root.candidatePath(modelData.key) ? "Change file… · " + root.candidatePath(modelData.key).split("/").pop() : "Choose file…"; bordered: true; onClicked: root.chooseFile(modelData.key) }
                }
              }
            }
            Column {
              width: parent.width; spacing: Style.spacing.md; visible: root.selectedEngine === "Online"
              Text { width: parent.width; text: "Connect an OpenAI-compatible speech server. Remote servers receive the text being read and may charge for speech. Localhost servers can stay on this device."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              Ui.PanelSectionHeader { text: "Server address" }
              Ui.TextField { width: parent.width; text: root.onlineEndpoint; placeholderText: "https://your-server/v1"; onTextChanged: root.onlineEndpoint = text }
              Ui.PanelSectionHeader { text: "Speech model" }
              Ui.TextField { width: parent.width; text: root.onlineModel; placeholderText: "Speech model ID"; onTextChanged: root.onlineModel = text }
              Ui.PanelSectionHeader { text: "Voice / speaker" }
              Ui.TextField { width: parent.width; text: root.onlineVoice; placeholderText: "Voice ID"; onTextChanged: root.onlineVoice = text }
              Ui.PanelSectionHeader { text: "API key / token (if required)" }
              Ui.TextField { id: providerToken; width: parent.width; password: true; placeholderText: root.state.key_ready && root.onlineEndpoint === root.config.online_endpoint ? "Existing token will be used · enter to replace" : "Enter token, or leave empty for a local server" }
              Ui.Toggle { width: parent.width; label: "Remember token on this device"; checked: root.rememberToken; onClicked: root.rememberToken = !checked }
              Text { width: parent.width; visible: root.rememberToken; text: "Saved tokens are stored in an owner-only plaintext file."; wrapMode: Text.Wrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            }
            Ui.Dropdown { width: parent.width; visible: root.selectedEngine !== "Online"; label: "Voice / speaker to test"; options: root.candidateVoices; value: root.candidateVoice || (root.candidateVoices.length ? root.candidateVoices[0].value : ""); onChanged: root.candidateVoice = value }
            Text { width: parent.width; text: root.candidateReady() ? "Voice is available. Test it through the selected audio output before activating." : "Setup needed. Install a voice or supply the required settings above."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Flow {
              width: parent.width; spacing: Style.spacing.md
              Ui.Button { focusable: true; text: "Test provider voice"; bordered: true; enabled: root.candidateReady() && !root.state.installing_kokoro && !root.state.kokoro_checking; onClicked: root.testCandidate() }
              Ui.Button { focusable: true; text: "Use provider"; bordered: true; enabled: root.candidateReady() && root.candidateVerified() && !root.state.installing_kokoro && !root.state.kokoro_checking; onClicked: root.useCandidate() }
            }
            Text { width: parent.width; text: root.message; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: root.actionError ? Theme.Color.accent : Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Text { width: parent.width; visible: root.candidateVerified(); text: "Voice test passed. Choose Use provider to activate."; wrapMode: Text.Wrap; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Ui.Button { focusable: true; width: parent.width; text: root.showAdvanced ? "▾ Advanced · files & maintenance" : "▸ Advanced · files & maintenance"; bordered: true; onClicked: root.showAdvanced = !root.showAdvanced }
            Column {
              width: parent.width; spacing: Style.spacing.md; visible: root.showAdvanced
              Column {
                width: parent.width; spacing: Style.spacing.md; visible: root.selectedEngine === "Kokoro"
                Ui.Button { focusable: true; width: parent.width; text: root.state.kokoro_checking ? "Checking model updates…" : "Check for model updates"; enabled: root.backendReady && !root.state.kokoro_checking && !root.state.installing_kokoro; onClicked: root.request({command: "check-kokoro-updates", language: root.installLanguage}) }
                Text { width: parent.width; text: ((root.state.kokoro_updates || {})[root.installLanguage] || {}).message || ""; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                Ui.Button { focusable: true; width: parent.width; text: root.state.installing_kokoro ? "Updating model…" : "Update selected Kokoro model"; visible: ((root.state.kokoro_updates || {})[root.installLanguage] || {}).available === true; enabled: !root.state.installing_kokoro && !root.state.kokoro_checking; bordered: true; onClicked: root.request({command: "update-kokoro", language: root.installLanguage}) }
                Ui.Button { focusable: true; text: "Cancel model update"; visible: root.state.installing_kokoro === true; onClicked: root.request({command: "cancel-kokoro-install"}) }
              }
              Repeater {
                model: root.selectedEngine === "Piper" ? [{key: "piper_runner", label: "Piper executable"}, {key: "piper_model", label: "Voice model (.onnx)"}, {key: "piper_config", label: "Voice configuration (.json)"}] : root.selectedEngine === "Qwen" ? [{key: "qwen_runner", label: "llama.cpp TTS executable"}, {key: "qwen_model", label: "Qwen backbone (.gguf)"}, {key: "qwen_projection", label: "Audio projection (.gguf)"}, {key: "qwen_speaker", label: "Speaker recording (.wav)"}] : []
                delegate: Column {
                  required property var modelData
                  width: parent.width; spacing: Style.space(4)
                  Ui.PanelSectionHeader { text: modelData.label }
                  Row {
                    width: parent.width; spacing: Style.spacing.md
                    Ui.TextField { width: parent.width - browseButton.width - parent.spacing; text: root.candidatePath(modelData.key); placeholderText: "Absolute file path or ~/"; onEditingFinished: root.setCandidatePath(modelData.key, text) }
                    Ui.Button { focusable: true; id: browseButton; text: "Browse…"; onClicked: root.chooseFile(modelData.key) }
                  }
                }
              }
              Column {
                width: parent.width; spacing: Style.spacing.md; visible: root.selectedEngine === "Online"
                Text { width: parent.width; text: "The server must support /v1/audio/speech with WAV output. Model discovery is available for the active connection; it may include chat models which cannot speak."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                Ui.Button { focusable: true; text: "Refresh active server models"; enabled: root.backendReady && !root.state.models_loading; onClicked: root.request({command: "online-models"}) }
                Ui.Dropdown { width: parent.width; label: "Discovered models"; options: root.state.online_models || []; value: root.onlineModel; onChanged: root.onlineModel = value }
                Ui.Button { focusable: true; text: "Clear active server token"; enabled: root.backendReady; onClicked: root.request({command: "configure-token", token: "", remember_token: false}) }
              }
            }
          }
          Text { width: parent.width; text: "Reading controls save immediately; provider setup applies with Use provider. Closing this popup leaves narration running. Focus the window you want to read."; wrapMode: Text.Wrap; color: Color.foreground; opacity: 0.65; font.family: Style.font.family; font.pixelSize: Style.font.caption }
        }
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.showManualView
          Ui.Button { focusable: true; width: parent.width; text: "← Back to Reading Controls"; bordered: true;  onClicked: root.showManualView = false }
          Repeater {
            model: [
              {title: "1. Reading Controls", body: "• First use: open Add / manage speech providers, choose Kokoro and a voice language, then Install Kokoro voice & reader. Test provider voice, then Use provider. Then Test voice or focus your text window and Read active window. Existing reader shortcuts can also be used; this plugin does not replace desktop shortcuts.\n• Pause/Resume controls playback; Read again restarts the current page.\n• Stop ends narration and reader-owned capture. Closing this popup leaves narration running."},
              {title: "2. Voice, Language & Speed", body: "• Choose the text language (50 languages) and a local voice for it. Kokoro speaks English, German, Spanish, French, Italian, Portuguese, Hindi and Chinese; Piper covers all 50.\n• Kokoro is the default local voice. Add / manage speech providers offers Kokoro and Piper installation, a Qwen file checklist, or a compatible speech server. Optional local voices appear only with their runtimes and models installed.\n• Online supports endpoint, model, voice and token configuration. Test provider voice, then Use provider. The active provider stays selected during setup.\n• Audio output chooses speakers or headphones for every provider. System default follows your desktop setting.\n• Set speed from 60% to 200%. Reading controls save immediately."},
              {title: "3. Reading & Kindle", body: "• Follow active window and page changes enables continuous reading.\n• Kindle cropping skips the toolbar and margins.\n• Automatic page turning advances Kindle after narration finishes.\n• Manual page changes stop old speech and resume when the new text settles."},
              {title: "4. Reading Area & Highlighting", body: "• Select area closes the popup so you can choose a region.\n• Reset area returns to the full active window.\n• Highlighting follows the current speech chunk and hides when another window has focus."},
              {title: "5. Troubleshooting & Privacy", body: "• No speech: verify narration is on, your text window has focus and the voice is installed.\n• Unwanted text: choose a smaller area or enable Kindle cropping.\n• OCR always runs locally. Local speech stays on this device; Online sends the recognized text to your selected provider."}
            ]
            delegate: Rectangle {
              required property var modelData
              width: parent.width
              implicitHeight: section.implicitHeight + Style.space(16)
              radius: Style.space(6)
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
              border.width: 1
              border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)
              Column {
                id: section
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(4)
                Text { width: parent.width; text: modelData.title; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Theme.Style.font.bodySmall; font.bold: true }
                Text { width: parent.width; text: modelData.body; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.foreground; opacity: 0.85; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              }
            }
          }
          Ui.Button { focusable: true; width: parent.width; text: "← Back to Reading Controls"; bordered: true;  onClicked: root.showManualView = false }
        }
      }
    }
  }
  FileDialog {
    id: filePicker
    property string settingKey: ""
    title: "Choose speech engine file"
    onAccepted: root.setCandidatePath(settingKey, decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, "")))
  }
  Timer { id: selectionDelay; interval: 300; onTriggered: root.request({command: "select-area"}) }
}
