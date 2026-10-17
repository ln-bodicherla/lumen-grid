import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Status at a glance, Lumen style: only what's ON shows, all at the same size and color.
//   Do not disturb · screen recording · night light · stay awake
// Click an icon to switch it off. Replaces Omarchy's dimmed indicator group.
Item {
  id: root
  property var bar
  property string moduleName
  property var settings

  readonly property color light: bar ? bar.foreground : "#8ED7E6"
  property var flags: ({})

  readonly property var items: [
    { key: "dnd", glyph: "󰂛", tip: "Do not disturb · click to turn off", off: "omarchy toggle notification silencing" },
    { key: "rec", glyph: "󰻂", tip: "Recording · click to stop", off: "omarchy-capture-screenrecording --stop-recording" },
    { key: "night", glyph: "󰔎", tip: "Night light · click to turn off", off: "omarchy toggle nightlight" },
    { key: "awake", glyph: "󰅶", tip: "Stay awake · click to turn off", off: "omarchy toggle idle" }
  ]

  implicitWidth: row.implicitWidth > 0 ? row.implicitWidth + 8 : 0
  implicitHeight: bar ? bar.barSize : 26

  Process {
    id: poll
    command: ["bash", "-c",
      "dnd=$(python3 -c 'import json,os; print(str(json.load(open(os.path.expanduser(\"~/.local/state/omarchy/notifications.json\"))).get(\"dnd\", False)).lower())' 2>/dev/null || echo false); " +
      "omarchy-capture-screenrecording-process >/dev/null 2>&1 && rec=true || rec=false; " +
      "night=$(omarchy toggle nightlight --status 2>/dev/null | grep -q '\"enabled\":true' && echo true || echo false); " +
      "awake=$(omarchy toggle idle status 2>/dev/null | grep -q '\"enabled\":true' && echo true || echo false); " +
      "printf '{\"dnd\":%s,\"rec\":%s,\"night\":%s,\"awake\":%s}' $dnd $rec $night $awake"]
    stdout: StdioCollector { onStreamFinished: { try { root.flags = JSON.parse(text) } catch (e) {} } }
  }
  Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!poll.running) poll.running = true }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 12
    Repeater {
      model: root.items
      Text {
        required property var modelData
        visible: root.flags[modelData.key] === true
        text: modelData.glyph
        color: root.light
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
        MouseArea {
          anchors.fill: parent
          anchors.margins: -4
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { Quickshell.execDetached(["bash", "-lc", parent.modelData.off]); poll.running = true }
          onEntered: if (root.bar) root.bar.showTooltip(parent, parent.modelData.tip)
          onExited: if (root.bar) root.bar.hideTooltip(parent)
        }
      }
    }
  }
}
