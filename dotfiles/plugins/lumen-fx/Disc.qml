import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

// Light-disc launcher around the mouse pointer: your favorite apps on the outer
// ring, quick actions (lock, screenshot, Program/Overload, themes, ...) on the inner ring.
// Hold SUPER+D, point at an item, let go: it runs (or the disc just closes if you
// point at nothing). Hyprland calls `lumenDisc show` on press and `lumenDisc release` on
// release; the disc also closes on its own when it sees SUPER or D come up.
// While it's open you can also use:
//   Left / Right / scroll   spin the active ring; whatever sits under the top notch is selected
//   Up / Down / Tab         switch between the app ring and the action ring
//   Enter / Space / click   run it      1-9  run that app directly      Esc / click outside  close
// `omarchy-shell lumenDisc toggle` opens it without the hold.
// Customize in ~/.config/omarchy/lumen-disc.json:
//   { "apps": ["chromium", "org.gnome.Nautilus"],
//     "actions": [{ "name": "Lock", "glyph": "󰌾", "exec": "omarchy system lock" }] }
// (A plain list of desktop ids still works and sets just the apps.)
Item {
  id: disc
  readonly property color light: Color.accent

  readonly property var defaultApps: ["com.mitchellh.ghostty", "chromium", "org.gnome.Nautilus", "md.obsidian.Obsidian",
                                      "btop", "YouTube", "WhatsApp", "1password"]
  readonly property var defaultActions: [
    { name: "Lock", glyph: "󰌾", exec: "omarchy system lock" },
    { name: "Screenshot", glyph: "󰹑", exec: "omarchy capture screenshot" },
    { name: "Program / Overload", glyph: "󰔎", exec: "$HOME/.local/bin/lumen-switch" },
    { name: "Themes", glyph: "󰏘", exec: "omarchy theme switcher" },
    { name: "Next wallpaper", glyph: "󰋩", exec: "omarchy theme bg next" },
    { name: "Clipboard", glyph: "󰅇", exec: "omarchy menu clipboard" },
    { name: "Do not disturb", glyph: "󰂛", exec: "omarchy toggle notification silencing" },
    { name: "Grid vision", glyph: "󰈈", exec: "$HOME/.local/bin/lumen-gridvision" },
    { name: "Power", glyph: "󰐥", exec: "omarchy menu toggle system" }
  ]
  property var appIds: defaultApps
  property var actions: defaultActions

  readonly property var apps: {
    var out = []
    for (var i = 0; i < appIds.length; i++) {
      var e = DesktopEntries.heuristicLookup(appIds[i])
      if (e) out.push(e)
    }
    return out
  }

  property bool open: false
  property bool cancelOpen: false   // released before the disc finished opening
  property var hover: null          // { ring, item } under the pointer
  property int ring: 0              // 0 apps (outer), 1 actions (inner)
  property int appIndex: 0
  property int actIndex: 0
  readonly property real appStep: 360 / Math.max(1, apps.length)
  readonly property real actStep: 360 / Math.max(1, actions.length)
  property real appSpin: 0
  property real actSpin: 0
  Behavior on appSpin { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
  Behavior on actSpin { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

  function wrap(i, n) { return n ? ((i % n) + n) % n : 0 }
  readonly property var selApp: apps.length ? apps[wrap(appIndex, apps.length)] : null
  readonly property var selAct: actions.length ? actions[wrap(actIndex, actions.length)] : null
  readonly property string label: ring === 0 ? (selApp ? selApp.name : "") : (selAct ? selAct.name : "")

  property real cx: 0
  property real cy: 0
  readonly property real outerR: 150
  readonly property real innerR: 88

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/lumen-disc.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var cfg = JSON.parse(text())
        if (Array.isArray(cfg)) cfg = { apps: cfg }
        disc.appIds = Array.isArray(cfg.apps) && cfg.apps.length ? cfg.apps : disc.defaultApps
        disc.actions = Array.isArray(cfg.actions) && cfg.actions.length ? cfg.actions : disc.defaultActions
      } catch (e) {}
    }
    onLoadFailed: { disc.appIds = disc.defaultApps; disc.actions = disc.defaultActions }
  }

  function rotate(by) {
    if (ring === 0) { appIndex += by; appSpin = -appIndex * appStep }
    else { actIndex += by; actSpin = -actIndex * actStep }
  }
  function runApp(entry) { if (entry) entry.execute(); open = false }
  function runAction(a) { if (a) Quickshell.execDetached(["bash", "-c", a.exec]); open = false }
  function runSelected() { if (ring === 0) runApp(selApp); else runAction(selAct) }

  function show() {
    if (open || cursor.running) return
    cancelOpen = false
    hover = null
    cursor.running = true
  }
  // Letting go of the keys: run what the pointer is on, otherwise just close.
  function release() {
    if (cursor.running) { cancelOpen = true; return }
    if (!open) return
    var h = hover
    hover = null
    if (h && h.ring === 0) runApp(h.item)
    else if (h && h.ring === 1) runAction(h.item)
    else open = false
  }
  function pointAt(r, i, item) {
    ring = r
    if (r === 0) appIndex = i; else actIndex = i
    hover = { ring: r, item: item }
  }

  Process {
    id: cursor
    command: ["hyprctl", "cursorpos", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { var p = JSON.parse(text); disc.cx = p.x; disc.cy = p.y } catch (e) {}
        disc.ring = 0
        if (disc.cancelOpen) { disc.cancelOpen = false; return }
        disc.open = true
      }
    }
  }

  IpcHandler {
    target: "lumenDisc"
    function toggle(): void { if (disc.open) disc.open = false; else disc.show() }
    function show(): void { disc.show() }
    function release(): void { disc.release() }
    function close(): void { disc.open = false }
  }

  // One slot on a ring: an app icon or an action glyph.
  component Slot: Item {
    id: slot
    property real angle: 0          // degrees, 0 = top
    property real r: 0
    property bool chosen: false
    property bool dim: false        // on the inactive ring
    property real size: 50
    property string iconSource: ""
    property string glyph: ""
    signal activated()
    signal pointed()
    signal unpointed()
    readonly property real rad: (angle - 90) * Math.PI / 180
    x: Math.cos(rad) * r
    y: Math.sin(rad) * r
    opacity: dim ? 0.55 : 1

    Rectangle {
      anchors.centerIn: parent
      width: slot.chosen ? slot.size * 1.3 : slot.size; height: width; radius: width / 2
      color: slot.chosen ? Qt.rgba(disc.light.r, disc.light.g, disc.light.b, 0.16) : Qt.rgba(0.05, 0.05, 0.05, 0.6)
      border.width: slot.chosen ? 2 : 1
      border.color: disc.light
      opacity: slot.chosen ? 1 : 0.45
      Behavior on width { NumberAnimation { duration: 160 } }
    }
    Image {
      visible: slot.iconSource !== ""
      anchors.centerIn: parent
      width: (slot.chosen ? 0.8 : 0.6) * slot.size; height: width
      source: slot.iconSource
      sourceSize: Qt.size(80, 80)
      smooth: true
      opacity: slot.chosen ? 1 : 0.75
      Behavior on width { NumberAnimation { duration: 160 } }
    }
    Text {
      visible: slot.glyph !== ""
      anchors.centerIn: parent
      text: slot.glyph
      color: disc.light
      font.family: Style.font.family
      font.pixelSize: (slot.chosen ? 0.55 : 0.45) * slot.size
      opacity: slot.chosen ? 1 : 0.8
    }
    MouseArea {
      anchors.centerIn: parent
      width: slot.size + 8; height: width
      cursorShape: Qt.PointingHandCursor
      hoverEnabled: true
      onEntered: slot.pointed()
      onExited: slot.unpointed()
      onClicked: slot.activated()
    }
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      readonly property bool here: Hyprland.focusedMonitor !== null && Hyprland.focusedMonitor.name === modelData.name
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "lumen-disc"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: disc.open && here ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      visible: here && (disc.open || body.opacity > 0)

      // where the disc sits on this screen, kept fully on screen
      readonly property real px: Math.max(disc.outerR + 70, Math.min(width - disc.outerR - 70, disc.cx - modelData.x))
      readonly property real py: Math.max(disc.outerR + 70, Math.min(height - disc.outerR - 70, disc.cy - modelData.y))

      Rectangle {   // dim scrim; a click outside the disc closes it
        anchors.fill: parent
        color: "black"
        opacity: disc.open ? 0.4 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        MouseArea {
          anchors.fill: parent
          onClicked: disc.open = false
          onWheel: function(w) { disc.rotate(w.angleDelta.y > 0 ? -1 : 1) }
        }
      }

      Item {
        id: body
        x: win.px; y: win.py
        width: 0; height: 0
        focus: disc.open
        opacity: disc.open ? 1 : 0
        scale: disc.open ? 1 : 0.6
        rotation: disc.open ? 0 : -90
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
        Behavior on rotation { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

        Keys.onPressed: function(event) {
          var k = event.key
          if (k === Qt.Key_Escape) disc.open = false
          else if (k === Qt.Key_Left) disc.rotate(-1)
          else if (k === Qt.Key_Right) disc.rotate(1)
          else if (k === Qt.Key_Up) disc.ring = 0
          else if (k === Qt.Key_Down) disc.ring = 1
          else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) disc.ring = 1 - disc.ring
          else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) disc.runSelected()
          else if (k >= Qt.Key_1 && k <= Qt.Key_9 && k - Qt.Key_1 < disc.apps.length) disc.runApp(disc.apps[k - Qt.Key_1])
          else return
          event.accepted = true
        }
        // the hold ends when SUPER or D comes up (ALT too, for older bindings)
        Keys.onReleased: function(event) {
          if (event.isAutoRepeat) return
          var k = event.key
          if (k === Qt.Key_Super_L || k === Qt.Key_Super_R || k === Qt.Key_Meta || k === Qt.Key_Alt || k === Qt.Key_D) {
            disc.release()
            event.accepted = true
          }
        }

        // disc face
        Rectangle {
          anchors.centerIn: parent
          width: (disc.outerR + 40) * 2; height: width; radius: width / 2
          color: Qt.rgba(0.05, 0.05, 0.05, 0.92)
          border.width: 2; border.color: disc.light
        }
        // spinning outer light ring, dashed like a disc's edge
        Shape {
          anchors.centerIn: parent
          width: (disc.outerR + 52) * 2; height: width
          RotationAnimation on rotation { from: 0; to: 360; duration: 9000; loops: Animation.Infinite; running: disc.open }
          ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(disc.light.r, disc.light.g, disc.light.b, 0.7)
            strokeWidth: 2
            strokeStyle: ShapePath.DashLine
            dashPattern: [14, 6]
            PathAngleArc { centerX: disc.outerR + 52; centerY: disc.outerR + 52; radiusX: disc.outerR + 50; radiusY: disc.outerR + 50; sweepAngle: 360 }
          }
        }
        // divider between the two rings
        Rectangle {
          anchors.centerIn: parent
          width: (disc.outerR + disc.innerR); height: width; radius: width / 2
          color: "transparent"; border.width: 1; border.color: disc.light
          opacity: 0.35
        }
        Rectangle {   // inner ring backdrop, lit while the action ring is active
          anchors.centerIn: parent
          width: (disc.innerR + 30) * 2; height: width; radius: width / 2
          color: disc.ring === 1 ? Qt.rgba(disc.light.r, disc.light.g, disc.light.b, 0.07) : "transparent"
          Behavior on color { ColorAnimation { duration: 160 } }
        }
        // hub
        Rectangle {
          anchors.centerIn: parent
          width: 84; height: width; radius: width / 2
          color: Qt.rgba(0.05, 0.05, 0.05, 0.95); border.width: 1; border.color: disc.light
        }
        Rectangle {
          x: -4; y: -14
          width: 8; height: width; radius: width / 2; color: disc.light
        }
        // selection notches at the top of each ring; the active one is solid
        Repeater {
          model: [{ r: disc.outerR + 46, ring: 0 }, { r: disc.innerR + 32, ring: 1 }]
          Shape {
            required property var modelData
            x: -8; y: -modelData.r
            width: 16; height: 11
            opacity: disc.ring === modelData.ring ? 1 : 0.35
            ShapePath {
              fillColor: disc.light; strokeColor: "transparent"
              startX: 0; startY: 0
              PathLine { x: 16; y: 0 }
              PathLine { x: 8; y: 11 }
              PathLine { x: 0; y: 0 }
            }
          }
        }

        Repeater {
          model: disc.apps
          Slot {
            required property var modelData
            required property int index
            angle: disc.appSpin + index * disc.appStep
            r: disc.outerR
            size: 50
            chosen: disc.ring === 0 && disc.selApp === modelData
            dim: disc.ring !== 0
            iconSource: Quickshell.iconPath(modelData.icon, "application-x-executable")
            onActivated: disc.runApp(modelData)
            onPointed: disc.pointAt(0, index, modelData)
            onUnpointed: if (disc.hover && disc.hover.item === modelData) disc.hover = null
          }
        }
        Repeater {
          model: disc.actions
          Slot {
            required property var modelData
            required property int index
            angle: disc.actSpin + index * disc.actStep
            r: disc.innerR
            size: 38
            chosen: disc.ring === 1 && disc.selAct === modelData
            dim: disc.ring !== 1
            glyph: modelData.glyph || "◆"
            onActivated: disc.runAction(modelData)
            onPointed: disc.pointAt(1, index, modelData)
            onUnpointed: if (disc.hover && disc.hover.item === modelData) disc.hover = null
          }
        }

        // selected name in the hub, decrypting in as the selection changes
        Decrypt {
          x: -38; y: 4
          width: 76
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          target: disc.label.toUpperCase()
          duration: 260
          color: disc.light
          font.family: Style.font.family
          font.pixelSize: 10
          font.bold: true
          font.letterSpacing: 1
        }
      }
    }
  }
}
