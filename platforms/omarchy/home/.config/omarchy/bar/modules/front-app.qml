import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons as Commons

// The focused app's name, as the Mac bar's front_app: muted, after the
// workspaces. Web apps show their launcher's name; the window title is the
// tooltip. A custom bar module (shell.json: { "id": "front-app", "type": "qml" }).
Item {
  id: root

  property var bar
  property string moduleName
  property var settings

  readonly property var toplevel: ToplevelManager.activeToplevel
  readonly property string appId: toplevel ? String(toplevel.appId || "") : ""
  readonly property string title: toplevel ? String(toplevel.title || "") : ""
  readonly property int maxWidth: settings && settings.maxWidth ? Number(settings.maxWidth) : 180

  function webAppName(id) {
    var match = id.match(/^(?:brave|chrome|chromium|msedge|vivaldi)-([^_]+)__.*-Default$/)
    if (!match) return ""
    var host = match[1].replace(/^www\./, "")
    var entries = DesktopEntries.applications.values
    var labels = host.split(".").slice(0, -1)
    for (var i = 0; i < entries.length; i++) {
      var exec = String(entries[i].execString || "")
      if (new RegExp("https?://(www\\.)?" + host.replace(/\./g, "\\.") + "([/\\s\"']|$)").test(exec)) return entries[i].name
      // Web apps opened through a handler script (HEY, Zoom) carry no URL.
      var handler = exec.match(/omarchy-webapp-handler-([a-z0-9-]+)/)
      if (handler && labels.indexOf(handler[1]) !== -1) return entries[i].name
    }
    return host
  }

  readonly property string appName: {
    if (!appId) return ""
    var web = webAppName(appId)
    if (web) return web
    var entry = DesktopEntries.byId(appId) || DesktopEntries.byId(appId.toLowerCase()) || DesktopEntries.heuristicLookup(appId)
    if (entry && entry.name) return entry.name
    // Omarchy's TUI launcher names terminal windows org.omarchy.<program>:
    // show the program's own launcher name (aerc, Yazi), else the program.
    var tui = appId.match(/^org\.omarchy\.(.+)$/)
    if (!tui) return appId
    var program = DesktopEntries.byId(tui[1])
    return program && program.name ? program.name : tui[1]
  }

  visible: appName !== "" && bar && !bar.vertical
  implicitWidth: visible ? Math.min(maxWidth, label.implicitWidth) + Commons.Style.space(8) * 2 : 0
  implicitHeight: bar ? bar.barSize : 26

  Behavior on implicitWidth {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  Text {
    id: label
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: Commons.Style.space(8)
    width: Math.min(root.maxWidth, implicitWidth)
    textFormat: Text.PlainText
    text: root.appName
    color: Commons.Color.muted
    font.family: root.bar ? root.bar.fontFamily : Commons.Style.font.family
    font.pixelSize: Commons.Style.font.body
    elide: Text.ElideRight
    renderType: Text.NativeRendering
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onEntered: if (root.bar && root.title) root.bar.showTooltip(root, root.title)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
