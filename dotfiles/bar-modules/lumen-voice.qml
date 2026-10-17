import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

// Lumen voice glow: while you dictate (Voxtype) or record the screen, a mic appears
// in the bar and glows with your voice: a halo brightens and light rings ripple
// out with the mic level. While Voxtype transcribes, the mic breathes slowly.
// Inspired by Voice Glow from libraries.dev (MIT).
Item {
  id: root
  property var bar
  property string moduleName
  property var settings

  property string dictation: "idle"     // idle | recording | transcribing (from Voxtype)
  property bool screenRecording: false
  readonly property bool listening: dictation === "recording" || screenRecording
  readonly property bool active: listening || dictation === "transcribing"

  readonly property color light: bar ? bar.foreground : "#8ED7E6"
  readonly property real size: bar ? bar.barSize : 26

  // Mic level, 0..1: fast attack, slow release, on a perceptual (square-root) scale.
  property real level: 0
  readonly property real target: listening ? Math.min(1, Math.sqrt(Math.max(0, peak.peak)) * 1.6) : 0
  onTargetChanged: if (target > level) level = target
  Timer {
    interval: 33; repeat: true; running: root.level > 0.001
    onTriggered: root.level = Math.max(root.target, root.level * 0.86)
  }

  visible: active || fade.running
  implicitWidth: active ? size + 6 : 0
  implicitHeight: size
  opacity: active ? 1 : 0
  Behavior on opacity { NumberAnimation { id: fade; duration: 250 } }

  PwObjectTracker { objects: [Pipewire.defaultAudioSource] }
  PwNodePeakMonitor {
    id: peak
    node: Pipewire.defaultAudioSource
    enabled: root.listening
  }

  Process {
    command: ["omarchy-voxtype-status"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var d = JSON.parse(line)
          root.dictation = String(d.alt || d.class || "idle")
        } catch (e) {}
      }
    }
  }

  Process {
    id: recProc
    command: ["omarchy-capture-screenrecording-process"]
    onExited: function(code) { root.screenRecording = code === 0 }
  }
  Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!recProc.running) recProc.running = true }

  // halo
  Rectangle {
    anchors.centerIn: parent
    width: root.size * (0.55 + 0.35 * root.level); height: width; radius: width / 2
    color: root.light
    opacity: root.listening ? 0.08 + 0.32 * root.level : 0
  }

  // light rings rippling out with the voice
  Repeater {
    model: 3
    Rectangle {
      required property int index
      anchors.centerIn: parent
      width: root.size * (0.5 + (index + 1) * 0.12 * (0.4 + root.level)); height: width; radius: width / 2
      color: "transparent"
      border.width: 1
      border.color: root.light
      opacity: root.listening ? (0.15 + 0.75 * root.level) * (1 - index * 0.3) : 0
    }
  }

  Text {
    id: mic
    anchors.centerIn: parent
    text: "󰍬"
    color: root.light
    font.family: root.bar ? root.bar.fontFamily : "JetBrainsMono Nerd Font"
    font.pixelSize: Math.round(root.size * 0.5)
    style: Text.Outline
    styleColor: Qt.rgba(root.light.r, root.light.g, root.light.b, 0.25 + 0.5 * root.level)
  }

  // transcribing: the mic breathes
  SequentialAnimation {
    running: root.dictation === "transcribing"
    loops: Animation.Infinite
    onStopped: mic.opacity = 1
    NumberAnimation { target: mic; property: "opacity"; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
    NumberAnimation { target: mic; property: "opacity"; to: 1; duration: 700; easing.type: Easing.InOutSine }
  }
}
