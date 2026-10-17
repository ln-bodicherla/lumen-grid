import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      id: discs
      model: root.workspaceIds()

      // Lumen light discs: empty = faint ring, occupied = lit ring,
      // focused = double ring with a glowing core. Colors follow the theme's bar text.
      Item {
        id: disc
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        readonly property color lightColor: root.bar ? root.bar.foreground : "#8ED7E6"
        readonly property real size: Math.round(root.barSize * 0.56)

        implicitWidth: root.vertical ? root.barSize : size + Style.space(4)
        implicitHeight: root.vertical ? size + Style.space(4) : root.barSize

        // outer ring
        Rectangle {
          anchors.centerIn: parent
          width: disc.size; height: width; radius: width / 2
          color: "transparent"
          border.width: disc.focused ? 2 : 1.5
          border.color: disc.lightColor
          opacity: disc.focused ? 1 : (disc.occupied ? 0.85 : 0.3)
          scale: 1
          Behavior on opacity { NumberAnimation { duration: 180 } }
        }
        // inner ring (focused only)
        Rectangle {
          anchors.centerIn: parent
          width: Math.round(disc.size * 0.55); height: width; radius: width / 2
          color: "transparent"
          border.width: 1
          border.color: disc.lightColor
          opacity: disc.focused ? 0.7 : 0
          Behavior on opacity { NumberAnimation { duration: 180 } }
        }
        // small dot on occupied discs; the focused core is the shared gooey light below
        Rectangle {
          anchors.centerIn: parent
          width: !disc.focused && disc.occupied ? 3 : 0
          height: width; radius: width / 2
          color: disc.lightColor
          Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        MouseArea {
          id: hover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.focusWorkspace(disc.modelData)
        }
      }
    }
  }

  // Gooey core: one light shared by all discs. On a workspace switch its front
  // end races to the new disc while the back end lags, so it stretches thin
  // like liquid, then pulls back into a round core. Inspired by Gooey from
  // libraries.dev (MIT).
  readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  readonly property real coreSize: Math.round(Math.round(root.barSize * 0.56) * 0.26)
  readonly property color coreColor: root.bar ? root.bar.foreground : "#8ED7E6"

  // Center of the focused disc along the bar's axis, and across it.
  function focusedCenter(_layout) {
    var i = root.workspaceIds().indexOf(root.focusedId)
    var item = i >= 0 ? discs.itemAt(i) : null
    if (!item) return null
    return item.mapToItem(root, item.width / 2, item.height / 2)
  }
  readonly property var target: focusedCenter([grid.width, grid.height, discs.count, root.focusedId])
  readonly property bool hasTarget: target !== null
  readonly property real targetAlong: hasTarget ? (root.vertical ? target.y : target.x) : 0
  readonly property real across: hasTarget ? (root.vertical ? target.x : target.y) : 0

  property bool animate: false
  Timer { interval: 400; running: true; onTriggered: root.animate = true }

  property real head: targetAlong
  property real tail: targetAlong
  Behavior on head { enabled: root.animate; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
  Behavior on tail { enabled: root.animate; NumberAnimation { duration: 520; easing.type: Easing.InOutQuart } }

  readonly property real stretch: Math.abs(head - tail)
  // Thins as it stretches, as if the same amount of light were pulled longer.
  readonly property real thickness: Math.max(coreSize * 0.45, coreSize * (1 - stretch / (coreSize * 9)))

  Item {
    visible: root.hasTarget
    readonly property real lo: Math.min(root.head, root.tail) - root.coreSize / 2
    readonly property real len: root.stretch + root.coreSize
    x: root.vertical ? root.across - width / 2 : lo
    y: root.vertical ? lo : root.across - height / 2
    width: root.vertical ? root.coreSize : len
    height: root.vertical ? len : root.coreSize

    // soft glow
    Rectangle {
      anchors.centerIn: parent
      width: root.vertical ? root.thickness + 4 : parent.width + 4
      height: root.vertical ? parent.height + 4 : root.thickness + 4
      radius: Math.min(width, height) / 2
      color: root.coreColor
      opacity: 0.22
    }
    // the light
    Rectangle {
      anchors.centerIn: parent
      width: root.vertical ? root.thickness : parent.width
      height: root.vertical ? parent.height : root.thickness
      radius: Math.min(width, height) / 2
      color: root.coreColor
    }
  }

  // Blobs at each end: the head arrives full size, the tail drains as it follows.
  component Blob: Rectangle {
    property real along: 0
    property real size: root.coreSize
    visible: root.hasTarget
    width: size; height: size; radius: size / 2
    x: (root.vertical ? root.across : along) - size / 2
    y: (root.vertical ? along : root.across) - size / 2
    color: root.coreColor
  }
  Blob { along: root.head; size: root.coreSize }
  Blob { along: root.tail; size: Math.max(root.thickness, root.coreSize * (1 - root.stretch / (root.coreSize * 6))) }
}
