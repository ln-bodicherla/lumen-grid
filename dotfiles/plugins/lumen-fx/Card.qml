import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

// Workspace switcher on SUPER+TAB, held like macOS's Cmd+Tab:
//   SUPER+TAB         the current workspace squeezes down and moves back to the right;
//                     the next workspace comes to the center as a card
//   TAB again         the center card moves back right, the next comes to the center
//   SHIFT+TAB         the other way
//   release SUPER     the center card zooms up to full screen and you're on it
//   Esc               cancel (zoom back to where you were)
// Cards are built from snapshots of each workspace's windows (works for workspaces that
// aren't on screen). Number keys keep the plain left/right slide.
//   omarchy-shell lumenCard next | prev | release | cancel
Item {
  id: sw
  readonly property color light: Color.accent

  property bool open: false
  property bool intro: false          // first frame: the current workspace still full size
  property bool zooming: false        // release: the chosen card fills the screen
  property var cards: []              // [{ id, windows: [{ top, x, y, w, h }] }]
  property int selected: 0
  property int origin: 0              // index of the workspace we started on
  property real monX: 0
  property real monY: 0
  property real monW: 1
  property real monH: 1

  function build() {
    var mon = Hyprland.focusedMonitor
    if (mon) {
      var mo = mon.lastIpcObject || {}
      monX = mo.x || 0; monY = mo.y || 0
      monW = (mo.width || 1) / (mo.scale || 1); monH = (mo.height || 1) / (mo.scale || 1)
    }
    var cur = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    var byWs = {}
    var tops = Hyprland.toplevels.values
    for (var i = 0; i < tops.length; i++) {
      var o = tops[i].lastIpcObject
      if (!o || !o.workspace || o.workspace.id < 1 || o.hidden) continue
      var id = o.workspace.id
      if (!byWs[id]) byWs[id] = []
      byWs[id].push({ top: tops[i], x: o.at[0] - monX, y: o.at[1] - monY, w: o.size[0], h: o.size[1] })
    }
    if (!byWs[cur]) byWs[cur] = []
    var ids = Object.keys(byWs).map(Number).sort(function(a, b) { return a - b })
    // order like SUPER+TAB (e+1): current first, then the ones after it, wrapping
    var start = ids.indexOf(cur)
    var ordered = ids.slice(start).concat(ids.slice(0, start))
    cards = ordered.map(function(id) { return { id: id, windows: byWs[id] } })
    origin = 0
  }

  function step(dir) {
    if (!open) {
      Hyprland.refreshToplevels()
      Hyprland.refreshMonitors()
      pendingDir = dir
      openDelay.restart()        // give the IPC refresh a moment
      return
    }
    if (zooming || cards.length < 2) return
    selected = (selected + dir + cards.length) % cards.length
  }
  property int pendingDir: 1
  Timer {
    id: openDelay
    interval: 60
    onTriggered: {
      sw.build()
      if (sw.cards.length < 2) return       // nothing to switch to
      sw.selected = 0
      sw.intro = true
      sw.zooming = false
      sw.open = true
      introEnd.restart()
    }
  }
  Timer {   // one frame at full size, then squeeze into the card layout
    id: introEnd
    interval: 30
    onTriggered: { sw.intro = false; sw.selected = (sw.pendingDir + sw.cards.length) % sw.cards.length }
  }

  function commit() {
    if (!open || zooming) return
    zooming = true
    zoomDone.restart()
  }
  function cancel() {
    if (!open || zooming) return
    selected = origin
    commit()
  }
  Timer {
    id: zoomDone
    interval: 300
    onTriggered: {
      var id = sw.cards[sw.selected].id
      // switch underneath without the slide (the zoom already did the moving), then restore it
      Quickshell.execDetached(["hyprctl", "eval",
        'hl.animation({ leaf = "workspaces", enabled = false }) ' +
        'hl.dispatch(hl.dsp.focus({ workspace = "' + id + '" }))'])
      closeDelay.restart()
    }
  }
  Timer {
    id: closeDelay
    interval: 90
    onTriggered: {
      sw.open = false
      sw.zooming = false
      Quickshell.execDetached(["hyprctl", "eval",
        'hl.animation({ leaf = "workspaces", enabled = true, speed = 4.5, bezier = "easeOutQuint", style = "slide" })'])
    }
  }

  IpcHandler {
    target: "lumenCard"
    function next(): void { sw.step(1) }
    function prev(): void { sw.step(-1) }
    function release(): void { sw.commit() }
    function cancel(): void { sw.cancel() }
  }

  PanelWindow {
    id: win
    screen: Quickshell.screens.find(function(s) { return Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name }) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "lumen-card"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: sw.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    visible: sw.open

    Rectangle {   // dim the desktop behind the cards
      anchors.fill: parent
      color: "black"
      opacity: sw.intro || sw.zooming ? 0 : 0.85
      Behavior on opacity { NumberAnimation { duration: 220 } }
    }

    Item {
      id: keys
      anchors.fill: parent
      focus: sw.open
      Keys.onPressed: function(e) {
        if (e.key === Qt.Key_Escape) sw.cancel()
        else if (e.key === Qt.Key_Tab) sw.step(1)
        else if (e.key === Qt.Key_Backtab) sw.step(-1)
        else if (e.key === Qt.Key_Right) sw.step(1)
        else if (e.key === Qt.Key_Left) sw.step(-1)
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) sw.commit()
        else return
        e.accepted = true
      }
      Keys.onReleased: function(e) {
        if (e.key === Qt.Key_Super_L || e.key === Qt.Key_Super_R || e.key === Qt.Key_Meta) { sw.commit(); e.accepted = true }
      }
    }

    Repeater {
      model: sw.cards
      Item {
        id: cardItem
        required property var modelData
        required property int index
        readonly property int n: sw.cards.length
        // position relative to the selected card: 0 center, negative = already passed
        // (back and to the right), positive = coming up (back and to the left)
        readonly property int rel: {
          var r = (index - sw.selected + n) % n
          return r >= n / 2 && r !== 0 ? r - n : r     // ties go back-right (where you came from)
        }
        readonly property bool chosen: rel === 0
        readonly property bool full: (sw.intro && index === sw.origin) || (sw.zooming && chosen)

        width: sw.monW; height: sw.monH
        transformOrigin: Item.Center
        z: full ? 10 : (chosen ? 5 : 4 - Math.abs(rel))
        x: full ? 0 : (chosen ? 0 : (rel < 0 ? 0.30 + 0.12 * (-rel - 1) : -0.30 - 0.12 * (rel - 1)) * sw.monW)
        y: full ? 0 : (chosen ? -0.02 * sw.monH : 0.04 * sw.monH)
        scale: full ? 1 : (chosen ? 0.62 : Math.max(0.2, 0.42 - 0.08 * (Math.abs(rel) - 1)))
        opacity: full || chosen ? 1 : (Math.abs(rel) > 2 ? 0 : (Math.abs(rel) === 1 ? 0.6 : 0.3))
        Behavior on x { enabled: !sw.intro; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !sw.intro; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !sw.intro; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        Behavior on opacity { enabled: !sw.intro; NumberAnimation { duration: 260 } }

        Rectangle {   // the card face: the desktop backdrop
          anchors.fill: parent
          color: "#0d0d0d"
          radius: cardItem.full ? 0 : 10
          Behavior on radius { NumberAnimation { duration: 200 } }
        }
        Repeater {   // the workspace's windows, as snapshots
          model: cardItem.modelData.windows
          ScreencopyView {
            required property var modelData
            x: modelData.x; y: modelData.y
            width: modelData.w; height: modelData.h
            captureSource: modelData.top ? modelData.top.wayland : null
            live: false
          }
        }
        Rectangle {   // glowing edge on the center card
          anchors.fill: parent
          color: "transparent"
          radius: 10
          border.width: 3 / Math.max(0.2, cardItem.scale)
          border.color: sw.light
          opacity: cardItem.chosen && !cardItem.full ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 200 } }
        }
        Text {   // workspace number under the card
          anchors.top: parent.bottom
          anchors.topMargin: 24 / Math.max(0.2, cardItem.scale)
          anchors.horizontalCenter: parent.horizontalCenter
          text: "◆  " + cardItem.modelData.id
          color: sw.light
          opacity: cardItem.full ? 0 : (cardItem.chosen ? 1 : 0.5)
          font.family: Style.font.family
          font.pixelSize: 22 / Math.max(0.2, cardItem.scale)
          font.bold: true
          font.letterSpacing: 4
        }
        MouseArea {
          anchors.fill: parent
          onClicked: { sw.selected = cardItem.index; sw.commit() }
        }
      }
    }
  }
}
