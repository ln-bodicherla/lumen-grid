import QtQuick

// Text that decrypts into place: characters start as scrambled glyphs and lock in
// one by one, left to right, like a code being cracked in a hacker movie.
// Set `text`; it decrypts whenever the text changes (or call play()).
Text {
  id: root
  property string target: ""
  property int duration: 600            // ms until the last character locks in
  property string glyphs: "01<>/\\|=+*#%&$@ABCDEFXYZ◆▲▼◇░▒▓"
  property real progress: 1
  property int tick: 0                  // bumps every frame so the scramble keeps changing

  function play() { anim.restart() }
  onTargetChanged: play()

  text: {
    tick
    var n = target.length
    var locked = Math.floor(progress * n)
    var out = ""
    for (var i = 0; i < n; i++) {
      var ch = target.charAt(i)
      if (i < locked || ch === " ") out += ch
      else out += glyphs.charAt(Math.floor(Math.random() * glyphs.length))
    }
    return out
  }

  NumberAnimation on progress { id: anim; from: 0; to: 1; duration: root.duration; running: false }
  Timer { interval: 40; repeat: true; running: anim.running; onTriggered: root.tick++ }
}
