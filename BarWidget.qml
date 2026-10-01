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
    tooltipText: "Simple Reader · " + (panel.state.status || "Off") + "\nClick for reading controls"
    onPressed: panel.toggle()
  }
}
