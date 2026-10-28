import QtQuick
import QtQuick.Shapes
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui

// The menu button with the jdp monogram (the fastfetch/About logo) in place of
// Omarchy's glyph. It stands in for Keystroke's bar widget, which draws that
// glyph from the omarchy font, so it keeps the same clicks (left toggles the
// menu, right opens a terminal) and the palette's bar items after the button
// (the Timer extension's countdown). Taking Keystroke's widget off the bar
// leaves the palette itself loaded. A custom bar module
// (shell.json: { "id": "jdp-menu", "type": "qml" }); not hot-reloaded, so run
// `omarchy restart shell` after editing.
Item {
  id: root

  property var bar
  property string moduleName
  property var settings

  readonly property bool vertical: bar ? bar.vertical : false

  // Keystroke's running palette, found the way its own bar widget finds it.
  readonly property var keystroke: {
    var shell = root.bar ? root.bar.shell : null
    var loaders = shell && shell.panelLoaders ? shell.panelLoaders : null
    var loader = loaders ? loaders["evindor.keystroke"] : null
    return loader && loader.item ? loader.item : null
  }
  readonly property var items: root.keystroke && root.keystroke.barList ? root.keystroke.barList : []

  // The p is drawn in the theme's green, which the shell's Color object does
  // not carry, so it is read from the theme file (as the workspace rainbow
  // does) and re-read when the shell's own colors change on a theme switch.
  property color green: button.foreground
  FileView {
    id: paletteFile
    path: Commons.Color.currentThemePath + "/colors.toml"
    watchChanges: false
    printErrors: false
    onLoaded: {
      var match = text().match(/^\s*green\s*=\s*["']?(#[0-9A-Fa-f]{6})/m)
      root.green = match ? match[1] : button.foreground
    }
  }
  Connections {
    target: Commons.Color
    function onForegroundChanged() { paletteFile.reload() }
    function onAccentChanged() { paletteFile.reload() }
  }

  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  function toggleMenu() {
    if (root.bar) root.bar.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
  }

  // An item's payload is what its provider wants the palette opened with;
  // without one the click toggles the menu.
  function openItem(item) {
    if (!root.bar) return
    if (item && item.payload) root.bar.run("omarchy-shell shell summon omarchy.menu " + Commons.Util.shellQuote(JSON.stringify(item.payload)))
    else root.toggleMenu()
  }

  Row {
    id: layout

    WidgetButton {
      id: button
      bar: root.bar
      hasVisualContent: true
      horizontalMargin: 7.5
      fixedWidth: root.vertical ? -1 : mark.width + scaledHorizontalMargin * 2
      fixedHeight: root.vertical ? mark.height + scaledVerticalPadding * 2 : -1
      onPressed: function(pressedButton) {
        if (!root.bar) return
        if (pressedButton === Qt.RightButton) root.bar.run("xdg-terminal-exec")
        else root.toggleMenu()
      }

      // The monogram: j, d and p sharing one stem and one bowl, leaning 12
      // degrees, with 45-degree cuts on the d's tip and the j's hook. The p
      // (stem, bowl, both bowl sides) is green; j's dot and foot and d's
      // ascender take the bar text color. Geometry is the N9 draft's, in its
      // own units before the shear (the SVG's 9-unit stroke), with the shear
      // as a transform about the foot so the foot stays where the box is.
      Item {
        id: mark
        readonly property real scale: Commons.Style.font.body / 40   // 0.3 at the default 12 px: ~22 px tall
        readonly property real lean: Math.tan(12 * Math.PI / 180)
        readonly property real unitsTall: 72                           // y 4..76
        readonly property real unitsWide: 46 + unitsTall * lean        // x 13..59 before the shear

        width: unitsWide * scale
        height: unitsTall * scale
        x: Math.round((button.width - width) / 2)
        y: Math.round((button.height - height) / 2)

        Shape {
          anchors.fill: parent
          preferredRendererType: Shape.CurveRenderer
          // Map SVG units to the box: shift so x=13,y=4 is the origin, scale,
          // then shear about the bottom edge (y = 76 before the shift).
          transform: [
            Translate { x: -13; y: -4 },
            Matrix4x4 { matrix: Qt.matrix4x4(1, -mark.lean, 0, mark.lean * 72, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) },
            Scale { xScale: mark.scale; yScale: mark.scale }
          ]

          // p: the outline with the counter as a second subpath (even-odd).
          ShapePath {
            fillColor: root.green
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill
            PathSvg { path: "M23 22 H59 V55 H32 V67 H23 Z M32 31 H50 V46 H32 Z" }
          }
          // j dot, d ascender with its 45-degree tip, j hook and foot.
          ShapePath {
            fillColor: button.foreground
            strokeWidth: -1
            PathSvg { path: "M23 10 H32 V19 H23 Z  M50 13 L59 4 V22 H50 Z  M23 67 H32 L23 76 H13 L15 67 Z" }
          }
        }
      }
    }

    Repeater {
      model: root.items
      delegate: WidgetButton {
        required property var modelData
        bar: root.bar
        visible: !root.vertical && text !== ""
        text: String(modelData.text || "")
        tooltipText: String(modelData.tooltip || "")
        horizontalMargin: 5
        onPressed: function(pressedButton) { root.openItem(modelData) }
      }
    }
  }
}
