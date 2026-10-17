import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import qs.Commons

// Lumen window effects, drawn on a click-through overlay above everything:
//   focus trail  a light cycle races from the old window to the new one, turning at
//                right angles like on the grid (off; set focusTrail: true to bring it back)
//   derez        a closing window breaks into glowing cells that flare and die
//   rez          an opening window is scanned in as a wireframe grid
//   live grid    the wallpaper: a live 3D Grid world (camera gliding over a reflective
//                grid floor, light cycles with light walls, glowing mountains);
//                its pulse follows CPU load, its horizon glows while Claude works
//                (pulsing harder while Claude waits). Always animating.
//   disc         light-disc app launcher around the pointer (Disc.qml, hold SUPER+D)
//   wake         "systems online" HUD boot-up on unlock and resume (Wake.qml)
//   surges       edge power surges and link pulses (Surge.qml)
//   computer     "Computer" command bar powered by Claude (Computer.qml, SUPER+ALT+C)
//   duel         two light discs duel over the Grid after 75 s idle (Duel.qml)
//   card swap    SUPER+TAB: the workspace drops back as a card, the next comes forward (Card.qml)
//   sentinels  while Omarchy's screensaver is up, Sentinels patrol over the grid
//                on top of it (keys and mouse still reach the screensaver to dismiss it)
Item {
  id: service
  property var shell: null

  readonly property color light: Color.accent
  property var windows: ({})        // address -> { x, y, w, h, ws }
  property var visibleWs: []        // workspace ids shown on any monitor
  property string focused: ""
  property var opened: ({})         // address -> time it opened (no trail onto a window that's rezzing)
  property var effects: []          // live effects: { id, kind, ... }
  property int nextId: 0
  property bool focusTrail: false   // light cycle between windows on focus change (off by request)
  property bool focusGlitch: true   // holo-glitch over the window that just got focus
  // Workspace switches (optional, off): the Grid camera surges forward and warp streaks rush outward.
  property bool workspaceWarp: false   // off: Hyprland's slide animation handles switches instead
  property real surge: 0
  property int lastWorkspace: -1
  NumberAnimation { id: surgeAnim; target: service; property: "surge"; duration: 900; easing.type: Easing.OutCubic }
  function warp() {
    surgeAnim.stop()
    surgeAnim.from = service.surge
    surgeAnim.to = service.surge + 14
    surgeAnim.start()
    service.spawn({ kind: "warp" })
  }
  function toplevelFor(addr) {
    var tops = Hyprland.toplevels.values
    for (var i = 0; i < tops.length; i++) if (service.addr(tops[i].address) === addr) return tops[i]
    return null
  }
  property var savers: ({})         // open screensaver windows
  readonly property bool saverUp: Object.keys(savers).length > 0
  property real saverTime: 0

  function addr(a) { return String(a || "").replace(/^0x/, "") }

  function onScreen(w) { return w && visibleWs.indexOf(w.ws) !== -1 }

  function spawn(effect) {
    effect.id = ++nextId
    effects = effects.concat([effect])
  }
  function finish(id) { effects = effects.filter(function(e) { return e.id !== id }) }

  // ---- window map (hyprctl), refreshed on window events and every 1.5 s ----
  property var pendingAfterRefresh: []
  function refresh(then) {
    if (then) pendingAfterRefresh = pendingAfterRefresh.concat([then])
    if (!query.running) query.running = true
  }
  Process {
    id: query
    command: ["bash", "-c", "printf '{\"clients\":%s,\"monitors\":%s}' \"$(hyprctl -j clients)\" \"$(hyprctl -j monitors)\""]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          var map = {}
          d.clients.forEach(function(c) {
            if (c.hidden || !c.mapped) return
            map[service.addr(c.address)] = { x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1], ws: c.workspace.id, cls: c.class }
          })
          var ws = []
          d.monitors.forEach(function(m) {
            ws.push(m.activeWorkspace.id)
            if (m.specialWorkspace && m.specialWorkspace.id) ws.push(m.specialWorkspace.id)
          })
          service.windows = map
          service.visibleWs = ws
        } catch (e) {}
        var todo = service.pendingAfterRefresh
        service.pendingAfterRefresh = []
        todo.forEach(function(fn) { fn() })
      }
    }
  }
  Timer { interval: 1500; running: true; repeat: true; triggeredOnStart: true; onTriggered: service.refresh() }
  Timer { id: settle; interval: 350; onTriggered: service.refresh() }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event.name, data = String(event.data || "")
      if (name === "activewindow") {
        service.focusedClass = data.split(",")[0]
      } else if (name === "configreloaded") {
        service.visionShown = false       // a reload clears the shader; apply again if needed
        service.syncVision()
      }
      if (name === "activewindowv2") {
        var to = service.addr(data), from = service.focused
        service.focused = to
        if (!from || !to || from === to) return
        var a = service.windows[from], b = service.windows[to]
        var justOpened = service.opened[to] && Date.now() - service.opened[to] < 600
        if (service.focusTrail && !justOpened && service.onScreen(a) && service.onScreen(b) && a.ws === b.ws)
          service.spawn({ kind: "trail", x1: a.x + a.w / 2, y1: a.y + a.h / 2, x2: b.x + b.w / 2, y2: b.y + b.h / 2 })
        if (service.focusGlitch && !justOpened && service.onScreen(b) && b.cls !== "org.omarchy.screensaver")
          service.spawn({ kind: "glitch", addr: to, x: b.x, y: b.y, w: b.w, h: b.h })
      } else if (name === "closewindow") {
        var gone = service.addr(data)
        if (service.savers[gone]) {
          var sv = Object.assign({}, service.savers); delete sv[gone]; service.savers = sv
          return
        }
        var w = service.windows[gone]
        if (service.onScreen(w)) service.spawn({ kind: "derez", x: w.x, y: w.y, w: w.w, h: w.h })
        settle.restart()
      } else if (name === "openwindow") {
        var id = service.addr(data.split(",")[0])
        if (data.split(",")[2] === "org.omarchy.screensaver") {
          var sa = Object.assign({}, service.savers); sa[id] = true; service.savers = sa
          return
        }
        var o = Object.assign({}, service.opened); o[id] = Date.now(); service.opened = o
        service.refresh(function() {
          var nw = service.windows[id]
          if (service.onScreen(nw)) service.spawn({ kind: "rez", x: nw.x, y: nw.y, w: nw.w, h: nw.h })
        })
        settle.restart()
      } else if (name === "workspacev2") {
        var wsId = parseInt(data.split(",")[0])
        if (service.workspaceWarp && service.lastWorkspace !== -1 && wsId !== service.lastWorkspace && wsId > 0) service.warp()
        service.lastWorkspace = wsId
        service.refresh()
      } else if (name === "movewindowv2" || name === "changefloatingmode"
                 || name === "fullscreen" || name === "focusedmonv2") {
        service.refresh()
      }
    }
  }

  // ---- grid vision (auto, per app) ----
  // While a window of one of the chosen apps is focused, the whole screen is tinted to the
  // theme accent (Hyprland screen shader written by lumen-gridvision); off otherwise.
  // Settings: ~/.config/omarchy/lumen-vision.json, edited by the eye icon in the bar.
  property string focusedClass: ""
  property var vision: ({ auto: false, apps: [] })
  property bool visionShown: false
  readonly property bool visionWanted: vision.auto === true && (vision.apps || []).indexOf(focusedClass) !== -1
  readonly property string visionShader: Quickshell.env("HOME") + "/.local/state/lumen/gridvision.glsl"
  onVisionWantedChanged: syncVision()
  function syncVision() {
    if (visionWanted === visionShown) return
    visionShown = visionWanted
    Quickshell.execDetached(["hyprctl", "eval", "hl.config({ decoration = { screen_shader = \"" + (visionWanted ? visionShader : "") + "\" } })"])
  }
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/lumen-vision.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { service.vision = JSON.parse(text()) } catch (e) {} }
  }
  Component.onCompleted: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/lumen-gridvision", "write"])

  // ---- music: the Grid pulses with whatever the speakers play ----
  // Beats, not loudness: the output peak compared with its own running average, so the
  // Grid pulses on transients instead of sitting at full glow while music plays.
  property real musicLevel: 0
  property real musicAvg: 0
  PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
  PwNodePeakMonitor {
    id: musicPeak
    node: Pipewire.defaultAudioSink
    enabled: true
  }
  Timer {
    interval: 33; repeat: true; running: true
    onTriggered: {
      var peak = Math.max(0, musicPeak.peak)
      service.musicAvg = service.musicAvg * 0.96 + peak * 0.04
      var target = Math.max(0, Math.min(1, (peak - service.musicAvg * 0.75) * 2.2))
      service.musicLevel = target > service.musicLevel ? target : Math.max(target, service.musicLevel * 0.88)
    }
  }

  // ---- live grid ----
  property real cpuLoad: 0
  property var cpuPrev: null
  property real agentState: 0      // 0 idle, 1 busy, 2 waiting
  property real gridTime: 0
  readonly property bool desktopVisible: Hyprland.focusedWorkspace !== null
                                         && Hyprland.focusedWorkspace.toplevels.values.length === 0

  FileView {
    id: procStat
    path: "/proc/stat"
    onLoaded: {
      var f = String(text()).split("\n")[0].trim().split(/\s+/).slice(1).map(Number)
      var idle = f[3] + (f[4] || 0), total = f.reduce(function(a, b) { return a + b }, 0)
      if (service.cpuPrev) {
        var dt = total - service.cpuPrev.total, di = idle - service.cpuPrev.idle
        service.cpuLoad = dt > 0 ? Math.max(0, Math.min(1, 1 - di / dt)) : 0
      }
      service.cpuPrev = { total: total, idle: idle }
    }
  }
  Process {
    id: agentProc
    command: [Quickshell.env("HOME") + "/.local/bin/lumen-agent-state", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        var s = String(text || "").trim()
        service.agentState = s === "wait" ? 2 : (s === "busy" ? 1 : 0)
      }
    }
  }
  Timer {
    interval: 1500; running: true; repeat: true; triggeredOnStart: true
    onTriggered: { procStat.reload(); if (!agentProc.running) agentProc.running = true }
  }
  // Live or paused (frozen frame): ~/.config/omarchy/lumen-wallpaper.json { "live": true },
  // toggled by the wallpaper button in the bar.
  property bool wallpaperLive: true
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/lumen-wallpaper.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { service.wallpaperLive = JSON.parse(text()).live !== false } catch (e) {} }
    onLoadFailed: service.wallpaperLive = true
  }
  Timer {   // ~30 fps while live (it shows through semi-transparent windows too); frozen when paused
    interval: 33; repeat: true; running: service.wallpaperLive
    onTriggered: service.gridTime += 0.033
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "lumen-grid"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      ShaderEffect {
        anchors.fill: parent
        property real time: service.gridTime
        property real load: service.wallpaperLive ? service.cpuLoad : 0
        property real agent: service.wallpaperLive ? service.agentState : 0
        property real surge: service.surge
        property real music: service.wallpaperLive ? service.musicLevel : 0
        property real horizon: 0.66
        property size size: Qt.size(width, height)
        property color color: service.light
        property color alert: Color.urgent
        // the whole wallpaper: a live 3D Grid world (opaque, replaces the static image)
        fragmentShader: Qt.resolvedUrl("shaders/world.frag.qsb")
        blending: false
      }
    }
  }

  Disc {}
  Wake { id: wakeHud }
  Surge { id: surgeFx }
  Duel { id: duelFx; saverUp: service.saverUp }
  Computer {}
  Card {}
  // `omarchy-shell lumenFx duel` previews the duel for 6 seconds
  SequentialAnimation {
    id: duelPreview
    NumberAnimation { target: duelFx; property: "fade"; from: 0; to: 1; duration: 800 }
    PauseAnimation { duration: 5000 }
    NumberAnimation { target: duelFx; property: "fade"; to: 0; duration: 400 }
  }

  IpcHandler {
    target: "lumenFx"
    function wake(): void { wakeHud.lastPlay = 0; wakeHud.play() }
    function surge(): void { surgeFx.powerIn() }
    function unplug(): void { surgeFx.powerOut() }
    function link(text: string): void { surgeFx.link(text || "UPLINK ESTABLISHED") }
    function duel(): void { duelFx.fade = 0; duelFx.time = 0; duelPreview.restart() }
  }

  // ---- Sentinel screensaver ----
  Timer { interval: 33; repeat: true; running: service.saverUp; onTriggered: service.saverTime += 0.033 }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "black"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "lumen-sentinels"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}
      visible: service.saverUp

      ShaderEffect {
        anchors.fill: parent
        property real time: service.saverTime
        property size size: Qt.size(width, height)
        property color color: service.light
        property color alert: service.light   // Sentinels in the theme color
        fragmentShader: Qt.resolvedUrl("shaders/saver.frag.qsb")
      }
    }
  }

  // ---- overlay ----
  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: overlay
      required property var modelData
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "lumen-fx"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}                  // click-through
      visible: service.effects.length > 0

      readonly property real ox: modelData.x
      readonly property real oy: modelData.y

      Repeater {
        model: service.effects
        delegate: Loader {
          required property var modelData
          sourceComponent: modelData.kind === "trail" ? trailFx : (modelData.kind === "glitch" ? glitchFx : (modelData.kind === "warp" ? warpFx : shaderFx))
          property var fx: modelData
          property real ox: overlay.ox
          property real oy: overlay.oy
        }
      }
    }
  }

  // Light-cycle focus trail: an L-shaped run, with a fading tail behind the head.
  Component {
    id: trailFx
    Item {
      id: trail
      readonly property var fx: parent.fx
      readonly property real x1: fx.x1 - parent.ox
      readonly property real y1: fx.y1 - parent.oy
      readonly property real x2: fx.x2 - parent.ox
      readonly property real y2: fx.y2 - parent.oy
      readonly property real len: Math.abs(x2 - x1) + Math.abs(y2 - y1)
      readonly property real tail: Math.min(len, 320)
      property real p: 0
      width: 1; height: 1

      component Run: ShapePath {
        property real sw: 2
        property real alpha: 1
        property real dash: trail.tail
        property color tone: service.light
        fillColor: "transparent"
        strokeColor: Qt.rgba(tone.r, tone.g, tone.b, alpha)
        strokeWidth: sw
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.MiterJoin
        strokeStyle: ShapePath.DashLine
        // the dash ends at the head, p * len along the path
        dashPattern: [dash / sw, (trail.len + trail.tail) / sw]
        dashOffset: (dash - trail.p * trail.len) / sw
        startX: trail.x1; startY: trail.y1
        PathLine { x: trail.x2; y: trail.y1 }
        PathLine { x: trail.x2; y: trail.y2 }
      }

      Shape {
        Run { sw: 10; alpha: 0.18 }
        Run { sw: 2.5; alpha: 0.8 }
        Run { sw: 3; dash: 26; tone: Qt.tint(service.light, "#b0ffffff") }
      }

      // arrival ring
      Rectangle {
        x: trail.x2 - width / 2; y: trail.y2 - height / 2
        width: 16 + 60 * ring.k; height: width; radius: width / 2
        color: "transparent"; border.width: 2; border.color: service.light
        opacity: ring.k > 0 ? 1 - ring.k : 0
        QtObject { id: ring; property real k: 0 }
      }

      SequentialAnimation {
        running: true
        NumberAnimation { target: trail; property: "p"; from: 0; to: 1; duration: Math.min(420, 160 + trail.len * 0.25); easing.type: Easing.InOutQuad }
        ParallelAnimation {
          NumberAnimation { target: ring; property: "k"; from: 0; to: 1; duration: 380; easing.type: Easing.OutCubic }
          NumberAnimation { target: trail; property: "opacity"; from: 1; to: 0; duration: 380 }
        }
        ScriptAction { script: service.finish(trail.fx.id) }
      }
    }
  }

  // Warp streaks over the whole screen for a workspace switch.
  Component {
    id: warpFx
    ShaderEffect {
      id: wfx
      readonly property var fx: parent.fx
      width: parent.parent ? parent.parent.width : 0
      height: parent.parent ? parent.parent.height : 0
      property real progress: 0
      property real seed: Math.random()
      property size size: Qt.size(width, height)
      property color color: service.light
      fragmentShader: Qt.resolvedUrl("shaders/warp.frag.qsb")
      SequentialAnimation {
        running: true
        NumberAnimation { target: wfx; property: "progress"; from: 0; to: 1; duration: 420; easing.type: Easing.OutQuad }
        ScriptAction { script: service.finish(wfx.fx.id) }
      }
    }
  }

  // Holo-glitch: a one-shot snapshot of the newly focused window, played back with a
  // color split, band jumps and scanlines that fade to reveal the real window.
  Component {
    id: glitchFx
    Item {
      id: gfx
      readonly property var fx: parent.fx
      readonly property var target: service.toplevelFor(fx.addr)
      x: fx.x - parent.ox; y: fx.y - parent.oy
      width: fx.w; height: fx.h
      property real progress: 0

      ScreencopyView {
        id: snap
        anchors.fill: parent
        captureSource: gfx.target ? gfx.target.wayland : null
        live: false
        visible: false
        onHasContentChanged: if (hasContent) play.start()
      }
      ShaderEffectSource { id: snapTex; sourceItem: snap; hideSource: true; live: false }
      ShaderEffect {
        anchors.fill: parent
        visible: snap.hasContent
        property var source: snapTex
        property real progress: gfx.progress
        property real seed: Math.random()
        property size size: Qt.size(width, height)
        property color color: service.light
        fragmentShader: Qt.resolvedUrl("shaders/glitch.frag.qsb")
      }
      SequentialAnimation {
        id: play
        NumberAnimation { target: gfx; property: "progress"; from: 0; to: 1; duration: 230; easing.type: Easing.OutQuad }
        ScriptAction { script: service.finish(gfx.fx.id) }
      }
      Timer { interval: 400; running: true; onTriggered: if (!snap.hasContent) service.finish(gfx.fx.id) }   // no snapshot: skip
    }
  }

  // Derez (mode 0) / rez (mode 1) over the window's rectangle.
  Component {
    id: shaderFx
    ShaderEffect {
      id: sfx
      readonly property var fx: parent.fx
      x: fx.x - parent.ox; y: fx.y - parent.oy
      width: fx.w; height: fx.h
      property real progress: 0
      property real mode: fx.kind === "rez" ? 1 : 0
      property real cell: 22
      property real seed: Math.random()
      property size size: Qt.size(width, height)
      property color color: service.light
      property color hole: Color.background
      fragmentShader: Qt.resolvedUrl("shaders/derez.frag.qsb")
      blending: true

      SequentialAnimation {
        running: true
        NumberAnimation { target: sfx; property: "progress"; from: 0; to: 1; duration: sfx.mode > 0.5 ? 650 : 320; easing.type: Easing.Linear }
        ScriptAction { script: service.finish(sfx.fx.id) }
      }
    }
  }
}
