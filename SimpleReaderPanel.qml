import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import "native/Commons"
import "native/Commons" as Commons
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
  property bool showTranslationGroup: false
  property bool showTranslation: false
  property bool rememberTranslatorToken: false
  property bool showVoiceGroup: false
  property bool showReadingGroup: false
  // Desktop notifications appear behind this popup, so warnings and errors are repeated here.
  property double dismissedNotice: 0  // ids are millisecond timestamps (beyond int range)
  readonly property var latestNotice: {
    var list = state.notices || []
    return list.length && list[list.length - 1].id > dismissedNotice ? list[list.length - 1] : null
  }
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
    var settings = {provider: "Local"}
    settings[speechLanguageKey] = installLanguage
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
  // With translation on, voices are set up for the target language.
  readonly property string speechLanguageKey: config.translate_to ? "translate_to" : "language"
  readonly property bool translating: !!config.translate_to
  readonly property var translateOptions: [{value: "", label: "Off · read in the text language"}].concat(languageOptions.filter(function(o) { return o.value !== root.config.language }))
  readonly property string translatorPreset: {
    var presets = state.translator_endpoints || {}
    for (var key in presets) if (presets[key] === config.translator_endpoint) return key
    return "Custom"
  }
  readonly property string installLanguageName: languageInfo(installLanguage).label.split(" · ")[0]
  readonly property string activeVoiceLabel: config.provider === "Online" ? (config.online_voice || "No voice") : voiceLabel(config.voice)
  readonly property string providerSummary: "Active: " + (activeEngine === "Online" ? "Speech server · " + (config.online_endpoint || "") : activeEngine + " · Local") + "\n" + activeVoiceLabel + " · " + languageInfo(config.language).label + (translating ? " → " + languageInfo(config.translate_to).label : "") + " · " + (!(backendReady && voiceReady) ? "Setup needed" : state.can_start === false ? "Not ready" : "Ready to read")
  function engineForVoice(voice) {
    var id = voice || ""
    return id.indexOf("piper") >= 0 || id.indexOf("fast") >= 0 ? "Piper" : id.indexOf("qwen") >= 0 ? "Qwen" : "Kokoro"
  }
  function voiceLabel(id) {
    var voices = state.voices || []
    for (var i = 0; i < voices.length; i++) if (voices[i].value === id) return voices[i].label
    return "No voice yet"
  }
  function providerOptions() {
    return [{value: "Kokoro", label: "Kokoro · local · " + (languageInfo(installLanguage).kokoro ? "recommended" : "no " + languageInfo(installLanguage).label.split(" · ")[0] + " voice")},
      {value: "Piper", label: "Piper · local · " + ((Object.keys(state.piper_installations || {}).length || (state.voices || []).some(function(v) { return v.engine === "piper" })) ? "installed" : "install available")},
      {value: "Qwen", label: "Qwen · local · " + ((state.voices || []).some(function(v) { return v.engine === "qwen" }) ? "installed" : "requires existing TTS files")},
      {value: "Online", label: "Speech server · online or localhost"}]
  }
  function manageProvider(engine) {
    engineChoice = engine || activeEngine
    candidateLanguage = config.translate_to || config.language || "en"
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
  }
  function candidateSettings() {
    if (selectedEngine === "Online") {
      var online = {provider: "Online", online_endpoint: onlineEndpoint, online_model: onlineModel, online_voice: onlineVoice}
      online[speechLanguageKey] = installLanguage
      return online
    }
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

  readonly property string installLanguage: candidateLanguage || config.translate_to || config.language || "en"
  readonly property bool kokoroSelectedInstalled: (state.kokoro_languages || {})[installLanguage] === true
  readonly property bool enabledReader: state.enabled === true
  onShowManualViewChanged: panelScroll.contentY = 0
  onShowProvidersChanged: panelScroll.contentY = 0
  // Backspace on a subpage returns to the reading controls (text fields keep it).
  function goBack() {
    if (showManualView) showManualView = false
    else if (showProviders) closeProviders()
    else if (showTranslation) showTranslation = false
    else return false
    content.forceActiveFocus()
    return true
  }
  onShowTranslationChanged: panelScroll.contentY = 0
  // The single next step shown when reading cannot start yet.
  property bool showMoreFixes: false
  readonly property var failedChecks: (state.checks || []).filter(function(c) { return !c.ok })
  readonly property var setupStep: ({problem: "Screen Narrator needs a one-time setup: the reader, text recognition and a " + languageInfo(installLanguage).label.split(" · ")[0] + " voice.",
                                     fixes: [{label: "Set up now", command: "setup", args: {language: installLanguage}}]})
  readonly property var nextStep: loaded && !backendReady && !setupBusy ? setupStep : (failedChecks.length ? failedChecks[0] : null)
  onNextStepChanged: showMoreFixes = false
  readonly property bool installBusy: setupBusy || state.installing_kokoro === true || state.installing_translator === true
  readonly property string installMessage: setupBusy ? (state.setup_message || "Setting up…") : (state.provider_status || state.translation_status || "Installing…")
  // "Set up automatically": install what the chosen language and provider still need.
  function failedCheck(prefix) {
    var list = state.checks || []
    for (var i = 0; i < list.length; i++) if (!list[i].ok && list[i].label.indexOf(prefix) === 0) return list[i]
    return null
  }
  readonly property bool canInstallVoices: activeEngine === "Kokoro" || activeEngine === "Piper"
  function voiceNeed() {
    var check = failedCheck("Voice")
    return check && canInstallVoices ? check : null
  }
  // The local engine guided setup uses for a language: the chosen one if it has a voice, else the other.
  function installEngine(code) {
    var info = languageInfo(code)
    if (activeEngine === "Piper" && info.piper) return "Piper"
    return info.kokoro ? "Kokoro" : "Piper"
  }
  function voiceInstallText(check, code) {
    var size = (check.fixes[0].label.match(/\(([^)]*)\)/) || ["", ""])[1]
    return "a " + languageInfo(code).label.split(" · ")[0] + " " + installEngine(code) + " voice" + (size ? " (" + size + ")" : "")
  }
  readonly property bool voiceBlocked: failedCheck("Voice") !== null && !canInstallVoices
  readonly property string voiceBlockedText: "Voices for " + (activeEngine === "Online" ? "a speech server" : activeEngine) + " cannot be installed automatically. Open Voice → Add / manage speech providers, or choose Kokoro or Piper there."
  function setupPlan(voiceLanguage, ocrLanguage, needOcr, needVoice) {
    var args = {language: voiceLanguage, ocr_language: ocrLanguage}
    if (needVoice && installEngine(voiceLanguage) === "Piper") args.engine = "piper"
    if (!needVoice) args.backend_only = true
    return args
  }
  readonly property string readingNeeds: {
    var parts = []
    var ocr = failedCheck("Text recognition"), voice = translating ? null : voiceNeed()
    if (ocr) parts.push(languageInfo(config.language).label.split(" · ")[0] + " text recognition")
    if (voice) parts.push(voiceInstallText(voice, config.language))
    return parts.join(" and ")
  }
  function setupReading() {
    var needVoice = !translating && voiceNeed() !== null
    request(Object.assign({command: "setup"}, setupPlan(config.language, config.language, failedCheck("Text recognition") !== null, needVoice)))
  }
  function defaultTranslationTarget() {
    var desktop = state.desktop_language || "en"
    if (desktop !== config.language) return desktop
    return config.language === "en" ? "de" : "en"
  }
  function needsOfflineTranslator() {
    var check = failedCheck("Translation")
    return check !== null && check.fixes.length > 0 && check.fixes[0].command === "install-translator"
  }
  readonly property string translationNeeds: {
    if (!translating) return ""
    var parts = [], voice = voiceNeed()
    if (voice) parts.push(voiceInstallText(voice, config.translate_to))
    if (needsOfflineTranslator()) parts.push("the offline translator (about 1.4 GB, non-commercial use)")
    return parts.join(" and ")
  }
  // A translation problem that installing cannot solve (e.g. the chosen server is not running).
  readonly property string translationProblem: {
    var check = translating ? failedCheck("Translation") : null
    return check && !needsOfflineTranslator() ? check.problem + " Start it, or choose the offline translator in Translation settings." : ""
  }
  function setupTranslation() {
    var needVoice = voiceNeed() !== null
    if (!needVoice && needsOfflineTranslator()) { request({command: "install-translator"}); return }
    var args = setupPlan(config.translate_to, config.language, false, needVoice)
    if (needsOfflineTranslator()) args.translator = "nllb"
    request(Object.assign({command: "setup"}, args))
  }
  // Explicit paste (Ctrl+V) for text fields: the bridge reads the clipboard bounded.
  property var pasteTarget: null
  function pasteInto(field) { pasteTarget = field; request({command: "paste"}) }
  function applyFix(fix) {
    if (fix.command) { request(Object.assign({command: fix.command}, fix.args || {})); return }
    if (fix.panel === "providers") manageProvider(activeEngine)
    else if (fix.panel === "translation") showTranslation = true
    else if (fix.settings) request({command: "configure", settings: fix.settings})
  }
  function closeProviders() {
    showProviders = false
    engineChoice = ""
    candidateVoice = ""
  }
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
      if (currentRequest.command === "paste") {
        if (pasteTarget && data.clipboard) pasteTarget.insert(data.clipboard)
        pasteTarget = null
        return
      }
      if (currentRequest.command === "use-provider") {
        providerToken.text = ""
        showProviders = false
        engineChoice = ""
      }
      if (!loaded) rememberToken = (data.settings || {}).remember_token === true
      if (!loaded) rememberTranslatorToken = (data.settings || {}).remember_translator_token === true
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
  // A layer-shell panel that takes the keyboard when it opens; an xdg-popup
  // (PopupCard) never receives keys, so text fields and list filters stayed dead.
  Ui.KeyboardPanel {
    id: popup
    focusTarget: content
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
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Backspace && root.goBack()) event.accepted = true
        }
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
        Text { width: parent.width; text: "Read screen text, PDFs and Kindle pages aloud."; color: Commons.Color.foreground; opacity: 0.65; font.family: Style.font.family; font.pixelSize: Style.font.body }
        Rectangle {
          width: parent.width
          visible: root.latestNotice !== null
          height: visible ? noticeText.implicitHeight + Style.space(16) : 0
          radius: Style.cornerRadius
          color: Qt.rgba(Theme.Color.accent.r, Theme.Color.accent.g, Theme.Color.accent.b, 0.18)
          border.color: Theme.Color.accent
          border.width: Math.max(1, Style.space(2))
          Text {
            id: noticeText
            anchors.left: parent.left; anchors.right: noticeClose.left; anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10); anchors.rightMargin: Style.space(6)
            text: root.latestNotice ? (root.latestNotice.level === "error" ? "⚠  " : "ⓘ  ") + root.latestNotice.title + "\n" + root.latestNotice.text : ""
            textFormat: Text.PlainText; wrapMode: Text.Wrap
            color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption
          }
          Ui.Button {
            id: noticeClose
            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Style.space(4)
            focusable: true; text: "✕"; fontSize: Style.font.caption; tooltipText: "Dismiss"
            onClicked: root.dismissedNotice = root.latestNotice ? root.latestNotice.id : root.dismissedNotice
          }
        }
        Column {
          width: parent.width
          spacing: Style.spacing.md
          visible: !root.showManualView
          Column {
            width: parent.width
            spacing: Style.spacing.md
            visible: !root.showProviders && !root.showTranslation
            Rectangle {
              width: parent.width
              height: activeSummary.implicitHeight + Style.space(20)
              radius: Style.cornerRadius
              color: Qt.rgba(Theme.Color.accent.r, Theme.Color.accent.g, Theme.Color.accent.b, 0.12)
              border.color: Theme.Color.accent
              Text { id: activeSummary; anchors.fill: parent; anchors.margins: Style.space(10); text: root.providerSummary; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
            }
            Row {
              width: parent.width; spacing: Style.spacing.md
              Ui.Button { focusable: true; width: (parent.width - 2 * Style.spacing.md) / 3; text: "▶  Start"; tooltipText: "Start reading the focused window (or right-click the bar icon)"; bordered: true; selected: !root.enabledReader && enabled && root.state.can_start !== false; enabled: root.loaded && !root.setupBusy && !root.state.kokoro_checking && !root.state.installing_kokoro && root.backendReady && !root.enabledReader; onClicked: root.request({command: "on"}) }
              Ui.Button { focusable: true; width: (parent.width - 2 * Style.spacing.md) / 3; text: root.state.paused ? "▶  Resume" : "❚❚  Pause"; bordered: true; enabled: root.enabledReader; onClicked: root.request({command: "pause"}) }
              Ui.Button { focusable: true; width: (parent.width - 2 * Style.spacing.md) / 3; text: "■  Stop"; tooltipText: "Stop reading (or right-click the bar icon)"; bordered: true; selected: root.enabledReader; enabled: root.enabledReader; onClicked: root.request({command: "off"}) }
            }
            Rectangle {
              id: nextStepCard
              width: parent.width
              visible: !root.enabledReader && (root.nextStep !== null || root.installBusy)
              height: visible ? nextStepColumn.implicitHeight + Style.space(20) : 0
              radius: Style.cornerRadius
              color: Qt.rgba(Theme.Color.accent.r, Theme.Color.accent.g, Theme.Color.accent.b, 0.10)
              border.color: Theme.Color.accent
              Column {
                id: nextStepColumn
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Style.space(10)
                spacing: Style.spacing.md
                Text { width: parent.width; text: root.installBusy ? "Installing…" : "Not ready yet" + (root.failedChecks.length > 1 ? " · step 1 of " + root.failedChecks.length : ""); color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
                Text { width: parent.width; text: root.installBusy ? root.installMessage : (root.nextStep ? root.nextStep.problem : ""); textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body }
                Ui.Button { focusable: true; width: parent.width; visible: !root.installBusy && root.nextStep !== null; selected: true; bordered: true; text: root.nextStep && root.nextStep.fixes.length ? root.nextStep.fixes[0].label : ""; onClicked: root.applyFix(root.nextStep.fixes[0]) }
                Ui.Button { focusable: true; visible: root.installBusy && root.setupBusy; enabled: root.state.setup_phase !== "packages"; bordered: true; text: "Cancel"; onClicked: root.request({command: "cancel-setup"}) }
                Text { visible: !root.installBusy && root.nextStep !== null && root.nextStep.fixes.length > 1; text: root.showMoreFixes ? "▾ Other options" : "▸ Other options"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.showMoreFixes = !root.showMoreFixes } }
                Flow {
                  width: parent.width; spacing: Style.spacing.md; visible: root.showMoreFixes && !root.installBusy && root.nextStep !== null
                  Repeater {
                    model: root.nextStep ? root.nextStep.fixes.slice(1) : []
                    Ui.Button { required property var modelData; focusable: true; bordered: true; text: modelData.label; fontSize: Style.font.caption; onClicked: root.applyFix(modelData) }
                  }
                }
              }
            }
            Text { width: parent.width; visible: !root.enabledReader && root.nextStep === null && !root.installBusy && root.state.can_start === true; text: "✓ Ready. Focus the window you want to read, then press ▶ Start."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; opacity: 0.8; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Text { width: parent.width; text: "Status: " + (root.message === "Off" ? "not reading" : root.message); textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Rectangle {
              width: parent.width
              height: readingGroup.implicitHeight + Style.space(20)
              radius: Style.cornerRadius
              color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.04)
              border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.14)
              Column {
                id: readingGroup
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Style.space(10)
                spacing: Style.spacing.md
                Item {
                  width: parent.width; height: Math.max(readingGroupTitle.implicitHeight, Style.space(22))
                  Row {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(8)
                    Text { text: "󰗚"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.body + Style.space(4); anchors.verticalCenter: parent.verticalCenter }
                    Text { id: readingGroupTitle; text: "Reading"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "· " + root.languageInfo(root.config.language).label.split(" · ")[0] + " · " + Math.round((root.config.speed || 1) * 100) + " %"; color: Commons.Color.foreground; opacity: 0.7; elide: Text.ElideRight; width: parent.width - Style.space(150); font.family: Style.font.family; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                  }
                  Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: root.showReadingGroup ? "▾" : "▸"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.body }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.showReadingGroup = !root.showReadingGroup }
                }
                Column {
                  width: parent.width; spacing: Style.spacing.md; visible: root.showReadingGroup
                  Ui.SearchableDropdown { placeholderText: "Type to filter languages…"; width: parent.width; id: textLanguagePicker; label: "Text language"; enabled: root.backendReady && !root.setupBusy && !root.enabledReader; options: root.languageOptions; value: root.config.language || "en"; onChanged: { root.set("language", value); textLanguagePicker.value = Qt.binding(function() { return root.config.language || "en" }) } }
                  Ui.NumberField { label: "Reading speed (%)"; enabled: root.backendReady && !root.setupBusy; from: 60; to: 200; stepSize: 5; value: Math.round((root.config.speed || 1) * 100); onModified: root.set("speed", value / 100) }
                  Ui.Button { focusable: true; width: parent.width; bordered: true; selected: enabled; text: "󰁨  Set up automatically"; tooltipText: "Install what reading in this language still needs"; visible: root.readingNeeds !== ""; enabled: root.loaded && !root.enabledReader && !root.installBusy; onClicked: root.setupReading() }
                  Text { width: parent.width; text: root.readingNeeds !== "" ? "Installs " + root.readingNeeds + "." : (!root.translating && root.voiceBlocked ? root.voiceBlockedText : "✓ Everything for reading " + root.languageInfo(root.config.language).label.split(" · ")[0] + " is installed."); textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; opacity: 0.8; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                  Flow {
                    width: parent.width; spacing: Style.spacing.md
                    Ui.Button { focusable: true; text: "Read again"; bordered: true; enabled: root.enabledReader && !root.state.testing_voice; onClicked: root.request({command: "read"}) }
                  }
                  Ui.Button { focusable: true; width: parent.width; text: root.showReadingOptions ? "▾ Reading options" : "▸ Reading options"; bordered: true; onClicked: root.showReadingOptions = !root.showReadingOptions }
                  Column {
                    width: parent.width; spacing: Style.spacing.md; visible: root.showReadingOptions
                  Text { text: "Reading, PDF & Kindle"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Theme.Style.font.bodySmall; font.bold: true }
                  Ui.Toggle { width: parent.width; enabled: root.backendReady && !root.setupBusy; label: "Follow active window and page changes"; checked: root.config.follow !== false; onClicked: root.set("follow", !checked) }
                  Ui.Toggle { width: parent.width; enabled: root.backendReady && !root.setupBusy; label: "Skip Kindle toolbar and margins"; checked: root.config.kindle_crop !== false; onClicked: root.set("kindle_crop", !checked) }
                  Ui.Toggle { width: parent.width; enabled: root.backendReady && !root.setupBusy; label: "Read only the page in PDF viewers"; checked: root.config.pdf_page_area !== false; onClicked: root.set("pdf_page_area", !checked) }
                  Ui.Toggle { width: parent.width; enabled: root.backendReady && !root.setupBusy; label: "Turn Kindle and PDF pages after reading"; checked: root.config.auto_page_turn !== false; onClicked: root.set("auto_page_turn", !checked) }
                  Ui.Toggle { width: parent.width; enabled: root.backendReady && !root.setupBusy; label: "Highlight the passage being read"; checked: root.config.highlight !== false; onClicked: root.set("highlight", !checked) }
                  Ui.PanelSeparator {}
                  Text { text: "Reading Area"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Theme.Style.font.bodySmall; font.bold: true }
                  Text { width: parent.width; text: root.state.custom_area ? "Custom reading area selected" : root.config.kindle_area ? "Saved Kindle reading area" : "Full active window"; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                  Flow {
                    width: parent.width
                    spacing: Style.spacing.md
                    Ui.Button { focusable: true; text: "Select area…"; enabled: root.backendReady && !root.setupBusy; bordered: true;  onClicked: { root.close(); selectionDelay.start() } }
                    Ui.Button { focusable: true; text: "Reset area"; enabled: root.backendReady && !root.setupBusy; bordered: true;  onClicked: root.request({command: "clear-area"}) }
                  }
                  }
                }
              }
            }
            Rectangle {
              width: parent.width
              height: voiceGroup.implicitHeight + Style.space(20)
              radius: Style.cornerRadius
              color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.04)
              border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.14)
              Column {
                id: voiceGroup
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Style.space(10)
                spacing: Style.spacing.md
                Item {
                  width: parent.width; height: Math.max(voiceGroupTitle.implicitHeight, Style.space(22))
                  Row {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(8)
                    Text { text: "󰕾"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.body + Style.space(4); anchors.verticalCenter: parent.verticalCenter }
                    Text { id: voiceGroupTitle; text: "Voice"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "· " + root.activeVoiceLabel + (root.activeVoiceLabel.indexOf(root.activeEngine) >= 0 ? "" : " · " + root.activeEngine); color: Commons.Color.foreground; opacity: 0.7; elide: Text.ElideRight; width: parent.width - Style.space(150); font.family: Style.font.family; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                  }
                  Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: root.showVoiceGroup ? "▾" : "▸"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.body }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.showVoiceGroup = !root.showVoiceGroup }
                }
                Column {
                  width: parent.width; spacing: Style.spacing.md; visible: root.showVoiceGroup
                  Ui.Dropdown { id: activeProviderPicker; width: parent.width; label: "Speech provider"; options: root.providerOptions(); value: root.activeEngine; enabled: !root.enabledReader && !root.setupBusy; onChanged: { root.manageProvider(value); activeProviderPicker.value = Qt.binding(function() { return root.activeEngine }) } }
                  Ui.Dropdown { width: parent.width; label: "Voice / speaker"; visible: root.activeEngine !== "Online"; options: root.activeVoices; value: root.config.voice || ""; enabled: root.backendReady && !root.setupBusy && !root.enabledReader; onChanged: root.request({command: "configure", settings: {provider: "Local", voice: value}}) }
                  Column {
                    width: parent.width; spacing: Style.space(4); visible: root.activeEngine === "Online"
                    Ui.PanelSectionHeader { text: "Voice / speaker" }
                    Ui.TextField { pasteHandler: root.pasteInto; width: parent.width; text: root.config.online_voice || ""; enabled: root.backendReady && !root.setupBusy && !root.enabledReader; placeholderText: "Speech server voice ID"; onEditingFinished: root.set("online_voice", text) }
                  }
                  Ui.Dropdown { width: parent.width; label: "Audio output · speakers / headphones"; options: root.state.audio_outputs || [{value: "auto", label: "System default"}]; value: root.config.audio_output || "auto"; enabled: root.backendReady && !root.setupBusy; onChanged: root.set("audio_output", value) }
                  Text { width: parent.width; visible: (root.config.audio_output || "auto") !== "auto" && !(root.state.audio_outputs || []).some(function(v) { return v.value === root.config.audio_output }); text: "Selected audio output is disconnected. Reconnect it or choose System default."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                  Flow {
                    width: parent.width; spacing: Style.spacing.md
                    Ui.Button { focusable: true; text: "Test voice"; bordered: true; enabled: root.backendReady && root.voiceReady && !root.enabledReader && !root.setupBusy && !root.state.installing_kokoro && !root.state.kokoro_checking; onClicked: root.request({command: "test-voice"}) }
                  }
                  Ui.Button { focusable: true; width: parent.width; text: "Add / manage speech providers…"; bordered: true; enabled: !root.enabledReader && !root.setupBusy; onClicked: root.showProviders ? root.showProviders = false : root.manageProvider(root.activeEngine) }
                }
              }
            }
            Rectangle {
              width: parent.width
              height: translationGroup.implicitHeight + Style.space(20)
              radius: Style.cornerRadius
              color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.04)
              border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.14)
              Column {
                id: translationGroup
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Style.space(10)
                spacing: Style.spacing.md
                Item {
                  width: parent.width; height: Math.max(translationGroupTitle.implicitHeight, Style.space(22))
                  Row {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(8)
                    Text { text: "󰗊"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.body + Style.space(4); anchors.verticalCenter: parent.verticalCenter }
                    Text { id: translationGroupTitle; text: "Translation"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "· " + (root.translating ? "→ " + root.languageInfo(root.config.translate_to).label.split(" · ")[0] : "off"); color: Commons.Color.foreground; opacity: 0.7; elide: Text.ElideRight; width: parent.width - Style.space(150); font.family: Style.font.family; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                  }
                  Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: root.showTranslationGroup ? "▾" : "▸"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.body }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.showTranslationGroup = !root.showTranslationGroup }
                }
                Column {
                  width: parent.width; spacing: Style.spacing.md; visible: root.showTranslationGroup
                  Ui.Toggle { width: parent.width; label: "Translate before reading"; enabled: root.backendReady && !root.setupBusy && !root.enabledReader; checked: root.translating; onClicked: root.set("translate_to", root.translating ? "" : root.defaultTranslationTarget()) }
                  Column {
                    width: parent.width; spacing: Style.spacing.md; visible: root.translating
                    Ui.SearchableDropdown { id: groupTranslateTo; placeholderText: "Type to filter languages…"; width: parent.width; label: "Read " + root.languageInfo(root.config.language).label.split(" · ")[0] + " text aloud in"; enabled: !root.enabledReader; options: root.languageOptions.filter(function(o) { return o.value !== root.config.language }); value: root.config.translate_to || ""; onChanged: { root.set("translate_to", value); groupTranslateTo.value = Qt.binding(function() { return root.config.translate_to || "" }) } }
                    Text { width: parent.width; text: "Translator: " + (root.config.translator === "nllb" ? "offline NLLB-200 on this computer" : (root.config.translator_model ? root.config.translator_model + " · " + root.config.translator_endpoint : "not chosen yet")); textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; opacity: 0.8; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                    Ui.Button { focusable: true; width: parent.width; bordered: true; selected: enabled; text: "󰁨  Set up automatically"; tooltipText: "Install what translating into this language still needs"; visible: root.translationNeeds !== ""; enabled: root.loaded && !root.enabledReader && !root.installBusy; onClicked: root.setupTranslation() }
                    Text { width: parent.width; text: root.translationProblem !== "" ? root.translationProblem : (root.translationNeeds !== "" ? "Installs " + root.translationNeeds + "." : root.voiceBlocked ? root.voiceBlockedText : "✓ Everything for reading in " + root.languageInfo(root.config.translate_to).label.split(" · ")[0] + " is installed."); textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; opacity: 0.8; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                    Ui.Button { focusable: true; bordered: true; text: "Translation settings…"; fontSize: Style.font.caption; onClicked: root.showTranslation = true }
                  }
                }
              }
            }
          }
          Ui.Button { focusable: true; width: parent.width; visible: root.showProviders; text: "← Back to Reading Controls · ⌫"; bordered: true; onClicked: root.closeProviders() }
          Text { width: parent.width; visible: root.showProviders && root.setupBusy; text: root.state.setup_message || "Setting up…"; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          Ui.Button { focusable: true; text: "Cancel setup"; visible: root.showProviders && root.setupBusy; enabled: root.state.setup_phase !== "packages"; bordered: true; onClicked: root.request({command: "cancel-setup"}) }
          Column {
            id: providerSettings
            width: parent.width
            spacing: Style.spacing.md
            visible: root.showProviders
            enabled: !root.enabledReader && !root.setupBusy
            Text { text: "Set up speech provider"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
            Text { width: parent.width; text: "1. Choose and set up  ·  2. Test voice  ·  3. Use provider\nYour active provider stays selected until you choose Use provider."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Ui.Dropdown { id: setupProviderPicker; width: parent.width; label: "Provider to set up"; options: root.providerOptions(); value: root.selectedEngine; onChanged: { root.engineChoice = value; root.candidateVoice = ""; root.showAdvanced = false; root.probeCandidate(); setupProviderPicker.value = Qt.binding(function() { return root.selectedEngine }) } }
            Ui.Button { focusable: true; width: parent.width; text: "Set up reader runtime"; visible: !root.backendReady && root.selectedEngine !== "Kokoro" && root.selectedEngine !== "Piper"; bordered: true; onClicked: root.request({command: "setup", language: root.installLanguage, backend_only: true}) }
            Column {
              width: parent.width; spacing: Style.spacing.md
              visible: root.selectedEngine === "Kokoro" || root.selectedEngine === "Piper"
              Text { width: parent.width; text: root.selectedEngine === "Kokoro" ? (root.kokoroSupportsLanguage ? "Local speech. Download about 330–354 MB plus runtime packages" + (root.installLanguage === "ja" ? " and a Japanese pronunciation dictionary (about 270 MB)" : "") + ". No separate AI server needed." : "Kokoro has no " + root.installLanguageName + " voice. Piper offers a local " + root.installLanguageName + " voice (about " + root.languageInfo(root.installLanguage).piper_mb + " MB).") : !root.piperSupportsLanguage ? "Piper has no working " + root.installLanguageName + " voice. Kokoro offers local " + root.installLanguageName + " voices." : "Local speech. Install Piper and a " + root.installLanguageName + " voice. Voice download about " + root.languageInfo(root.installLanguage).piper_mb + " MB plus runtime packages. Existing reader packages stay separate."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              Ui.SearchableDropdown { placeholderText: "Type to filter languages…"; id: installLanguagePicker; width: parent.width; label: root.translating ? "Spoken language (translation target)" : "Reading language"; options: root.languageOptions; value: root.installLanguage; onChanged: { root.candidateLanguage = value; root.candidateVoice = ""; root.probeCandidate(); installLanguagePicker.value = Qt.binding(function() { return root.installLanguage }) } }
              Ui.Button { focusable: true; width: parent.width; text: root.engineLacksLanguage ? "Set up " + (root.selectedEngine === "Kokoro" ? "Piper" : "Kokoro") + " for " + root.installLanguageName + " instead" : root.selectedEngine === "Kokoro" ? (root.kokoroSelectedInstalled ? "Repair Kokoro / reader" : "Install Kokoro voice & reader") : "Install / repair Piper voice & reader"; bordered: true; onClicked: root.engineLacksLanguage ? root.switchInstallEngine() : root.selectedEngine === "Kokoro" ? root.setup() : root.request({command: "setup", engine: "piper", language: root.installLanguage, backend_only: true}) }

            }
            Ui.SearchableDropdown { placeholderText: "Type to filter languages…"; width: parent.width; visible: root.selectedEngine === "Qwen" || root.selectedEngine === "Online"; id: serverLanguagePicker; label: "Text language"; options: root.languageOptions; value: root.installLanguage; onChanged: { root.candidateLanguage = value; root.candidateVoice = ""; root.probeCandidate(); serverLanguagePicker.value = Qt.binding(function() { return root.installLanguage }) } }
            Column {
              width: parent.width; spacing: Style.spacing.md; visible: root.selectedEngine === "Qwen"
              Text { width: parent.width; text: "Qwen uses an existing llama.cpp TTS runner, two compatible models and a speaker recording. Automatic Qwen downloads are not available. Complete the checklist below; existing files are detected automatically."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              Repeater {
                model: [{key: "qwen_runner", label: "1. Speech runner", help: "Choose the llama.cpp TTS executable."}, {key: "qwen_model", label: "2. Voice model", help: "Choose the Qwen 1.7B backbone (.gguf)."}, {key: "qwen_projection", label: "3. Audio model", help: "Choose its matching audio projection (.gguf)."}, {key: "qwen_speaker", label: "4. Speaker recording", help: "Choose a clear voice recording (.wav)."}]
                delegate: Column {
                  required property var modelData
                  width: parent.width; spacing: Style.space(4)
                  Ui.PanelSectionHeader { text: modelData.label }
                  Text { width: parent.width; text: modelData.help; wrapMode: Text.Wrap; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                  Ui.Button { focusable: true; width: parent.width; text: root.candidatePath(modelData.key) ? "Change file… · " + root.candidatePath(modelData.key).split("/").pop() : "Choose file…"; bordered: true; onClicked: root.chooseFile(modelData.key) }
                }
              }
            }
            Column {
              width: parent.width; spacing: Style.spacing.md; visible: root.selectedEngine === "Online"
              Text { width: parent.width; text: "Connect an OpenAI-compatible speech server. Remote servers receive the text being read and may charge for speech. Localhost servers can stay on this device."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              Ui.PanelSectionHeader { text: "Server address" }
              Ui.TextField { pasteHandler: root.pasteInto; width: parent.width; text: root.onlineEndpoint; placeholderText: "https://your-server/v1"; onTextChanged: root.onlineEndpoint = text }
              Ui.PanelSectionHeader { text: "Speech model" }
              Ui.TextField { pasteHandler: root.pasteInto; width: parent.width; text: root.onlineModel; placeholderText: "Speech model ID"; onTextChanged: root.onlineModel = text }
              Ui.PanelSectionHeader { text: "Voice / speaker" }
              Ui.TextField { pasteHandler: root.pasteInto; width: parent.width; text: root.onlineVoice; placeholderText: "Voice ID"; onTextChanged: root.onlineVoice = text }
              Ui.PanelSectionHeader { text: "API key / token (if required)" }
              Ui.TextField { pasteHandler: root.pasteInto; id: providerToken; width: parent.width; password: true; placeholderText: root.state.key_ready && root.onlineEndpoint === root.config.online_endpoint ? "Existing token will be used · enter to replace" : "Enter token, or leave empty for a local server" }
              Ui.Toggle { width: parent.width; label: "Remember token on this device"; checked: root.rememberToken; onClicked: root.rememberToken = !checked }
              Text { width: parent.width; visible: root.rememberToken; text: "Saved tokens are stored in an owner-only plaintext file."; wrapMode: Text.Wrap; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            }
            Ui.Dropdown { width: parent.width; visible: root.selectedEngine !== "Online"; label: "Voice / speaker to test"; options: root.candidateVoices; value: root.candidateVoice || (root.candidateVoices.length ? root.candidateVoices[0].value : ""); onChanged: root.candidateVoice = value }
            Text { width: parent.width; text: root.candidateReady() ? "Voice is available. Test it through the selected audio output before activating." : "Setup needed. Install a voice or supply the required settings above."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Flow {
              width: parent.width; spacing: Style.spacing.md
              Ui.Button { focusable: true; text: "Test provider voice"; bordered: true; enabled: root.candidateReady() && !root.state.installing_kokoro && !root.state.kokoro_checking; onClicked: root.testCandidate() }
              Ui.Button { focusable: true; text: "Use provider"; bordered: true; enabled: root.candidateReady() && root.candidateVerified() && !root.state.installing_kokoro && !root.state.kokoro_checking; onClicked: root.useCandidate() }
            }
            Text { width: parent.width; text: "Status: " + (root.message === "Off" ? "not reading" : root.message); textFormat: Text.PlainText; wrapMode: Text.Wrap; color: root.actionError ? Theme.Color.accent : Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Text { width: parent.width; visible: root.candidateVerified(); text: "Voice test passed. Choose Use provider to activate."; wrapMode: Text.Wrap; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Ui.Button { focusable: true; width: parent.width; text: root.showAdvanced ? "▾ Advanced · files & maintenance" : "▸ Advanced · files & maintenance"; bordered: true; onClicked: root.showAdvanced = !root.showAdvanced }
            Column {
              width: parent.width; spacing: Style.spacing.md; visible: root.showAdvanced
              Column {
                width: parent.width; spacing: Style.spacing.md; visible: root.selectedEngine === "Kokoro"
                Ui.Button { focusable: true; width: parent.width; text: root.state.kokoro_checking ? "Checking model updates…" : "Check for model updates"; enabled: root.backendReady && !root.state.kokoro_checking && !root.state.installing_kokoro; onClicked: root.request({command: "check-kokoro-updates", language: root.installLanguage}) }
                Text { width: parent.width; text: ((root.state.kokoro_updates || {})[root.installLanguage] || {}).message || ""; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
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
                    Ui.TextField { pasteHandler: root.pasteInto; width: parent.width - browseButton.width - parent.spacing; text: root.candidatePath(modelData.key); placeholderText: "Absolute file path or ~/"; onEditingFinished: root.setCandidatePath(modelData.key, text) }
                    Ui.Button { focusable: true; id: browseButton; text: "Browse…"; onClicked: root.chooseFile(modelData.key) }
                  }
                }
              }
              Column {
                width: parent.width; spacing: Style.spacing.md; visible: root.selectedEngine === "Online"
                Text { width: parent.width; text: "The server must support /v1/audio/speech with WAV output. Model discovery is available for the active connection; it may include chat models which cannot speak."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                Ui.Button { focusable: true; text: "Refresh active server models"; enabled: root.backendReady && !root.state.models_loading; onClicked: root.request({command: "online-models"}) }
                Ui.SearchableDropdown { placeholderText: "Type to filter models…"; width: parent.width; label: "Discovered models"; options: root.state.online_models || []; value: root.onlineModel; onChanged: root.onlineModel = value }
                Ui.Button { focusable: true; text: "Clear active server token"; enabled: root.backendReady; onClicked: root.request({command: "configure-token", token: "", remember_token: false}) }
              }
            }
          }
          Ui.Button { focusable: true; width: parent.width; visible: root.showProviders; text: "← Back to Reading Controls · ⌫"; bordered: true; onClicked: root.closeProviders() }
          Ui.Button { focusable: true; width: parent.width; visible: root.showTranslation; text: "← Back to Reading Controls · ⌫"; bordered: true; onClicked: root.showTranslation = false }
          Column {
            width: parent.width; spacing: Style.spacing.md; visible: root.showTranslation
            enabled: root.backendReady && !root.setupBusy
            Text { text: "Translation"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
            Text { width: parent.width; text: "Read the text in one language and hear it in another. Off by default. Translation needs a translator: a local LLM server (llama.cpp, LM Studio, Ollama) or the offline NLLB-200 model. User Manual → Translation explains the setup."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Ui.SearchableDropdown { placeholderText: "Type to filter languages…"; id: translateToPicker; width: parent.width; label: "Speak in"; enabled: !root.enabledReader; options: root.translateOptions; value: root.config.translate_to || ""; onChanged: { root.set("translate_to", value); translateToPicker.value = Qt.binding(function() { return root.config.translate_to || "" }) } }
            Ui.Dropdown { id: translatorPicker; width: parent.width; label: "Translator"; enabled: !root.enabledReader; options: [{value: "llm", label: "LLM server · llama.cpp, LM Studio, Ollama"}, {value: "nllb", label: "Offline NLLB-200 · 1.4 GB · non-commercial license"}]; value: root.config.translator || "llm"; onChanged: { root.set("translator", value); translatorPicker.value = Qt.binding(function() { return root.config.translator || "llm" }) } }
            Column {
              width: parent.width; spacing: Style.spacing.md; visible: (root.config.translator || "llm") === "llm"
              Ui.Dropdown { id: presetPicker; width: parent.width; label: "Server"; enabled: !root.enabledReader; options: Object.keys(root.state.translator_endpoints || {}).map(function(k) { return {value: k, label: k + " · " + root.state.translator_endpoints[k]} }).concat([{value: "Custom", label: "Custom · any OpenAI-compatible server"}]); value: root.translatorPreset; onChanged: { if (value !== "Custom") root.set("translator_endpoint", root.state.translator_endpoints[value]); presetPicker.value = Qt.binding(function() { return root.translatorPreset }) } }
              Ui.TextField { pasteHandler: root.pasteInto; width: parent.width; text: root.config.translator_endpoint || ""; enabled: !root.enabledReader; placeholderText: "http://127.0.0.1:8080/v1 or https://server/v1"; onEditingFinished: if (text !== root.config.translator_endpoint) root.set("translator_endpoint", text) }
              Ui.TextField { pasteHandler: root.pasteInto; width: parent.width; text: root.config.translator_model || ""; enabled: !root.enabledReader; placeholderText: "Model name, e.g. as shown by Refresh models"; onEditingFinished: if (text !== root.config.translator_model) root.set("translator_model", text) }
              Ui.SearchableDropdown { placeholderText: "Type to filter models…"; id: translatorModelPicker; width: parent.width; visible: (root.state.translator_models || []).length > 0; label: "Models on the server"; enabled: !root.enabledReader; options: (root.state.translator_models || []).map(function(m) { return {value: m, label: m} }); value: root.config.translator_model || ""; onChanged: { root.set("translator_model", value); translatorModelPicker.value = Qt.binding(function() { return root.config.translator_model || "" }) } }
              Flow {
                width: parent.width; spacing: Style.spacing.md
                Ui.Button { focusable: true; text: root.state.translator_models_loading ? "Refreshing…" : "Refresh models"; bordered: true; enabled: !root.state.translator_models_loading; onClicked: root.request({command: "translator-models"}) }
              }
              Ui.TextField { pasteHandler: root.pasteInto; id: translatorToken; width: parent.width; password: true; enabled: !root.enabledReader; placeholderText: root.state.translator_key_ready ? "Token in use · enter to replace" : "Token, only for servers that need one" }
              Ui.Toggle { width: parent.width; label: "Remember token on this device"; checked: root.rememberTranslatorToken; onClicked: root.rememberTranslatorToken = !checked }
              Flow {
                width: parent.width; spacing: Style.spacing.md
                Ui.Button { focusable: true; text: "Apply token"; bordered: true; enabled: !root.enabledReader && translatorToken.text.length > 0; onClicked: { root.request({command: "configure-translator-token", token: translatorToken.text, remember_token: root.rememberTranslatorToken}); translatorToken.text = "" } }
                Ui.Button { focusable: true; text: "Clear token"; bordered: true; enabled: !root.enabledReader && root.state.translator_key_ready === true; onClicked: root.request({command: "configure-translator-token", token: "", remember_token: false}) }
              }
              Text { width: parent.width; text: "Remote HTTPS servers receive the recognized text. llama.cpp, LM Studio and Ollama on this computer keep it local."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            }
            Column {
              width: parent.width; spacing: Style.spacing.md; visible: root.config.translator === "nllb"
              Text { width: parent.width; text: root.state.nllb_ready ? "Offline translator installed. It runs on this computer; the first page takes a few seconds to load the model." : "Downloads NLLB-200 1.3B (about 1.4 GB, checksum-verified) and its runtime. The model license (CC-BY-NC 4.0) allows non-commercial use only."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              Flow {
                width: parent.width; spacing: Style.spacing.md
                Ui.Button { focusable: true; text: root.state.nllb_ready ? "Repair offline translator" : "Install offline translator"; bordered: true; enabled: !root.enabledReader && !root.state.installing_translator; onClicked: root.request({command: "install-translator"}) }
                Ui.Button { focusable: true; text: "Cancel"; bordered: true; visible: root.state.installing_translator === true; onClicked: root.request({command: "cancel-translator-install"}) }
              }
            }
            Ui.Button { focusable: true; text: root.state.translation_testing ? "Testing…" : "Test translation"; bordered: true; enabled: root.translating && !root.enabledReader && !root.state.translation_testing && !root.state.installing_translator; onClicked: root.request({command: "test-translation"}) }
            Text { width: parent.width; visible: !!root.state.translation_status; text: root.state.translation_status || ""; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Text { width: parent.width; visible: root.translating && !root.voiceReady; text: "No voice for " + root.languageInfo(root.config.translate_to).label.split(" · ")[0] + " yet. Use Add / manage speech providers… to install one."; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          }
          Ui.Button { focusable: true; width: parent.width; visible: root.showTranslation; text: "← Back to Reading Controls · ⌫"; bordered: true; onClicked: root.showTranslation = false }
          Text { width: parent.width; text: "Reading controls save immediately; provider setup applies with Use provider. Closing this popup leaves narration running. Focus the window you want to read."; wrapMode: Text.Wrap; color: Commons.Color.foreground; opacity: 0.65; font.family: Style.font.family; font.pixelSize: Style.font.caption }
        }
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.showManualView
          Ui.Button { focusable: true; width: parent.width; text: "← Back to Reading Controls · ⌫"; bordered: true;  onClicked: root.showManualView = false }
          Repeater {
            model: [
              {title: "1. Reading Controls", body: "• ▶ Start, ❚❚ Pause and ■ Stop sit right under the summary. Right-click the bar icon to start or stop without opening the popup; the icon is green while reading.\n• First use: open Add / manage speech providers, choose Kokoro and a voice language, then Install Kokoro voice & reader. Test provider voice, then Use provider. Then Test voice or focus your text window and Start reading. Existing reader shortcuts can also be used; this plugin does not replace desktop shortcuts.\n• Pause/Resume controls playback; Read again restarts the current page.\n• Stop ends narration and reader-owned capture. Closing this popup leaves narration running.\n• On a subpage (provider setup, translation, this manual) Backspace returns to the reading controls; Esc closes the popup."},
              {title: "2. Voice, Language & Speed", body: "• Choose the text language (51 languages) and a local voice for it. Kokoro speaks English, German, Spanish, French, Italian, Portuguese, Hindi, Japanese and Chinese; Piper covers all except Japanese.\n• Kokoro is the default local voice. Add / manage speech providers offers Kokoro and Piper installation, a Qwen file checklist, or a compatible speech server. Optional local voices appear only with their runtimes and models installed.\n• Online supports endpoint, model, voice and token configuration. Test provider voice, then Use provider. The active provider stays selected during setup.\n• Audio output chooses speakers or headphones for every provider. System default follows your desktop setting.\n• Set speed from 60% to 200%. Reading controls save immediately."},
              {title: "3. Reading, PDF & Kindle", body: "• Follow active window and page changes enables continuous reading.\n• Kindle cropping skips the toolbar and margins.\n• In a PDF viewer (Evince, Papers) only the page is read: no toolbar, thumbnails or page numbers.\n• Automatic page turning advances Kindle and PDF pages after narration finishes and stops at the end of the document.\n• Manual page changes stop old speech and resume when the new text settles."},
              {title: "4. Reading Area & Highlighting", body: "• Select area closes the popup so you can choose a region.\n• Reset area returns to the full active window.\n• Highlighting follows the current speech chunk and hides when another window has focus."},
              {title: "5. Translation (optional)", body: "• Off by default. Turn it on under Translation → Speak in: the reader recognizes the text language and speaks the chosen language.\n• Set up a voice for the spoken language first: Add / manage speech providers… then uses that language.\n• Translator A — local LLM server (best quality, needs a GPU or patience):\n  – llama.cpp: install it (sudo pacman -S llama-cpp, or a GPU build from the llama.cpp releases), download an instruct GGUF model such as Gemma, Qwen or Llama, start it with  llama-server -m model.gguf --port 8080  and choose Server: llama.cpp.\n  – LM Studio: load a chat model, open Developer → Start server (port 1234), choose Server: LM Studio.\n  – Ollama: ollama pull gemma3 (or another chat model), keep ollama serve running, choose Server: Ollama.\n  – Refresh models lists the server's models; pick a chat/instruct model. Tokens are only for servers that require one.\n• Translator B — offline NLLB-200: Install offline translator downloads about 1.4 GB once. No server needed; runs on the CPU. License CC-BY-NC 4.0: non-commercial use only.\n• Test translation translates a sample sentence and shows the result without speaking.\n• Highlighting marks the original sentence while its translation is spoken. Remote HTTPS servers receive the recognized text."},
              {title: "6. Troubleshooting & Privacy", body: "• No speech: verify narration is on, your text window has focus and the voice is installed.\n• Unwanted text: choose a smaller area or enable Kindle cropping.\n• OCR always runs locally. Local speech stays on this device; Online sends the recognized text to your selected provider."}
            ]
            delegate: Rectangle {
              required property var modelData
              width: parent.width
              implicitHeight: section.implicitHeight + Style.space(16)
              radius: Style.space(6)
              color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.05)
              border.width: 1
              border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.15)
              Column {
                id: section
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(4)
                Text { width: parent.width; text: modelData.title; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Theme.Style.font.bodySmall; font.bold: true }
                Text { width: parent.width; text: modelData.body; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Commons.Color.foreground; opacity: 0.85; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              }
            }
          }
          Ui.Button { focusable: true; width: parent.width; text: "← Back to Reading Controls · ⌫"; bordered: true;  onClicked: root.showManualView = false }
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
