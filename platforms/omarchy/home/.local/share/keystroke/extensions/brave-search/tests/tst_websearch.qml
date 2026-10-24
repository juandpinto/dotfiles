import QtQuick
import QtTest
import "../core/WebSearch.js" as WebSearch

TestCase {
  name: "BraveWebSearch"

  function request(text) { return { query: "s " + text, scope: "", command: { id: "search", prefix: "s", rest: text } } }

  function test_explicit_search_url() {
    var row = WebSearch.rows(request("Asahi Linux"), "brave-search")[0]
    compare(row.action, { type: "url", url: "https://search.brave.com/search?q=Asahi%20Linux" })
    compare(row.altAction, { type: "copy", text: row.action.url })
    compare(row.remember, false)
  }

  function test_special_characters_cannot_change_the_destination() {
    var query = "C++ & pandas #1? $(touch /tmp/not-a-command)"
    var row = WebSearch.rows(request(query), "brave-search")[0]
    compare(row.action.url, "https://search.brave.com/search?q=" + encodeURIComponent(query))
    verify(row.action.url.indexOf("%26") >= 0)
    verify(row.action.url.indexOf("%23") >= 0)
    compare(row.action.type, "url")
  }

  function test_unicode_and_whitespace() {
    var row = WebSearch.rows(request("  café 日本語  "), "brave-search")[0]
    compare(row.subtitle, "café 日本語")
    compare(row.action.url, "https://search.brave.com/search?q=caf%C3%A9%20%E6%97%A5%E6%9C%AC%E8%AA%9E")
  }

  function test_empty_request_is_not_activated() {
    var row = WebSearch.rows(request("   "), "brave-search")[0]
    verify(row.disabled)
    compare(row.action.type, "noop")
  }

  function test_unrelated_root_queries_and_scopes_are_ignored() {
    compare(WebSearch.rows({ query: "private working text", scope: "", command: null }, "brave-search"), [])
    compare(WebSearch.rows({ query: "docs", scope: "files", command: null }, "brave-search"), [])
  }

  function test_renamed_prefix_is_owned_by_host() {
    var ctx = { query: "web test", scope: "", command: { prefix: "web", rest: "test" } }
    compare(WebSearch.rows(ctx, "brave-search")[0].subtitle, "test")
  }

  function test_provider_scope_and_stable_ids() {
    var a = WebSearch.rows({ query: "first", scope: "brave-search", command: null }, "brave-search")[0]
    var b = WebSearch.rows(request("second"), "brave-search")[0]
    compare(a.id, b.id)
    compare(a.subtitle, "first")
  }

  function test_service_loads() {
    var component = Qt.createComponent("../Service.qml")
    compare(component.status, Component.Ready, component.errorString())
    var service = component.createObject(null, { extension: { id: "brave-search" } })
    verify(service !== null)
    compare(service.provider.query(request("test"))[0].title, "Search Brave")
    service.destroy()
  }
}
