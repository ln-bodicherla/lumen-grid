import QtQuick
import QtQuick.Shapes

// Lumen border beam: a light cycle riding the edge of its parent, with a bright
// head, a fading trail and a soft glow. Inspired by Border Beam from
// libraries.dev (MIT). Each layer is one dash on a rounded-rect path; moving the
// dash offset carries it around the edge.
Item {
  id: root
  property color color: "#8ED7E6"
  // The head burns hotter than the trail, toward white.
  property color headColor: Qt.tint(color, "#a0ffffff")
  property real radius: 0
  property real inset: 1            // keep the stroke inside the edge
  property real length: 110         // trail length in px
  property int duration: 2600       // ms per lap
  property bool running: visible
  property int loops: Animation.Infinite

  readonly property real w: Math.max(0, width - inset * 2)
  readonly property real h: Math.max(0, height - inset * 2)
  readonly property real r: Math.min(radius, w / 2, h / 2)
  readonly property real perimeter: 2 * (w + h) - (8 - 2 * Math.PI) * r
  property real progress: 0         // 0..1 around the edge

  component BeamPath: ShapePath {
    property real sw: 1
    property real dash: root.length
    property real alpha: 1
    property color tone: root.color
    fillColor: "transparent"
    strokeColor: Qt.rgba(tone.r, tone.g, tone.b, alpha)
    strokeWidth: sw
    capStyle: ShapePath.RoundCap
    strokeStyle: ShapePath.DashLine
    // Dash units are stroke widths. The dash ends at the head, progress * perimeter.
    dashPattern: [dash / sw, Math.max(0.01, root.perimeter - dash) / sw]
    dashOffset: (dash - root.progress * root.perimeter + root.perimeter) / sw
    startX: root.inset; startY: root.inset
    PathRectangle {
      x: root.inset; y: root.inset
      width: root.w; height: root.h
      radius: root.r
    }
  }

  Shape {
    anchors.fill: parent
    visible: root.perimeter > 0
    BeamPath { sw: 9; dash: root.length * 0.6; alpha: 0.22 }
    BeamPath { sw: 2; alpha: 0.75 }
    BeamPath { sw: 3; dash: root.length * 0.22; tone: root.headColor }
  }

  NumberAnimation on progress {
    from: 0; to: 1
    duration: root.duration
    loops: root.loops
    running: root.running && root.perimeter > 0
  }
}
