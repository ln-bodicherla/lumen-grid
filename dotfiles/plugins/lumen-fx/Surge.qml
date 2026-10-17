import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Edge power surges: the system reacting to power and links like a ship's grid.
//   charger plugged in   two beams race from the bottom center up both screen edges,
//                        meet at the top, and the whole edge flares: POWER RESTORED
//   charger unplugged    a short amber flicker along the edge: AUX POWER
//   Wi-Fi connects       a ring pulse at the top right: UPLINK ESTABLISHED
//   Bluetooth connects   a ring pulse at the top right: DEVICE LINKED
//   omarchy-shell lumenFx surge | unplug | link "TEXT"     try them
Item {
  id: surge
  readonly property color light: Color.accent
  readonly property color amber: Color.urgent

  property bool surging: false
  property real head: 0                 // 0..1 along each half of the edge
  property real flare: 0                // whole-edge glow after the beams meet
  property bool unplugged: false
  property real flicker: 0
  property string linkText: ""
  property real linkK: 0                // 0..1 through a corner pulse
  property string bannerText: ""

  readonly property bool active: surging || flicker > 0 || linkK > 0

  function powerIn() {
    unplugged = false
    bannerText = "POWER RESTORED"
    surgeAnim.restart()
  }
  function powerOut() {
    unplugged = true
    bannerText = "AUX POWER"
    flickerAnim.restart()
  }
  function link(text) {
    linkText = text
    linkAnim.restart()
  }

  // ---- watchers ----
  property string acPath: ""
  property int acState: -1
  Process {   // find the AC adapter once
    running: true
    command: ["bash", "-c", "for p in /sys/class/power_supply/*; do [ \"$(cat $p/type 2>/dev/null)\" = Mains ] && { echo $p/online; exit; }; done"]
    stdout: StdioCollector { onStreamFinished: surge.acPath = String(text).trim() }
  }
  FileView {
    id: acFile
    path: surge.acPath
    printErrors: false
    onLoaded: {
      var on = parseInt(String(text()).trim()) === 1 ? 1 : 0
      if (surge.acState !== -1 && on !== surge.acState) { if (on) surge.powerIn(); else surge.powerOut() }
      surge.acState = on
    }
  }
  Timer { interval: 1000; repeat: true; running: surge.acPath !== ""; onTriggered: acFile.reload() }

  Process {   // Wi-Fi / network up
    running: true
    command: ["nmcli", "monitor"]
    stdout: SplitParser {
      onRead: function(line) {
        if (/: connected$/.test(line) && !/^(lo|docker|veth|virbr|br-)/.test(line)) surge.link("UPLINK ESTABLISHED")
      }
    }
  }
  Process {   // Bluetooth device connected
    running: true
    command: ["dbus-monitor", "--system", "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'"]
    property bool sawConnected: false
    stdout: SplitParser {
      onRead: function(line) {
        if (line.indexOf('string "Connected"') !== -1) parent.sawConnected = true
        else if (parent.sawConnected && line.indexOf("boolean") !== -1) {
          if (line.indexOf("boolean true") !== -1) surge.link("DEVICE LINKED")
          parent.sawConnected = false
        }
      }
    }
  }

  // ---- animations ----
  SequentialAnimation {
    id: surgeAnim
    PropertyAction { target: surge; property: "surging"; value: true }
    PropertyAction { target: surge; property: "flare"; value: 0 }
    NumberAnimation { target: surge; property: "head"; from: 0; to: 1; duration: 850; easing.type: Easing.InOutCubic }
    NumberAnimation { target: surge; property: "flare"; from: 0; to: 1; duration: 120 }
    NumberAnimation { target: surge; property: "flare"; to: 0; duration: 900; easing.type: Easing.OutCubic }
    PropertyAction { target: surge; property: "surging"; value: false }
  }
  SequentialAnimation {
    id: flickerAnim
    NumberAnimation { target: surge; property: "flicker"; to: 1; duration: 60 }
    NumberAnimation { target: surge; property: "flicker"; to: 0.2; duration: 90 }
    NumberAnimation { target: surge; property: "flicker"; to: 0.9; duration: 60 }
    NumberAnimation { target: surge; property: "flicker"; to: 0.3; duration: 120 }
    NumberAnimation { target: surge; property: "flicker"; to: 0.7; duration: 60 }
    NumberAnimation { target: surge; property: "flicker"; to: 0; duration: 700 }
  }
  NumberAnimation { id: linkAnim; target: surge; property: "linkK"; from: 0.001; to: 1; duration: 1400; easing.type: Easing.OutCubic
    onFinished: surge.linkK = 0 }

  // One beam layer along half the screen edge; the dash ends at the head.
  component BeamLayer: ShapePath {
    property var win
    property real sw: 3
    property real alpha: 1
    property color tone: surge.light
    fillColor: "transparent"
    strokeColor: Qt.rgba(tone.r, tone.g, tone.b, alpha)
    strokeWidth: sw
    capStyle: ShapePath.RoundCap
    strokeStyle: ShapePath.DashLine
    dashPattern: [win.tail / sw, (win.half + win.tail) / sw]
    dashOffset: (win.tail - surge.head * win.half) / sw
    // inset so the whole beam, glow included, stays on screen
    startX: win.w / 2; startY: win.h - 4
    PathLine { x: win.w - 4; y: win.h - 4 }
    PathLine { x: win.w - 4; y: 4 }
    PathLine { x: win.w / 2; y: 4 }
  }
  // One beam: bottom center -> right edge -> top center (mirror for the left side)
  component Run: Shape {
    id: run
    property var win
    property bool mirror: false
    anchors.fill: parent
    visible: surge.surging
    transform: Scale { origin.x: run.win.w / 2; xScale: run.mirror ? -1 : 1 }
    BeamLayer { win: run.win; sw: 22; alpha: 0.2 }
    BeamLayer { win: run.win; sw: 3; alpha: 0.85 }
    BeamLayer { win: run.win; sw: 4; tone: Qt.tint(surge.light, "#b0ffffff") }
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "lumen-surge"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}
      visible: surge.active

      readonly property real w: width
      readonly property real h: height
      readonly property real half: w / 2 + h + w / 2      // length of one side's run
      readonly property real tail: 520

      // keeps the first frame non-empty so the layer repaints
      Rectangle { width: 1; height: 1; color: Qt.rgba(0, 0, 0, 0.01) }

      // two beams: bottom center -> right edge -> top center, and its mirror
      Run { win: win }
      Run { win: win; mirror: true }

      // whole-edge flare (power in) / amber flicker (power out)
      Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 3
        border.color: surge.unplugged ? surge.amber : surge.light
        opacity: Math.max(surge.flare, surge.flicker)
        Rectangle {
          anchors.fill: parent; anchors.margins: 3
          color: "transparent"; border.width: 18
          border.color: surge.unplugged ? surge.amber : surge.light
          opacity: 0.12
        }
      }

      Decrypt {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - 70
        target: (surge.flare > 0.05 || surge.flicker > 0.05) ? surge.bannerText : ""
        duration: 420
        color: surge.unplugged ? surge.amber : surge.light
        opacity: Math.max(surge.flare, surge.flicker)
        font.family: Style.font.family
        font.pixelSize: 15
        font.bold: true
        font.letterSpacing: 6
      }

      // link pulse in the top right, under the bar's network icons
      Item {
        visible: surge.linkK > 0
        x: parent.width - 150; y: 34
        Rectangle {
          anchors.centerIn: parent
          width: 14 + 140 * surge.linkK; height: width; radius: width / 2
          color: "transparent"; border.width: 2; border.color: surge.light
          opacity: 1 - surge.linkK
        }
        Rectangle {
          anchors.centerIn: parent
          width: 8 + 70 * surge.linkK; height: width; radius: width / 2
          color: "transparent"; border.width: 1; border.color: surge.light
          opacity: 0.8 * (1 - surge.linkK)
        }
        Decrypt {
          anchors.right: parent.right
          anchors.rightMargin: -60
          y: 34
          target: surge.linkK > 0 ? surge.linkText : ""
          duration: 380
          color: surge.light
          opacity: 1 - Math.max(0, surge.linkK - 0.6) / 0.4
          font.family: Style.font.family
          font.pixelSize: 11
          font.bold: true
          font.letterSpacing: 3
        }
      }
    }
  }
}
