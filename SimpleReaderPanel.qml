import QtQuick
import QtQuick.Controls as Controls
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
  property bool showManualView: false
  property bool loaded: false
  property string kokoroLanguage: ""
  property bool rememberToken: false
  readonly property string installLanguage: kokoroLanguage || config.language || "de"
  readonly property bool kokoroSelectedInstalled: (state.kokoro_languages || {})[installLanguage] === true
  readonly property bool enabledReader: state.enabled === true
  onShowManualViewChanged: panelScroll.contentY = 0
  function open() { controller.show(); request({command: "status"}) }
  function close() { controller.hide() }
  function toggle() { opened ? close() : open() }
  function set(key, value) {
    var changes = {}; changes[key] = value
    request({command: "configure", settings: changes})
  }
  function request(payload) {
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
      if (data.error) { message = data.error; return }
      if (!loaded) rememberToken = (data.settings || {}).remember_token === true
      state = data; message = data.provider_status || data.status || "Ready"; loaded = true
    } catch (e) { message = "Cannot read Simple Reader response." }
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
            text: "Simple Reader"
            color: Theme.Color.accent
            font.family: Theme.Style.font.family
            font.pixelSize: Theme.Style.font.title
            font.bold: true
          }
          Ui.Button {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: Style.space(24)
            text: root.showManualView ? "✕ Close Manual" : "📖 User Manual"
            fontSize: Style.font.caption
            bordered: true
            focusable: true
            selected: root.showManualView
            onClicked: root.showManualView = !root.showManualView
          }
        }
        Text { width: parent.width; text: "A little room to listen."; color: Color.foreground; opacity: 0.65; font.family: Style.font.family; font.pixelSize: Style.font.body }
        Column {
          width: parent.width
          spacing: Style.spacing.md
          visible: !root.showManualView
          Flow {
            width: parent.width
            spacing: Style.spacing.md
            Ui.Button { text: root.enabledReader ? "Stop" : "Start reader"; bordered: true; focusable: true; enabled: root.loaded && !root.state.installing_kokoro; onClicked: root.request({command: root.enabledReader ? "off" : "on"}) }
            Ui.Button { text: root.state.paused ? "Resume" : "Pause"; bordered: true; focusable: true; enabled: root.enabledReader; onClicked: root.request({command: "pause"}) }
            Ui.Button { text: "Read again"; focusable: true; enabled: root.enabledReader; onClicked: root.request({command: "read"}) }
          }
          Text { width: parent.width; text: root.message; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          Ui.PanelSeparator {}
          Text { text: "Voice & Language"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Theme.Style.font.bodySmall; font.bold: true }
          Ui.Dropdown { width: parent.width; label: "Speech provider"; options: ["Local", "Online"]; value: root.config.provider || "Local"; enabled: !root.enabledReader && !root.state.installing_kokoro; onChanged: root.set("provider", value) }
          Column {
            width: parent.width
            spacing: Style.spacing.md
            visible: root.config.provider !== "Online"
            Ui.Dropdown { width: parent.width; label: "Voice"; options: root.state.voices || []; value: root.config.voice || "kokoro-martin"; onChanged: root.set("voice", value) }
            Text { width: parent.width; text: "Only installed speech engines with their required models are listed."; wrapMode: Text.Wrap; color: Color.foreground; opacity: 0.65; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Ui.Dropdown { width: parent.width; label: "Kokoro language model"; options: [{value: "de", label: "German · Martin"}, {value: "en", label: "English / multilingual · Kokoro v1.0"}]; value: root.installLanguage; enabled: !root.state.installing_kokoro; onChanged: root.kokoroLanguage = value }
            Ui.Button { width: parent.width; text: root.state.installing_kokoro ? "Cancel Kokoro installation" : "Install Kokoro for selected language"; visible: !root.kokoroSelectedInstalled || root.state.installing_kokoro; bordered: true; focusable: true; enabled: !root.enabledReader; onClicked: root.request(root.state.installing_kokoro ? {command: "cancel-kokoro-install"} : {command: "install-kokoro", language: root.installLanguage}) }
            Text { width: parent.width; text: root.kokoroSelectedInstalled ? "Selected Kokoro language model is installed." : "Installs the selected model and voice files (about 330–354 MB), plus missing runtime dependencies."; wrapMode: Text.Wrap; color: Color.foreground; opacity: 0.65; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          }
          Column {
            width: parent.width
            spacing: Style.spacing.md
            visible: root.config.provider === "Online"
            enabled: !root.enabledReader
            Ui.PanelSectionHeader { text: "Provider endpoint" }
            Ui.TextField { width: parent.width; text: root.config.online_endpoint || "https://api.openai.com/v1"; placeholderText: "HTTPS provider base URL"; onEditingFinished: root.set("online_endpoint", text) }
            Ui.Dropdown { width: parent.width; label: "Speech model"; options: root.state.online_models || []; value: root.config.online_model || ""; onChanged: root.set("online_model", value) }
            Ui.Button { text: root.state.models_loading ? "Refreshing models…" : "Refresh models"; focusable: true; enabled: !root.state.models_loading; onClicked: root.request({command: "online-models"}) }
            Ui.PanelSectionHeader { text: "Model ID (manual entry)" }
            Ui.TextField { width: parent.width; text: root.config.online_model || ""; placeholderText: "Provider speech model ID"; onEditingFinished: root.set("online_model", text) }
            Ui.PanelSectionHeader { text: "Voice ID" }
            Ui.TextField { width: parent.width; text: root.config.online_voice || "alloy"; placeholderText: "Provider voice ID"; onEditingFinished: root.set("online_voice", text) }
            Ui.PanelSectionHeader { text: "API key or bearer token" }
            Ui.TextField { id: token; width: parent.width; password: true; placeholderText: root.state.key_ready ? "Token configured" : "Enter provider token" }
            Ui.Toggle { width: parent.width; label: "Save token locally"; checked: root.rememberToken; onClicked: root.rememberToken = !checked }
            Flow {
              width: parent.width
              spacing: Style.spacing.md
              Ui.Button { text: "Apply token"; bordered: true; focusable: true; onClicked: { root.request({command: "configure-token", token: token.text, remember_token: root.rememberToken}); token.text = "" } }
              Ui.Button { text: "Clear token"; focusable: true; onClicked: root.request({command: "configure-token", token: "", remember_token: false}) }
            }
            Text { width: parent.width; text: "Use a speech-capable model and voice from your provider. Online speech sends the text being read to that provider. Saved tokens are owner-only plaintext. The endpoint must support /v1/audio/speech with WAV output."; wrapMode: Text.Wrap; color: Color.foreground; opacity: 0.65; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          }
          Ui.Dropdown { width: parent.width; label: "Text language"; options: [{value: "de", label: "German"}, {value: "en", label: "English"}]; value: root.config.language || "de"; onChanged: root.set("language", value) }
          Ui.NumberField { label: "Reading speed (%)"; from: 60; to: 200; stepSize: 5; value: Math.round((root.config.speed || 1) * 100); onModified: root.set("speed", value / 100) }
          Ui.PanelSeparator {}
          Text { text: "Reading & Kindle"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Theme.Style.font.bodySmall; font.bold: true }
          Ui.Toggle { width: parent.width; label: "Follow active window and page changes"; checked: root.config.follow !== false; onClicked: root.set("follow", !checked) }
          Ui.Toggle { width: parent.width; label: "Skip Kindle toolbar and margins"; checked: root.config.kindle_crop !== false; onClicked: root.set("kindle_crop", !checked) }
          Ui.Toggle { width: parent.width; label: "Turn Kindle pages after reading"; checked: root.config.auto_page_turn !== false; onClicked: root.set("auto_page_turn", !checked) }
          Ui.Toggle { width: parent.width; label: "Highlight the passage being read"; checked: root.config.highlight !== false; onClicked: root.set("highlight", !checked) }
          Ui.PanelSeparator {}
          Text { text: "Reading Area"; color: Theme.Color.accent; font.family: Style.font.family; font.pixelSize: Theme.Style.font.bodySmall; font.bold: true }
          Text { width: parent.width; text: root.state.custom_area ? "Custom reading area selected" : root.config.kindle_area ? "Saved Kindle reading area" : "Full active window"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          Flow {
            width: parent.width
            spacing: Style.spacing.md
            Ui.Button { text: "Select area…"; bordered: true; focusable: true; onClicked: { root.close(); selectionDelay.start() } }
            Ui.Button { text: "Reset area"; bordered: true; focusable: true; onClicked: root.request({command: "clear-area"}) }
          }
          Text { width: parent.width; text: "Changes save immediately. Closing this popup leaves narration running. Focus the window you want to read."; wrapMode: Text.Wrap; color: Color.foreground; opacity: 0.65; font.family: Style.font.family; font.pixelSize: Style.font.caption }
        }
        Column {
          width: parent.width
          spacing: Style.space(10)
          visible: root.showManualView
          Ui.Button { width: parent.width; text: "← Back to Reading Controls"; bordered: true; focusable: true; onClicked: root.showManualView = false }
          Repeater {
            model: [
              {title: "1. Reading Controls", body: "• Focus your text window and click Start reader. Existing reader shortcuts can also be used; this plugin does not replace desktop shortcuts.\n• Pause/Resume controls playback; Read again restarts the current page.\n• Stop ends narration and reader-owned capture. Closing this popup leaves narration running."},
              {title: "2. Voice, Language & Speed", body: "• Choose a local voice and German or English text language.\n• Kokoro is the default neural engine. Choose a Kokoro language model and install it if missing. Optional local voices appear only with their runtimes and models installed.\n• Online supports endpoint, model, voice and token configuration. Apply token before starting authenticated speech.\n• Set speed from 60% to 200%. Changes save immediately."},
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
          Ui.Button { width: parent.width; text: "← Back to Reading Controls"; bordered: true; focusable: true; onClicked: root.showManualView = false }
        }
      }
    }
  }
  Timer { id: selectionDelay; interval: 300; onTriggered: root.request({command: "select-area"}) }
}
