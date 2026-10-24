import QtQuick
import "core/WebSearch.js" as WebSearch

QtObject {
  id: root
  property var shell: null
  property var extension: null
  property string omarchyPath: ""
  readonly property string key: extension && extension.id ? String(extension.id) : "brave-search"
  readonly property var provider: ({
    apiVersion: 1,
    name: "Brave web search",
    icon: WebSearch.ICON,
    color: "#7fbbb3",
    description: "Search the web with Brave Search in the default browser",
    settings: [],
    query: function(ctx) { return WebSearch.rows(ctx, root.key) }
  })
}
