.pragma library

var ICON = "󰖟"

function rows(ctx, key) {
  if (ctx.scope && ctx.scope !== key) return []
  // Keystroke removes the configured prefix; never assume it remains "s".
  if (!ctx.command && ctx.scope !== key) return []
  var query = String(ctx.command ? ctx.command.rest || "" : ctx.query || "").trim()
  if (!query) return [{ id: "hint", title: "Type a web search", subtitle: "Enter a query after the prefix", icon: ICON,
    section: "Brave Search", tier: "item", score: 100, disabled: true, action: { type: "noop" } }]
  var url
  try { url = "https://search.brave.com/search?q=" + encodeURIComponent(query) }
  catch (e) { return [{ id: "invalid", title: "Query contains invalid text", icon: ICON,
    section: "Brave Search", tier: "item", score: 100, disabled: true, action: { type: "noop" } }] }
  return [{ id: "search", title: "Search Brave", subtitle: query, icon: ICON,
    section: "Brave Search", verb: "Search", tier: "item", score: 100, remember: false,
    action: { type: "url", url: url }, altVerb: "Copy search URL", altAction: { type: "copy", text: url } }]
}
