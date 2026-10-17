import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Disc duel: after 75 s of idle, two light discs duel over the Grid (duel.frag) on a
// click-through overlay. Any input ends it (the idle monitor flips back); it steps aside
// for the screensaver and the lock screen.
Item {
  id: duel
  property bool saverUp: false       // set by the service: Omarchy's screensaver is showing
  property real time: 0
  property real fade: 0
  readonly property bool active: idle.isIdle && !saverUp

  IdleMonitor {
    id: idle
    timeout: 75
    respectInhibitors: true
  }

  onActiveChanged: { fadeAnim.stop(); fadeAnim.to = active ? 1 : 0; fadeAnim.duration = active ? 1200 : 250; fadeAnim.start() }
  NumberAnimation { id: fadeAnim; target: duel; property: "fade" }
  Timer { interval: 33; repeat: true; running: duel.fade > 0; onTriggered: duel.time += 0.033 }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "lumen-duel"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}
      visible: duel.fade > 0

      ShaderEffect {
        anchors.fill: parent
        property real time: duel.time
        property real fade: Math.max(0.01, duel.fade)
        property size size: Qt.size(width, height)
        property color color: Color.accent
        fragmentShader: Qt.resolvedUrl("shaders/duel.frag.qsb")
      }
    }
  }
}
