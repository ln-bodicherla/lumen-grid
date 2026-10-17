import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// The ship's computer: SUPER+ALT+C opens a bar at the top of the screen.
//   Type anything        live search across your apps, Omarchy system commands and
//                        files in your home folder; Up/Down to pick, Enter to open.
//   End with "?"         Enter asks Claude instead (via ~/.local/bin/lumen-computer),
//                        which answers and runs Omarchy commands for you. Safe ones run
//                        at once; anything else waits for a second Enter.
//   Esc closes. You can dictate into it with your Voxtype key.
// IPC: omarchy-shell lumenComputer toggle | ask "<request>" | search "<text>"
Item {
  id: comp
  readonly property color light: Color.accent
  readonly property color warn: Color.urgent

  property bool open: false
  property string phase: "input"        // input | thinking | answer | confirm | done
  property string query: ""
  property string say: ""
  property var commands: []
  property var history: []              // this session's questions and answers, for follow-ups
  property string lastQuestion: ""

  readonly property bool asking: query.trim().endsWith("?")

  function show() {
    phase = "input"; say = ""; commands = []; query = ""; selected = 0; files = []; history = []
    open = true
  }
  function close() { open = false; ask.running = false }

  // Waveform shown while the computer thinks.
  component Wave: Row {
    spacing: 4
    height: 28
    Repeater {
      model: 32
      Rectangle {
        required property int index
        width: 4
        radius: 2
        color: comp.light
        anchors.verticalCenter: parent.verticalCenter
        property real k: 0
        height: 4 + 22 * k
        opacity: 0.4 + 0.6 * k
        SequentialAnimation on k {
          running: comp.phase === "thinking"
          loops: Animation.Infinite
          PauseAnimation { duration: (index * 37) % 260 }
          NumberAnimation { to: 1; duration: 220 + (index * 53) % 180; easing.type: Easing.InOutSine }
          NumberAnimation { to: 0.1; duration: 240 + (index * 29) % 200; easing.type: Easing.InOutSine }
        }
      }
    }
  }

  // ---- search ----
  property var systemCommands: []       // from `omarchy commands --json`, runnable without arguments
  property var files: []
  property int selected: 0
  property real pointerX: -1            // last pointer position over the results (scene coords)
  property real pointerY: -1

  Process {
    running: true
    command: ["omarchy", "commands", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var all = JSON.parse(text).commands || []
          comp.systemCommands = all.filter(function(c) {
            return !c.hidden && !c.requires_sudo && (!c.args || String(c.args).trim().charAt(0) === "[")
          })
        } catch (e) {}
      }
    }
  }

  // A typed web address (github.com, https://..., localhost:3000/x), as a URL to open; "" if it isn't one.
  function urlFor(text) {
    if (!text || /\s/.test(text)) return ""
    if (/^https?:\/\//i.test(text)) return text
    if (/^(localhost|\d{1,3}(\.\d{1,3}){3})(:\d+)?(\/\S*)?$/i.test(text)) return "http://" + text
    if (/^([a-z0-9-]+\.)+[a-z]{2,}(:\d+)?(\/\S*)?$/i.test(text) && !/\.(txt|md|pdf|png|jpe?g|qml|py|sh|json|toml|lua|conf|log)$/i.test(text)) return "https://" + text
    return ""
  }

  function score(hay, q) {
    hay = String(hay || "").toLowerCase()
    var i = hay.indexOf(q)
    if (i < 0) return -1
    if (i === 0) return 3
    return /[\s\-_./]/.test(hay.charAt(i - 1)) ? 2 : 1
  }

  readonly property var results: {
    var q = query.trim().toLowerCase()
    if (!q || asking) return []
    var out = []
    var url = comp.urlFor(query.trim())
    if (url) out.push({ kind: "WEB", title: url.replace(/^https?:\/\//, ""), detail: "open in the browser", url: url })
    var apps = DesktopEntries.applications.values
    for (var i = 0; i < apps.length; i++) {
      var a = apps[i]
      if (a.noDisplay) continue
      var s = Math.max(score(a.name, q) * 2, score(a.genericName, q), score((a.keywords || []).join(" "), q))
      if (s > 0) out.push({ kind: "APP", title: a.name, detail: a.genericName || a.comment || "", rank: 30 + s, entry: a })
    }
    for (var j = 0; j < systemCommands.length; j++) {
      var c = systemCommands[j]
      var route = String(c.route).replace(/^omarchy /, "")
      var t = Math.max(score(route, q) * 2, score(c.summary, q))
      if (t > 0) out.push({ kind: "SYS", title: route, detail: c.summary, rank: 20 + t, run: c.route })
    }
    out.sort(function(x, y) { return y.rank - x.rank })
    out = out.slice(0, 10)
    for (var k = 0; k < files.length && out.length < 16; k++)
      out.push({ kind: "FILE", title: files[k].name, detail: files[k].dir, path: files[k].path })
    return out
  }
  onResultsChanged: if (selected >= results.length) selected = Math.max(0, results.length - 1)

  Timer {   // debounce file search
    id: fileDebounce
    interval: 180
    onTriggered: {
      var q = comp.query.trim()
      if (q.length < 2 || comp.asking) { comp.files = []; return }
      fileSearch.running = false
      fileSearch.command = ["fd", "--ignore-case", "--max-results", "6", "--exclude", ".cache", "--exclude", "node_modules",
                            "--exclude", ".local/share/Trash", "--absolute-path", "--fixed-strings", "--", q, Quickshell.env("HOME")]
      fileSearch.running = true
    }
  }
  Process {
    id: fileSearch
    stdout: StdioCollector {
      onStreamFinished: {
        var home = Quickshell.env("HOME")
        comp.files = String(text).split("\n").filter(function(l) { return l.length }).map(function(p) {
          var clean = p.replace(/\/$/, "")
          var cut = clean.lastIndexOf("/")
          return { path: clean, name: clean.slice(cut + 1), dir: clean.slice(0, cut).replace(home, "~") }
        })
      }
    }
  }
  onQueryChanged: { selected = 0; fileDebounce.restart() }

  function openResult(r) {
    if (!r) return
    if (r.kind === "APP") r.entry.execute()
    else if (r.kind === "SYS") Quickshell.execDetached(["bash", "-lc", r.run])
    else if (r.kind === "FILE") Quickshell.execDetached(["xdg-open", r.path])
    else if (r.kind === "WEB") Quickshell.execDetached(["xdg-open", r.url])
    open = false
  }

  // ---- asking Claude ----
  function submit(text) {
    text = String(text || "").trim()
    if (!text) return
    phase = "thinking"
    say = ""
    commands = []
    lastQuestion = text
    ask.command = [Quickshell.env("HOME") + "/.local/bin/lumen-computer", "--history", JSON.stringify(history), text]
    ask.running = true
  }
  function runAll() {
    for (var i = 0; i < commands.length; i++) Quickshell.execDetached(["bash", "-lc", commands[i].cmd])
    phase = "done"
    closeLater.restart()
  }
  function enter() {
    if (phase === "confirm") runAll()
    else if (phase === "done") close()
    else if (phase === "answer" && !query.trim()) close()
    else if (phase !== "input" && phase !== "answer") return
    else if (asking) submit(query)
    else openResult(results[selected])
  }

  Process {
    id: ask
    stdout: StdioCollector {
      onStreamFinished: {
        var r = {}
        try { r = JSON.parse(text) } catch (e) { r = { say: "Computer core offline.", commands: [], autorun: true } }
        comp.say = r.say || ""
        comp.commands = r.commands || []
        comp.history = comp.history.concat([{ q: comp.lastQuestion, a: comp.say }]).slice(-4)
        if (comp.commands.length === 0) {
          // stays open, input cleared for the next question (or a search)
          comp.phase = "answer"
          comp.query = ""
        }
        else if (r.autorun) { closeLater.interval = 2600; comp.runAll() }
        else comp.phase = "confirm"
      }
    }
  }
  Timer { id: closeLater; interval: 2600; onTriggered: if (comp.phase === "done") comp.open = false }

  IpcHandler {
    target: "lumenComputer"
    function toggle(): void { if (comp.open) comp.close(); else comp.show() }
    function ask(request: string): void { if (!comp.open) comp.show(); comp.query = request; comp.submit(request) }
    function search(text: string): void { comp.show(); comp.query = text }
  }

  PanelWindow {
    id: win
    visible: comp.open || openK > 0

    // Opening: two light cycles launch from the middle of the bar's left edge and race
    // in opposite directions along the top and bottom, drawing the frame behind them,
    // while a glowing scan edge unveils the bar left to right. They meet on the right
    // edge and the contents decrypt in. Closing rewinds it.
    property real openK: 0
    NumberAnimation { id: openAnim; target: win; property: "openK"; from: 0; to: 1; duration: 460; easing.type: Easing.OutCubic }
    NumberAnimation { id: closeAnim; target: win; property: "openK"; to: 0; duration: 220; easing.type: Easing.InCubic }
    Connections {
      target: comp
      function onOpenChanged() {
        if (comp.open) { closeAnim.stop(); openAnim.restart(); promptLabel.play() }
        else { openAnim.stop(); closeAnim.restart() }
      }
    }
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "lumen-computer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: comp.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {   // dim the desktop; a click outside the bar closes it
      anchors.fill: parent
      color: "black"
      opacity: comp.open ? 0.2 : 0
      Behavior on opacity { NumberAnimation { duration: 200 } }
      MouseArea { anchors.fill: parent; onClicked: comp.close() }
    }

    // Where the bar sits: input line centered on screen; when the results would run
    // off the bottom, the whole bar rides up just enough to fit (top at most).
    readonly property real centerY: height / 2 - 46
    readonly property real targetY: Math.max(40, Math.min(centerY, height - 40 - panel.height))
    // the bar's full frame on screen (revealer animates within it)
    readonly property real frameX: revealer.x
    readonly property real frameY: revealer.fullY

    // Light-cycle trail: when the bar moves, both edges leave a fading light streak
    // from where it was to where it is.
    property real trailFrom: 0
    property real trailK: 0
    onTargetYChanged: {
      if (!comp.open) return
      trailFrom = win.frameY
      trailAnim.restart()
    }
    NumberAnimation { id: trailAnim; target: win; property: "trailK"; from: 1; to: 0; duration: 520; easing.type: Easing.OutQuad }

    Repeater {
      model: [0, 1]
      Rectangle {
        id: streak
        required property var modelData
        visible: win.trailK > 0 && Math.abs(win.trailFrom - win.frameY) > 4
        readonly property bool up: win.frameY < win.trailFrom
        x: win.frameX + (modelData ? panel.width - 1 : -1)
        width: 2
        // spans from the bar's top edge back to where that edge started
        y: up ? win.frameY : win.trailFrom
        height: Math.abs(win.trailFrom - win.frameY)
        opacity: win.trailK
        // bright at the bar, fading back toward where it came from (flipped when moving down)
        rotation: up ? 0 : 180
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.tint(comp.light, "#a0ffffff") }
          GradientStop { position: 1.0; color: "transparent" }
        }
        Rectangle {   // soft glow around the streak
          anchors.centerIn: parent
          width: 10; height: parent.height
          opacity: 0.25
          gradient: Gradient {
            GradientStop { position: 0.0; color: comp.light }
            GradientStop { position: 1.0; color: "transparent" }
          }
        }
      }
    }

    Rectangle {   // soft glow around the bar, once it's drawn
      x: revealer.x - 8; y: revealer.y - 8
      width: panel.width + 16; height: panel.height + 16
      radius: 10
      color: "transparent"
      border.width: 8
      border.color: Qt.rgba(panel.border.color.r, panel.border.color.g, panel.border.color.b, 0.18)
      opacity: Math.max(0, (win.openK - 0.8) / 0.2)
    }

    // the light cycles: path from the left edge's middle, around one half of the frame
    Item {
      id: cycles
      x: win.frameX; y: win.frameY
      width: panel.width; height: panel.height
      visible: win.openK > 0 && win.openK < 1
      readonly property real w: width
      readonly property real h: height
      readonly property real run: h / 2 + w + h / 2          // length of one half
      readonly property real d: win.openK * run              // how far each cycle has gone
      function at(dist, bottom) {                             // point on the path
        var x, y
        if (dist < h / 2) { x = 0; y = h / 2 - dist }
        else if (dist < h / 2 + w) { x = dist - h / 2; y = 0 }
        else { x = w; y = Math.min(h / 2, dist - h / 2 - w) }
        return Qt.point(x, bottom ? h - y : y)
      }

      // drawn frame: one dash per half that grows with the cycle
      Shape {
        anchors.fill: parent
        ShapePath {
          fillColor: "transparent"; strokeColor: Qt.tint(comp.light, "#60ffffff"); strokeWidth: 2
          strokeStyle: ShapePath.DashLine
          dashPattern: [Math.max(0.01, cycles.d / 2), (cycles.run + 4) / 2]
          startX: 1; startY: cycles.h / 2
          PathLine { x: 1; y: 1 }
          PathLine { x: cycles.w - 1; y: 1 }
          PathLine { x: cycles.w - 1; y: cycles.h / 2 }
        }
        ShapePath {
          fillColor: "transparent"; strokeColor: Qt.tint(comp.light, "#60ffffff"); strokeWidth: 2
          strokeStyle: ShapePath.DashLine
          dashPattern: [Math.max(0.01, cycles.d / 2), (cycles.run + 4) / 2]
          startX: 1; startY: cycles.h / 2
          PathLine { x: 1; y: cycles.h - 1 }
          PathLine { x: cycles.w - 1; y: cycles.h - 1 }
          PathLine { x: cycles.w - 1; y: cycles.h / 2 }
        }
      }
      // the two bright heads
      Repeater {
        model: [false, true]
        Item {
          required property var modelData
          readonly property point p: cycles.at(cycles.d, modelData)
          x: p.x; y: p.y
          Rectangle { anchors.centerIn: parent; width: 26; height: 26; radius: 13; color: comp.light; opacity: 0.3 }
          Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: Qt.tint(comp.light, "#c0ffffff") }
        }
      }
    }

    // the scan edge that unveils the bar
    Rectangle {
      visible: win.openK > 0 && win.openK < 1
      x: win.frameX + panel.width * win.openK - 1
      y: win.frameY
      width: 2; height: panel.height
      color: Qt.tint(comp.light, "#a0ffffff")
      Rectangle { anchors.centerIn: parent; width: 18; height: parent.height; color: comp.light; opacity: 0.18 }
    }

    Item {
      id: revealer
      x: (win.width - panel.width) / 2
      width: panel.width * win.openK
      property real fullY: win.targetY
      Behavior on fullY { enabled: win.openK >= 1; NumberAnimation { duration: 280; easing.type: Easing.OutExpo } }
      y: fullY
      height: panel.height
      clip: true
      visible: win.openK > 0

    Rectangle {
      id: panel
      width: Math.min(960, win.width - 80)
      height: body.implicitHeight + 48
      y: 0
      radius: 4
      color: Qt.rgba(0.04, 0.04, 0.04, 0.94)
      border.width: 2
      border.color: comp.phase === "confirm" ? comp.warn : comp.light

      Repeater {   // corner ticks
        model: [[0, 0], [1, 0], [0, 1], [1, 1]]
        Rectangle {
          required property var modelData
          width: 22; height: 3; color: panel.border.color
          x: modelData[0] ? panel.width - width : 0
          y: modelData[1] ? panel.height - height : 0
        }
      }

      Column {
        id: body
        opacity: Math.max(0, (win.openK - 0.7) / 0.3)
        x: 28; y: 24
        width: panel.width - 56
        spacing: 16

        Row {
          spacing: 18
          width: parent.width
          // Light-disc logo in place of a label: same size in every mode, so the
          // input never shifts. Calm spin while searching, core lights up and pulses
          // when the line ends with "?", fast spin while the computer thinks.
          Item {
            id: promptLabel
            width: 44; height: 44
            anchors.verticalCenter: parent.verticalCenter
            readonly property bool thinking: comp.phase === "thinking"
            property real spinIn: 1
            function play() { spinInAnim.restart() }
            NumberAnimation { id: spinInAnim; target: promptLabel; property: "spinIn"; from: 0; to: 1; duration: 520; easing.type: Easing.OutCubic }
            scale: 0.6 + 0.4 * spinIn
            rotation: -180 * (1 - spinIn)

            Rectangle {   // outer ring
              anchors.centerIn: parent
              width: 40; height: 40; radius: 20
              color: "transparent"; border.width: 2; border.color: comp.light
            }
            Rectangle {   // inner ring
              anchors.centerIn: parent
              width: 22; height: 22; radius: 11
              color: "transparent"; border.width: 1; border.color: comp.light
              opacity: 0.6
            }
            Rectangle {   // core
              id: core
              anchors.centerIn: parent
              property real pulse: 0
              width: (comp.asking ? 10 : 7) + 3 * pulse; height: width; radius: width / 2
              color: comp.asking || promptLabel.thinking ? Qt.tint(comp.light, "#b0ffffff") : comp.light
              Behavior on width { NumberAnimation { duration: 160 } }
              SequentialAnimation on pulse {
                running: comp.asking || promptLabel.thinking
                loops: Animation.Infinite
                onStopped: core.pulse = 0
                NumberAnimation { to: 1; duration: 520; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0; duration: 520; easing.type: Easing.InOutSine }
              }
              Rectangle {   // glow
                anchors.centerIn: parent
                width: parent.width * 2.6; height: width; radius: width / 2
                color: comp.light
                opacity: (comp.asking || promptLabel.thinking) ? 0.25 + 0.2 * core.pulse : 0
              }
            }
            Shape {   // the light segment circling the disc
              anchors.fill: parent
              RotationAnimation on rotation {
                from: 0; to: 360; loops: Animation.Infinite; running: comp.open
                duration: promptLabel.thinking ? 700 : (comp.asking ? 1800 : 5200)
              }
              ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.tint(comp.light, "#90ffffff")
                strokeWidth: 3
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 22; centerY: 22; radiusX: 20; radiusY: 20; startAngle: -90; sweepAngle: 70 }
              }
            }
          }
          TextInput {
            id: input
            // whatever room the label leaves; long input scrolls inside instead of spilling out
            width: parent.width - promptLabel.width - parent.spacing
            clip: true
            autoScroll: true
            anchors.verticalCenter: parent.verticalCenter
            color: "#e8fbff"
            font.family: Style.font.family
            font.pixelSize: 22
            focus: comp.open
            readOnly: comp.phase !== "input" && comp.phase !== "answer"
            cursorVisible: activeFocus && !readOnly
            selectionColor: comp.light
            text: comp.query
            onTextEdited: comp.query = text
            Keys.onPressed: function(event) {
              var n = comp.results.length
              if (event.key === Qt.Key_Escape) comp.close()
              else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) comp.enter()
              else if ((event.key === Qt.Key_Down || event.key === Qt.Key_Tab) && n) comp.selected = (comp.selected + 1) % n
              else if ((event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) && n) comp.selected = (comp.selected - 1 + n) % n
              else return
              event.accepted = true
            }
            Text {
              visible: !input.text && (comp.phase === "input" || comp.phase === "answer")
              width: input.width
              elide: Text.ElideRight
              text: "search apps, system, files  ·  end with ? to ask"
              color: Qt.rgba(comp.light.r, comp.light.g, comp.light.b, 0.4)
              font.family: input.font.family
              font.pixelSize: 17
              anchors.verticalCenter: parent.verticalCenter
            }
            Connections {
              target: comp
              function onOpenChanged() { if (comp.open) input.forceActiveFocus() }
            }
            readonly property bool waveInline: contentWidth < width * 0.5
            Wave {
              x: input.contentWidth + 28
              anchors.verticalCenter: parent.verticalCenter
              visible: comp.phase === "thinking" && input.waveInline
            }
          }
        }

        // search results
        Column {
          visible: (comp.phase === "input" || comp.phase === "answer") && comp.results.length > 0
          width: parent.width
          spacing: 2
          Repeater {
            model: comp.results
            Rectangle {
              id: row
              required property var modelData
              required property int index
              readonly property bool sel: index === comp.selected
              width: parent.width
              height: 40
              clip: true
              radius: 3
              color: sel ? Qt.rgba(comp.light.r, comp.light.g, comp.light.b, 0.22) : "transparent"
              border.width: sel ? 2 : 0
              border.color: comp.light
              Row {
                anchors.verticalCenter: parent.verticalCenter
                x: 10
                spacing: 12
                Text {
                  width: 56
                  text: modelData.kind
                  color: Qt.rgba(comp.light.r, comp.light.g, comp.light.b, 0.6)
                  font.family: Style.font.family
                  font.pixelSize: 12
                  font.bold: true
                  font.letterSpacing: 2
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  id: titleText
                  // the name takes what it needs, up to 45% of the row
                  width: Math.min(implicitWidth, row.width * 0.45)
                  elide: Text.ElideRight
                  text: modelData.title
                  color: sel ? "#ffffff" : "#d8f4fa"
                  font.family: Style.font.family
                  font.pixelSize: 16
                  font.bold: sel
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  // the description fills the rest of the row
                  width: Math.max(0, row.width - 10 - 56 - titleText.width - 2 * 12 - 14)
                  elide: Text.ElideRight
                  text: modelData.detail
                  color: Qt.rgba(comp.light.r, comp.light.g, comp.light.b, 0.55)
                  font.family: Style.font.family
                  font.pixelSize: 13
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                // Follow the pointer only when it really moves: results appearing under a
                // resting pointer must not steal the selection from the first result.
                onPositionChanged: function(mouse) {
                  var p = mapToItem(null, mouse.x, mouse.y)
                  if (Math.abs(p.x - comp.pointerX) + Math.abs(p.y - comp.pointerY) > 2 && comp.pointerX >= 0) comp.selected = index
                  comp.pointerX = p.x; comp.pointerY = p.y
                }
                onClicked: comp.openResult(modelData)
              }
            }
          }
        }

        Text {
          visible: (comp.phase === "input" || comp.phase === "answer") && comp.asking
          text: "◆ ENTER TO ASK THE COMPUTER"
          color: comp.light
          opacity: 0.7
          font.family: Style.font.family
          font.pixelSize: 11
          font.bold: true
          font.letterSpacing: 2
        }

        // waveform while the computer thinks: centered on its own line when the
        // question fills more than half the line (otherwise it sits right after it)
        Wave {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: comp.phase === "thinking" && !input.waveInline
        }

        Decrypt {
          visible: comp.say !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          target: comp.say.toUpperCase()
          duration: 500
          color: comp.light
          font.family: Style.font.family
          font.pixelSize: 16
          font.bold: true
          font.letterSpacing: 2
        }

        Column {
          visible: comp.commands.length > 0
          width: parent.width
          spacing: 4
          Repeater {
            model: comp.commands
            Text {
              required property var modelData
              width: parent.width
              elide: Text.ElideRight
              text: (comp.phase === "done" ? "✓ " : (modelData.safe ? "◆ " : "! ")) + modelData.cmd
              color: modelData.safe ? Qt.rgba(comp.light.r, comp.light.g, comp.light.b, 0.75) : comp.warn
              font.family: Style.font.family
              font.pixelSize: 11
            }
          }
        }

        Text {
          visible: comp.phase === "answer" && !comp.query.trim()
          text: "ASK A FOLLOW-UP  ·  ENTER / ESC TO CLOSE"
          color: comp.light
          opacity: 0.5
          font.family: Style.font.family
          font.pixelSize: 11
          font.letterSpacing: 2
        }

        Text {
          visible: comp.phase === "confirm"
          text: "UNVERIFIED COMMANDS  ·  ENTER TO EXECUTE  ·  ESC TO ABORT"
          color: comp.warn
          font.family: Style.font.family
          font.pixelSize: 11
          font.bold: true
          font.letterSpacing: 2
        }
      }
    }
    }
  }
}
