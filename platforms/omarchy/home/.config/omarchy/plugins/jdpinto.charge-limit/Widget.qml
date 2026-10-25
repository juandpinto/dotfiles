import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Reminder while the battery charge limit is below 100% (`omarchy battery
// charge limit 80`). Clicking opens a terminal that sets it back to 100%,
// which asks for the sudo password. Polled, because Omarchy's command has no
// way to notify the bar.
BarWidget {
  id: root
  moduleName: "jdpinto.charge-limit"

  readonly property string thresholdPath: "/sys/class/power_supply/macsmc-battery/charge_control_end_threshold"
  property int limit: 100
  readonly property bool on: limit < 100

  visible: on
  implicitWidth: on ? button.implicitWidth : 0
  implicitHeight: on ? button.implicitHeight : 0

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱈏"
    tooltipText: "Charge limit " + root.limit + "%. Click to charge to 100%."
    fontSize: Style.font.caption
    horizontalMargin: 5
    verticalPadding: 5
    fixedWidth: root.vertical ? -1 : Style.bar.statusSlot
    fixedHeight: root.vertical ? Style.bar.statusSlot : -1
    onPressed: function() {
      if (!raise.running) raise.running = true
    }
  }

  Process {
    id: probe
    command: ["cat", root.thresholdPath]
    stdout: StdioCollector {
      onStreamFinished: {
        var value = parseInt(text, 10)
        root.limit = isNaN(value) ? 100 : value
      }
    }
  }

  Process {
    id: raise
    command: ["omarchy-launch-floating-terminal-with-presentation", "omarchy battery charge limit 100"]
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!probe.running) probe.running = true
  }
}
