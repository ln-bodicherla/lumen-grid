import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Key stats right in the bar: CPU load, memory in use and the hottest SMC temperature.
// Same icon size and color as every other bar icon. (Battery % sits by the battery icon.)
// Fixed-width slots, so changing numbers never shift the icons beside them. Updates every
// 2 s; click to open btop.
Item {
  id: root
  property var bar
  property string moduleName
  property var settings

  readonly property color light: bar ? bar.foreground : "#8ED7E6"
  readonly property color warn: bar ? bar.urgent : "#d19a66"
  readonly property string font: bar ? bar.fontFamily : "monospace"
  readonly property real size: bar ? bar.barSize : 26

  property int cpu: 0
  property int mem: 0
  property int temp: 0
  property var prev: null

  implicitWidth: row.implicitWidth + 8
  implicitHeight: size

  FileView {
    id: stat
    path: "/proc/stat"
    onLoaded: {
      var f = String(text()).split("\n")[0].trim().split(/\s+/).slice(1).map(Number)
      var idle = f[3] + (f[4] || 0), total = f.reduce(function(a, b) { return a + b }, 0)
      if (root.prev) {
        var dt = total - root.prev.total, di = idle - root.prev.idle
        root.cpu = dt > 0 ? Math.round(Math.max(0, Math.min(1, 1 - di / dt)) * 100) : 0
      }
      root.prev = { total: total, idle: idle }
    }
  }
  FileView {
    id: meminfo
    path: "/proc/meminfo"
    onLoaded: {
      var t = String(text()), total = +(t.match(/MemTotal:\s+(\d+)/) || [0, 0])[1], avail = +(t.match(/MemAvailable:\s+(\d+)/) || [0, 0])[1]
      root.mem = total ? Math.round((total - avail) / total * 100) : 0
    }
  }
  Process {   // hottest SMC sensor
    id: temps
    command: ["bash", "-c", "cat /sys/class/hwmon/hwmon*/temp*_input 2>/dev/null | sort -n | tail -1"]
    stdout: StdioCollector { onStreamFinished: root.temp = Math.round((parseInt(text) || 0) / 1000) }
  }
  Timer {
    interval: 2000; running: true; repeat: true; triggeredOnStart: true
    onTriggered: { stat.reload(); meminfo.reload(); if (!temps.running) temps.running = true }
  }

  component Stat: Row {
    property string glyph
    property string value
    property bool hot: false
    spacing: 4
    Text { text: parent.glyph; color: root.light; font.family: root.font; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
    Text {
      width: valueMetrics.width   // fixed slot
      horizontalAlignment: Text.AlignRight
      text: parent.value
      color: parent.hot ? root.warn : root.light
      font.family: root.font; font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
    }
  }
  TextMetrics { id: valueMetrics; font.family: root.font; font.pixelSize: Style.font.body; text: "100%" }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 12
    Stat { glyph: "󰻠"; value: root.cpu + "%"; hot: root.cpu >= 85 }
    Stat { glyph: "󰍛"; value: root.mem + "%"; hot: root.mem >= 90 }
    Stat { glyph: "󰔏"; value: root.temp + "°"; hot: root.temp >= 85 }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
  }
}
