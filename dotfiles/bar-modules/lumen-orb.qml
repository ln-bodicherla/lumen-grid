import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Claude Code status: a still icon in the bar (no motion), same size and color as the rest.
//   light disc            a Claude Code session is working
//   hourglass                a session is waiting for you
//   hidden                   idle
// Sessions report their state through Claude Code hooks (~/.local/bin/lumen-agent-state).
Item {
  id: root
  property var bar
  property string moduleName
  property var settings

  property string state: "idle"
  readonly property bool active: state !== "idle"
  readonly property bool waiting: state === "wait"
  readonly property color light: bar ? bar.foreground : "#8ED7E6"
  readonly property real size: Style.font.body

  visible: active
  implicitWidth: active ? size + 10 : 0
  implicitHeight: bar ? bar.barSize : 26

  Process {
    id: poll
    command: [Quickshell.env("HOME") + "/.local/bin/lumen-agent-state", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.state = String(text || "").trim() || "idle"
    }
  }
  Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: poll.running = true }

  // light disc while working, hourglass while waiting; same size and color as every bar icon
  Text {
    anchors.centerIn: parent
    text: root.waiting ? "󰔟" : "󰻂"
    color: root.light
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onEntered: if (root.bar) root.bar.showTooltip(root, root.waiting ? "Claude Code needs you" : "Claude Code is working")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
