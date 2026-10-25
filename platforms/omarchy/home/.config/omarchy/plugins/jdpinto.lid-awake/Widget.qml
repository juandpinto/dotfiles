import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Visible only while lid-awake.service runs; clicking turns it off.
// `lid-awake on|off` refreshes this over IPC; the timer catches anything else,
// such as the service failing.
BarWidget {
  id: root
  moduleName: "jdpinto.lid-awake"

  readonly property string command: Quickshell.env("HOME") + "/.local/bin/lid-awake"
  property bool on: false

  visible: on
  implicitWidth: on ? button.implicitWidth : 0
  implicitHeight: on ? button.implicitHeight : 0

  function refresh() {
    if (!probe.running) probe.running = true
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌢"
    tooltipText: "Lid awake: keeps running when closed. Click to turn off."
    fontSize: Style.font.caption
    horizontalMargin: 5
    verticalPadding: 5
    fixedWidth: root.vertical ? -1 : Style.bar.statusSlot
    fixedHeight: root.vertical ? Style.bar.statusSlot : -1
    onPressed: function() {
      if (!turnOff.running) turnOff.running = true
    }
  }

  Process {
    id: probe
    command: ["systemctl", "--user", "is-active", "--quiet", "lid-awake.service"]
    onExited: function(code) { root.on = code === 0 }
  }

  Process {
    id: turnOff
    command: [root.command, "off"]
    onExited: root.refresh()
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: "jdpinto.lid-awake"

    function refresh(): void {
      root.broadcast("refresh")
    }
  }

  Component.onCompleted: refresh()
}
