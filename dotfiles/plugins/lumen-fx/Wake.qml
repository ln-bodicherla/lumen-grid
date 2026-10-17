import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// "Systems online": a 2-second HUD boot-up when you unlock or the Mac wakes.
// A scan line sweeps the screen, the machine's name decrypts in the middle inside an
// expanding identity ring, and readouts (power, network, time, user) type in at
// the corners, then everything fades. Click-through; nothing to dismiss.
//   omarchy-shell lumenFx wake     play it now
Item {
  id: wake
  readonly property color light: Color.accent
  property bool playing: false
  property real t: 0                    // ms into the sequence
  readonly property int total: 2300
  property var info: ({})               // readouts gathered at wake time
  property double lastPlay: 0

  function play() {
    if (Date.now() - lastPlay < 3000) return   // unlock right after resume: play once
    lastPlay = Date.now()
    if (!gather.running) gather.running = true
  }
  function start() {
    t = 0
    playing = true
    clock.restart()
  }

  Process {
    id: gather
    command: ["bash", "-c",
      "b=$(for p in /sys/class/power_supply/*; do [ \"$(cat $p/type 2>/dev/null)\" = Battery ] && { echo $p; break; }; done); " +
      "ssid=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1==\"yes\"{print $2; exit}'); " +
      "[ -z \"$ssid\" ] && ssid=$(iwctl station wlan0 show 2>/dev/null | awk '/Connected network/{ $1=$2=\"\"; sub(/^ +/,\"\"); print }'); " +
      "ip=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4; exit}'); " +
      "printf '{\"host\":\"%s\",\"user\":\"%s\",\"bat\":\"%s\",\"batst\":\"%s\",\"ssid\":\"%s\",\"ip\":\"%s\",\"theme\":\"%s\",\"kernel\":\"%s\"}' " +
      "\"$(hostname)\" \"$USER\" \"$(cat $b/capacity 2>/dev/null)\" \"$(cat $b/status 2>/dev/null)\" \"$ssid\" \"${ip%/*}\" " +
      "\"$(cat ~/.local/state/omarchy/current/theme.name 2>/dev/null)\" \"$(uname -r)\""]
    stdout: StdioCollector {
      onStreamFinished: {
        try { wake.info = JSON.parse(text) } catch (e) { wake.info = {} }
        wake.start()
      }
    }
  }

  Timer {
    id: clock
    interval: 16; repeat: true; running: wake.playing
    onTriggered: { wake.t += 16; if (wake.t >= wake.total) wake.playing = false }
  }

  // resume from sleep (logind PrepareForSleep false); unlock calls lumenFx wake directly
  Process {
    command: ["dbus-monitor", "--system", "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"]
    running: true
    stdout: SplitParser {
      onRead: function(line) { if (line.indexOf("boolean false") !== -1) wake.play() }
    }
  }

  // progress 0..1 of the window [from, to] at time tt (pass wake.t so bindings follow the clock)
  function phase(tt, from, to) { return Math.max(0, Math.min(1, (tt - from) / (to - from))) }
  readonly property real fadeOut: 1 - phase(t, 1750, 2300)
  readonly property string themeLabel: {
    var th = String(info.theme || "")
    return th === "lumen-overload" ? "OVERLOAD" : (th === "lumen-redline" ? "REDLINE" : (th === "lumen-program" ? "PROGRAM" : th.toUpperCase()))
  }

  component Readout: Column {
    id: ro
    property var lines: []
    property int startAt: 0
    property int align: Text.AlignLeft
    spacing: 4
    opacity: wake.phase(wake.t, ro.startAt, ro.startAt + 150) * wake.fadeOut
    Repeater {
      model: ro.lines
      Decrypt {
        required property string modelData
        required property int index
        width: 420
        horizontalAlignment: ro.align
        target: wake.playing && wake.t >= ro.startAt + index * 120 ? modelData : ""
        duration: 380
        color: index === 0 ? wake.light : Qt.rgba(wake.light.r, wake.light.g, wake.light.b, 0.75)
        font.family: Style.font.family
        font.pixelSize: index === 0 ? 13 : 12
        font.bold: index === 0
        font.letterSpacing: 1.5
      }
    }
  }

  component Bracket: Shape {
    property bool flipX: false
    property bool flipY: false
    width: 26; height: 26
    transform: Scale { origin.x: 13; origin.y: 13; xScale: flipX ? -1 : 1; yScale: flipY ? -1 : 1 }
    ShapePath {
      fillColor: "transparent"; strokeColor: wake.light; strokeWidth: 2
      startX: 0; startY: 26
      PathLine { x: 0; y: 0 }
      PathLine { x: 26; y: 0 }
    }
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "lumen-wake"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}
      visible: wake.playing

      Item {
        id: hud
        anchors.fill: parent

        // veil: darkens the desktop for the boot-up, then lifts
        Rectangle {
          anchors.fill: parent
          color: "black"
          // on from the first frame: a layer whose first frame is fully transparent never repaints
          opacity: 0.55 * (1 - wake.phase(wake.t, 1500, 2300))
        }

        // scan line sweeping down, with a faint grid left behind it
        Rectangle {
          width: parent.width; height: 2
          y: parent.height * wake.phase(wake.t, 60, 620)
          color: Qt.tint(wake.light, "#80ffffff")
          opacity: 1 - wake.phase(wake.t, 560, 700)
          Rectangle { anchors.centerIn: parent; width: parent.width; height: 24; color: wake.light; opacity: 0.12 }
        }
        Repeater {
          model: Math.ceil(hud.height / 48)
          Rectangle {
            required property int index
            y: index * 48; width: hud.width; height: 1
            color: wake.light
            visible: y < hud.height * wake.phase(wake.t, 60, 620)
            opacity: 0.07 * (1 - wake.phase(wake.t, 900, 1400))
          }
        }

        // identity ring opening around the name
        Item {
          anchors.centerIn: parent
          width: 1; height: 1
          readonly property real k: wake.phase(wake.t, 250, 900)
          Rectangle {
            anchors.centerIn: parent
            width: 120 + 300 * parent.k; height: width; radius: width / 2
            color: "transparent"; border.width: 2; border.color: wake.light
            opacity: (0.2 + 0.8 * (1 - parent.k)) * wake.fadeOut
          }
          Rectangle {
            anchors.centerIn: parent
            width: 340; height: width; radius: width / 2
            color: "transparent"; border.width: 1; border.color: wake.light
            opacity: 0.35 * wake.phase(wake.t, 500, 800) * wake.fadeOut
            RotationAnimation on rotation { from: 0; to: 360; duration: 6000; loops: Animation.Infinite; running: wake.playing }
            Rectangle { x: parent.width / 2 - 3; y: -3; width: 6; height: 6; radius: 3; color: wake.light }
          }
        }

        Column {
          anchors.centerIn: parent
          spacing: 10
          opacity: wake.phase(wake.t, 300, 450) * wake.fadeOut
          Decrypt {
            anchors.horizontalCenter: parent.horizontalCenter
            target: wake.playing && wake.t > 300 ? String(wake.info.host || "GRID").toUpperCase() : ""
            duration: 700
            color: wake.light
            font.family: Style.font.family
            font.pixelSize: 30
            font.bold: true
            font.letterSpacing: 6
            style: Text.Outline
            styleColor: Qt.rgba(wake.light.r, wake.light.g, wake.light.b, 0.35)
          }
          Decrypt {
            anchors.horizontalCenter: parent.horizontalCenter
            target: wake.playing && wake.t > 800 ? "◆  SYSTEMS ONLINE  ◆" : ""
            duration: 500
            color: Qt.tint(wake.light, "#60ffffff")
            font.family: Style.font.family
            font.pixelSize: 13
            font.letterSpacing: 4
          }
        }

        // corner readouts with brackets
        Bracket { x: 28; y: 48; opacity: wake.phase(wake.t, 200, 300) * wake.fadeOut }
        Bracket { x: parent.width - 54; y: 48; flipX: true; opacity: wake.phase(wake.t, 250, 350) * wake.fadeOut }
        Bracket { x: 28; y: parent.height - 54; flipY: true; opacity: wake.phase(wake.t, 300, 400) * wake.fadeOut }
        Bracket { x: parent.width - 54; y: parent.height - 54; flipX: true; flipY: true; opacity: wake.phase(wake.t, 350, 450) * wake.fadeOut }

        Readout {
          x: 64; y: 58
          startAt: 450
          lines: ["POWER", (wake.info.bat ? wake.info.bat + "%" : "--") + "  ·  " + String(wake.info.batst || "").toUpperCase(),
                  "CORE  " + String(wake.info.kernel || "")]
        }
        Readout {
          x: parent.width - 484; y: 58
          startAt: 600
          align: Text.AlignRight
          lines: ["GRID TIME", Qt.formatDateTime(new Date(), "hh:mm:ss  ·  ddd dd MMM yyyy").toUpperCase(), "SECTOR  " + wake.themeLabel]
        }
        Readout {
          x: 64; y: parent.height - 120
          startAt: 750
          lines: ["LINK", wake.info.ssid ? "WIFI  " + String(wake.info.ssid).toUpperCase() : "NO UPLINK", wake.info.ip ? "ADDR  " + wake.info.ip : ""]
        }
        Readout {
          x: parent.width - 484; y: parent.height - 120
          startAt: 900
          align: Text.AlignRight
          lines: ["USER", "IDENTITY  " + String(wake.info.user || "").toUpperCase(), "ACCESS  GRANTED"]
        }
      }
    }
  }
}
