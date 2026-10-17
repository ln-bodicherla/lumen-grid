import QtQuick

// An empty gap the width of the MacBook notch. Anchored at the center of the bar so the
// modules on either side sit right beside the notch instead of under it.
Item {
  property var bar
  property string moduleName
  property var settings
  implicitWidth: settings && settings.width ? settings.width : 230
  implicitHeight: bar ? bar.barSize : 26
}
