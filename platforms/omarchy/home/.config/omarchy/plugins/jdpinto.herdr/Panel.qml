import Quickshell
import Quickshell.Io
import "../jankeesvw.herdr" as Upstream

// Inherit upstream fixes instead of maintaining copies of its card/data script.
Upstream.Panel {
  id: root
  moduleName: "jdpinto.herdr"
  ipcTarget: "jdpinto.herdr"

  function openWithDefaultTerminal(session, pane) {
    if (!session || !validName(session.name) || opener.running) return
    if (session.remote === true && !validMachine(session.machineId)) return
    pendingKey = rowKey(session)
    opener.command = [Quickshell.env("HOME") + "/.local/bin/herdr-widget-open",
      JSON.stringify(session), pane || ""]
    opener.running = true
    dismiss()
  }

  function openSession(session) {
    openWithDefaultTerminal(session, "")
  }

  function focusAgent(session, agent) {
    if (!agent || !validPane(agent.pane)) { openSession(session); return }
    openWithDefaultTerminal(session, agent.pane)
  }

  Process {
    id: opener
    onExited: function(code) {
      root.pendingKey = ""
      if (code !== 0) console.warn("Herdr default-terminal launcher failed:", code)
      root.refresh()
    }
  }
}
