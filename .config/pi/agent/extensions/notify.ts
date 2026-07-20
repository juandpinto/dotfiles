import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

/**
 * Notify: OS-level notification when pi finishes responding and is waiting
 * on you, so you can tab away (or detach) without missing that it's done.
 *
 * Delivery: writes the WezTerm/xterm "OSC 777" notify escape sequence to
 * stderr (never stdout, so it can't interleave with pi's own TUI frames),
 * wrapped in a tmux DCS passthrough when running inside tmux (requires
 * `set -g allow-passthrough on` in tmux.conf — already set in this repo's
 * tmux.conf). OSC 777 is what WezTerm implements natively; if you switch
 * terminals later, check whether it understands OSC 777 before relying on
 * this again.
 *
 * Debounce: `agent_settled` arms a short delay timer rather than notifying
 * immediately. This is not about detecting whether you're paying attention
 * (you'd rather get a prompt, occasionally redundant notification than a
 * late one) — it's just a small grace window so that if pi immediately
 * continues on its own (auto-retry, auto-compaction, a queued follow-up)
 * before the delay elapses, that in-progress work doesn't get mistaken for
 * "done" and reported as such. `agent_settled` should already guarantee no
 * such continuation happens, so in practice this window is a defensive
 * backstop, not something expected to trigger often.
 *
 * Deliberately built only on documented, stable pi extension APIs
 * (`pi.on`, `ctx.isIdle()`, `ctx.mode`, `ctx.sessionManager`, `pi.exec`) —
 * no reach into undocumented internals, so it should keep working across
 * pi upgrades without maintenance.
 */

// ── Tuning ───────────────────────────────────────────────────────────────
// Grace window before a notification fires. Keep this small (seconds, not
// tens of seconds) — see "Debounce" above for why it exists at all.
const IDLE_DELAY_MS = 3_000;
// Max length of the assistant-message preview included in the notification.
const PREVIEW_MAX_CHARS = 160;

// ── Terminal delivery ────────────────────────────────────────────────────

/** Wrap an escape sequence for tmux DCS passthrough (no-op outside tmux). */
function wrapForTmux(sequence: string): string {
	if (!process.env.TMUX) return sequence;
	// DCS passthrough requires doubling any ESC bytes inside the payload.
	const escaped = sequence.replaceAll("\x1b", "\x1b\x1b");
	return `\x1bPtmux;${escaped}\x1b\\`;
}

/** Send a desktop notification via OSC 777 (WezTerm, Ghostty, iTerm2, rxvt-unicode). */
function notify(title: string, body: string): void {
	const sequence = `\x1b]777;notify;${title};${body}\x07`;
	process.stderr.write(wrapForTmux(sequence));
}

// ── Context for the notification body ───────────────────────────────────

/** Best-effort tmux session name (e.g. "work"), or undefined if unavailable. */
async function getTmuxSessionName(pi: ExtensionAPI): Promise<string | undefined> {
	if (!process.env.TMUX) return undefined;
	try {
		const result = await pi.exec("tmux", ["display-message", "-p", "#S"], { timeout: 500 });
		const name = result.stdout.trim();
		return name.length > 0 ? name : undefined;
	} catch {
		return undefined;
	}
}

/** Flatten the last assistant message's text blocks into a single preview string. */
function getLastAssistantPreview(ctx: ExtensionContext): string | undefined {
	const entries = ctx.sessionManager.getBranch();
	for (let i = entries.length - 1; i >= 0; i--) {
		const entry = entries[i];
		if (entry.type !== "message" || entry.message.role !== "assistant") continue;
		const text = entry.message.content
			.filter((block): block is { type: "text"; text: string } => block.type === "text")
			.map((block) => block.text)
			.join(" ")
			.trim();
		if (text.length === 0) return undefined;
		return text.length > PREVIEW_MAX_CHARS ? `${text.slice(0, PREVIEW_MAX_CHARS - 1)}…` : text;
	}
	return undefined;
}

// ── Circuit breaker ──────────────────────────────────────────────────────

let pendingTimer: ReturnType<typeof setTimeout> | null = null;

function cancelPending(): void {
	if (pendingTimer) {
		clearTimeout(pendingTimer);
		pendingTimer = null;
	}
}

function scheduleNotify(pi: ExtensionAPI, ctx: ExtensionContext): void {
	cancelPending();

	// Only notify for real interactive terminal sessions: skip RPC/print/json
	// modes, where writing raw escape codes to stderr could corrupt output
	// another program is consuming.
	if (ctx.mode !== "tui") return;
	// If another extension immediately kicked off more work, pi isn't
	// actually done — don't schedule a premature "finished" notification.
	if (!ctx.isIdle()) return;

	pendingTimer = setTimeout(async () => {
		pendingTimer = null;
		const [sessionName, preview] = await Promise.all([
			getTmuxSessionName(pi),
			Promise.resolve(getLastAssistantPreview(ctx)),
		]);
		const title = sessionName ? `Pi (${sessionName})` : "Pi";
		notify(title, preview ?? "Ready for input");
	}, IDLE_DELAY_MS);

	// Don't keep the process alive just for this timer.
	pendingTimer.unref();
}

export default function (pi: ExtensionAPI) {
	pi.on("agent_settled", (_event, ctx) => scheduleNotify(pi, ctx));

	// Cancel if pi is (or becomes) not actually done within the debounce
	// window: you submitting a new message, or pi starting another run on
	// its own (auto-retry, auto-compaction, a queued follow-up).
	pi.on("input", () => cancelPending());
	pi.on("agent_start", () => cancelPending());

	pi.on("session_shutdown", () => cancelPending());
}
