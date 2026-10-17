import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Live wallpaper switch: click to pause the live Grid world (it freezes into a still
// image) or bring it back to life. Saved in ~/.config/omarchy/lumen-wallpaper.json.
Item {
  id: root
  property var bar
  property string moduleName
  property var settings

  readonly property color light: bar ? bar.foreground : "#8ED7E6"
  readonly property real size: bar ? bar.barSize : 26
  property bool live: true

  implicitWidth: size
  implicitHeight: size

  FileView {
    id: cfg
    path: Quickshell.env("HOME") + "/.config/omarchy/lumen-wallpaper.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.live = JSON.parse(text()).live !== false } catch (e) {} }
  }
  function toggle() {
    root.live = !root.live
    cfg.setText(JSON.stringify({ live: root.live }, null, 2) + "\n")
  }

  Text {   // landscape while live, pause while frozen; same size and color as every bar icon
    anchors.centerIn: parent
    text: root.live ? "󰸉" : "󰏤"
    color: root.light
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.toggle()
    onEntered: if (root.bar) root.bar.showTooltip(root, root.live ? "Live wallpaper · click to pause" : "Wallpaper paused · click for live")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
