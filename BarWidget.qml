import QtQuick
import qs.Ui as Ui

Ui.BarWidget {
  id: root
  moduleName: "ubruckhaus.simple-reader"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  readonly property bool opened: panel.opened
  readonly property bool popoutSwitchClosing: panel.popoutSwitchClosing
  function open() { panel.open() }
  function close() { panel.close() }
  function closeForPopoutSwitch() { panel.closeForPopoutSwitch() }
  SimpleReaderPanel { id: panel; bar: root.bar; anchorItem: button; hostWidget: root }
  Ui.BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf025"
    active: panel.state.enabled === true
    tooltipText: "Screen Narrator · " + (panel.state.status || "Off") + "\n" + panel.providerSummary + "\nClick for reading controls"
    onPressed: panel.toggle()
  }
}
