import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons

// Grid vision control: an eye in the bar.
//   eye         auto is on (tints while a chosen app has focus)
//   crossed     auto is off
// Left click: panel with the auto switch and the apps that get the tint (your open
// apps plus the ones already chosen). Right click: auto on / off.
// Settings live in ~/.config/omarchy/lumen-vision.json; the lumen-fx plugin does the tinting.
Item {
  id: root
  property var bar
  property string moduleName
  property var settings

  readonly property color light: bar ? bar.foreground : "#8ED7E6"
  readonly property real size: bar ? bar.barSize : 26
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/lumen-vision.json"

  property var vision: ({ auto: false, apps: [] })
  readonly property string focusedClass: Hyprland.activeToplevel && Hyprland.activeToplevel.lastIpcObject
                                         ? String(Hyprland.activeToplevel.lastIpcObject.class || "") : ""
  readonly property bool tinted: vision.auto === true && (vision.apps || []).indexOf(focusedClass) !== -1

  implicitWidth: size
  implicitHeight: size

  FileView {
    id: cfg
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.vision = JSON.parse(text()) } catch (e) {} }
  }
  function save(v) {
    root.vision = v
    cfg.setText(JSON.stringify(v, null, 2) + "\n")
  }
  function setAuto(on) {
    save({ auto: on, apps: vision.apps || [] })
    if (on) Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/lumen-gridvision", "write"])
  }
  function toggleApp(cls) {
    var apps = (vision.apps || []).slice()
    var i = apps.indexOf(cls)
    if (i === -1) apps.push(cls); else apps.splice(i, 1)
    save({ auto: vision.auto === true, apps: apps })
  }

  // the eye
  Text {
    anchors.centerIn: parent
    text: root.vision.auto ? "󰈈" : "󰈉"
    color: root.light
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.setAuto(!root.vision.auto)
      else popup.visible = !popup.visible
    }
    onEntered: if (root.bar && !popup.visible) root.bar.showTooltip(root, "Grid vision · " + (root.vision.auto ? "auto" : "off"))
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  // apps to list: open windows plus the chosen ones
  readonly property var appList: {
    var seen = {}, out = []
    var tops = Hyprland.toplevels.values
    for (var i = 0; i < tops.length; i++) {
      var o = tops[i].lastIpcObject
      var c = o ? String(o.class || "") : ""
      if (c && !seen[c]) { seen[c] = true; out.push(c) }
    }
    var apps = vision.apps || []
    for (var j = 0; j < apps.length; j++) if (!seen[apps[j]]) { seen[apps[j]] = true; out.push(apps[j]) }
    out.sort()
    return out
  }
  function niceName(cls) {
    var e = DesktopEntries.heuristicLookup(cls)
    return e ? e.name : cls
  }
  function iconFor(cls) {
    var e = DesktopEntries.heuristicLookup(cls)
    return Quickshell.iconPath(e ? e.icon : cls, "application-x-executable")
  }

  PopupWindow {
    id: popup
    visible: false
    anchor.item: root
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.rect.y: root.height + 6
    implicitWidth: 300
    implicitHeight: col.implicitHeight + 28
    color: "transparent"
    onVisibleChanged: if (visible) Hyprland.refreshToplevels()

    HyprlandFocusGrab {
      windows: [popup]
      active: popup.visible
      onCleared: popup.visible = false
    }

    Rectangle {
      anchors.fill: parent
      radius: 4
      color: Qt.rgba(0.05, 0.05, 0.05, 0.96)
      border.width: 1
      border.color: root.light

      Column {
        id: col
        x: 14; y: 14
        width: parent.width - 28
        spacing: 8

        Row {
          width: parent.width
          spacing: 8
          Text {
            text: "GRID VISION"
            color: root.light
            font.family: root.bar ? root.bar.fontFamily : "monospace"
            font.pixelSize: 12
            font.bold: true
            font.letterSpacing: 3
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - autoSwitch.width - 8
          }
          // auto switch
          Rectangle {
            id: autoSwitch
            width: 46; height: 22; radius: 11
            color: root.vision.auto ? Qt.rgba(root.light.r, root.light.g, root.light.b, 0.3) : "transparent"
            border.width: 1; border.color: root.light
            Rectangle {
              width: 16; height: 16; radius: 8
              y: 3; x: root.vision.auto ? parent.width - width - 3 : 3
              color: root.light
              opacity: root.vision.auto ? 1 : 0.5
              Behavior on x { NumberAnimation { duration: 150 } }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setAuto(!root.vision.auto) }
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Tint the screen while these apps are focused:"
          color: root.light
          opacity: 0.6
          font.family: root.bar ? root.bar.fontFamily : "monospace"
          font.pixelSize: 10
        }

        Repeater {
          model: root.appList
          Rectangle {
            required property string modelData
            readonly property bool on: (root.vision.apps || []).indexOf(modelData) !== -1
            width: col.width
            height: 30
            radius: 3
            color: hover.containsMouse ? Qt.rgba(root.light.r, root.light.g, root.light.b, 0.1) : "transparent"
            Image {
              x: 6; anchors.verticalCenter: parent.verticalCenter
              width: 18; height: 18
              source: root.iconFor(parent.modelData)
              sourceSize: Qt.size(36, 36)
            }
            Text {
              x: 32; anchors.verticalCenter: parent.verticalCenter
              width: parent.width - 32 - 34
              elide: Text.ElideRight
              text: root.niceName(parent.modelData)
              color: root.light
              opacity: parent.on ? 1 : 0.65
              font.family: root.bar ? root.bar.fontFamily : "monospace"
              font.pixelSize: 12
            }
            Rectangle {   // checkbox
              anchors.right: parent.right; anchors.rightMargin: 6
              anchors.verticalCenter: parent.verticalCenter
              width: 16; height: 16; radius: 3
              color: parent.on ? root.light : "transparent"
              border.width: 1; border.color: root.light
              Text { anchors.centerIn: parent; text: "✓"; visible: parent.parent.on; color: "#0d0d0d"; font.pixelSize: 11; font.bold: true }
            }
            MouseArea {
              id: hover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleApp(parent.modelData)
            }
          }
        }

        Text {
          visible: root.appList.length === 0
          text: "Open an app to add it here."
          color: root.light
          opacity: 0.5
          font.family: root.bar ? root.bar.fontFamily : "monospace"
          font.pixelSize: 11
        }
      }
    }
  }
}
