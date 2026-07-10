import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { CURSOR_MARKER, Key, matchesKey, truncateToWidth, type Component } from "@earendil-works/pi-tui";

/**
 * Lookback: read-only viewer for the current session's already-rendered
 * transcript.
 *
 * Capture strategy: calls `tui.render(width)` once at open time. That method
 * is the standard, public `Component` interface method the whole app tree
 * (including TUI itself, which extends Container) must implement — so this
 * returns byte-identical output to what pi already displays, without ever
 * touching `tui.children` or forcing a full clear/redraw. If that call ever
 * throws (future pi internals shift), we fall back to reconstructing text
 * from `ctx.sessionManager.getBranch()`, which only uses documented APIs.
 *
 * Never touches session/tree state. Never forces `requestRender(true)`, so
 * it never wipes terminal scrollback (unlike an alt-screen/tui.children-swap
 * approach would). Read-only: closing always hands you back to the real
 * editor with your draft intact, so you keep full autocomplete/paste/
 * multi-line editing there instead of a duplicated mini-composer.
 */

const HEADER_LINES = 2;
const FOOTER_LINES = 2;
const USER_BLOCK_MARKER = "\u0000"; // sentinel used only to measure theme.bg()'s wrapper

function flattenText(content: unknown): string {
	if (typeof content === "string") return content;
	if (Array.isArray(content)) {
		return content
			.filter((c: any) => c?.type === "text")
			.map((c: any) => c.text ?? "")
			.join("\n");
	}
	return "";
}

/** Fallback used only if `tui.render(width)` throws. Documented-API only. */
function reconstructFromSession(ctx: ExtensionContext): { lines: string[]; userStarts: number[] } {
	const entries = ctx.sessionManager.getBranch() as any[];
	const lines: string[] = [];
	const userStarts: number[] = [];
	for (const entry of entries) {
		if (entry.type !== "message") continue;
		const role = entry.message?.role;
		if (role === "user" || role === "assistant") {
			const text = flattenText(entry.message.content);
			if (!text.trim()) continue;
			if (role === "user") userStarts.push(lines.length);
			lines.push(`-- ${role.toUpperCase()} --`);
			lines.push(...text.split("\n"));
			lines.push("");
		}
	}
	if (lines.length === 0) lines.push("No messages yet in this session.");
	return { lines, userStarts };
}

function isSmartcaseInsensitive(query: string): boolean {
	return query === query.toLowerCase();
}

function findMatches(lines: string[], query: string): Array<{ line: number; col: number }> {
	if (!query) return [];
	const ci = isSmartcaseInsensitive(query);
	const needle = ci ? query.toLowerCase() : query;
	const matches: Array<{ line: number; col: number }> = [];
	for (let i = 0; i < lines.length; i++) {
		const haystack = ci ? lines[i].toLowerCase() : lines[i];
		let pos = 0;
		while (true) {
			const found = haystack.indexOf(needle, pos);
			if (found === -1) break;
			matches.push({ line: i, col: found });
			pos = found + Math.max(1, needle.length);
		}
	}
	return matches;
}

class LookbackComponent implements Component {
	private capturedLines: string[] = [];
	private capturedWidth = 0;
	private userMessageLines: number[] = [];
	private scrollOffset = 0;
	private searchMode = false;
	private searchQuery = "";
	private matches: Array<{ line: number; col: number }> = [];
	private currentMatch = -1;
	private fromFallback = false;

	constructor(
		private readonly tui: any,
		private readonly theme: any,
		private readonly ctx: ExtensionContext,
		private readonly done: () => void,
	) {
		this.capture(tui.terminal.columns);
		this.scrollOffset = this.maxScroll(); // start at the bottom, like pressing G
	}

	/** The exact ANSI background-color escape UserMessageComponent wraps itself
	 * in (via `theme.bg("userMessageBg", ...)`). AssistantMessageComponent never
	 * calls `.bg()` at all, so matching this substring in our own captured
	 * lines reliably identifies user-message lines specifically — without
	 * reaching into `tui.children` to inspect the component tree directly. */
	private getUserBgSignature(): string | undefined {
		try {
			const wrapped: string = this.theme.bg("userMessageBg", USER_BLOCK_MARKER);
			const idx = wrapped.indexOf(USER_BLOCK_MARKER);
			return idx > 0 ? wrapped.slice(0, idx) : undefined;
		} catch {
			return undefined;
		}
	}

	private capture(width: number): void {
		try {
			if (typeof this.tui.render !== "function") throw new Error("tui.render unavailable");
			const rendered: string[] = this.tui.render(width);
			const signature = this.getUserBgSignature();
			const cleaned: string[] = [];
			const userStarts: number[] = [];
			let inUserBlock = false;
			for (const raw of rendered) {
				const isUserLine = signature !== undefined && raw.includes(signature);
				if (isUserLine && !inUserBlock) userStarts.push(cleaned.length);
				inUserBlock = isUserLine;
				cleaned.push(raw.replaceAll(CURSOR_MARKER, ""));
			}
			this.capturedLines = cleaned;
			this.userMessageLines = userStarts;
			this.fromFallback = false;
		} catch {
			const { lines, userStarts } = reconstructFromSession(this.ctx);
			this.capturedLines = lines;
			this.userMessageLines = userStarts;
			this.fromFallback = true;
		}
		this.capturedWidth = width;
	}

	private vh(): number {
		return Math.max(1, this.tui.terminal.rows - HEADER_LINES - FOOTER_LINES);
	}

	private maxScroll(): number {
		return Math.max(0, this.capturedLines.length - this.vh());
	}

	private scrollBy(delta: number): void {
		this.scrollOffset = Math.max(0, Math.min(this.maxScroll(), this.scrollOffset + delta));
		this.tui.requestRender();
	}

	private recomputeMatches(): void {
		this.matches = findMatches(this.capturedLines, this.searchQuery);
		this.currentMatch = this.matches.length > 0 ? 0 : -1;
		if (this.currentMatch >= 0) this.jumpToMatch(this.currentMatch);
	}

	private jumpToMatch(idx: number): void {
		const m = this.matches[idx];
		if (!m) return;
		const vh = this.vh();
		this.scrollOffset = Math.max(0, Math.min(this.maxScroll(), m.line - Math.floor(vh / 2)));
	}

	private gotoMatch(dir: 1 | -1): void {
		if (this.matches.length === 0) return;
		this.currentMatch = (this.currentMatch + dir + this.matches.length) % this.matches.length;
		this.jumpToMatch(this.currentMatch);
		this.tui.requestRender();
	}

	/** Index (1-based) of the user message the current scroll position sits
	 * within, and the total count — for the "msg N/M" status readout. */
	private currentUserMessagePosition(): { index: number; total: number } {
		const total = this.userMessageLines.length;
		if (total === 0) return { index: 0, total: 0 };
		let index = 0;
		for (let i = 0; i < total; i++) {
			if (this.userMessageLines[i] <= this.scrollOffset) index = i;
			else break;
		}
		return { index: index + 1, total };
	}

	private jumpToUserMessage(dir: 1 | -1): void {
		if (this.userMessageLines.length === 0) return;
		if (dir === 1) {
			const next = this.userMessageLines.find((l) => l > this.scrollOffset);
			this.scrollOffset = next !== undefined ? Math.min(next, this.maxScroll()) : this.maxScroll();
		} else {
			const prior = this.userMessageLines.filter((l) => l < this.scrollOffset);
			this.scrollOffset = prior.length > 0 ? prior[prior.length - 1] : 0;
		}
		this.tui.requestRender();
	}

	handleInput(data: string): void {
		if (this.searchMode) {
			if (matchesKey(data, Key.escape)) {
				this.searchMode = false;
				this.tui.requestRender();
				return;
			}
			if (matchesKey(data, Key.enter)) {
				this.searchMode = false;
				this.tui.requestRender();
				return;
			}
			if (matchesKey(data, Key.backspace)) {
				this.searchQuery = this.searchQuery.slice(0, -1);
				this.recomputeMatches();
				this.tui.requestRender();
				return;
			}
			if (data.length === 1 && data >= " ") {
				this.searchQuery += data;
				this.recomputeMatches();
				this.tui.requestRender();
			}
			return;
		}

		if (matchesKey(data, Key.escape) || data === "q") {
			this.done();
			return;
		}
		if (data === "/") {
			this.searchMode = true;
			this.searchQuery = "";
			this.matches = [];
			this.currentMatch = -1;
			this.tui.requestRender();
			return;
		}
		if (data === "n") {
			this.gotoMatch(1);
			return;
		}
		if (data === "N") {
			this.gotoMatch(-1);
			return;
		}
		if (data === "g") {
			this.scrollOffset = 0;
			this.tui.requestRender();
			return;
		}
		if (data === "G") {
			this.scrollOffset = this.maxScroll();
			this.tui.requestRender();
			return;
		}
		if (data === "J") {
			this.jumpToUserMessage(1);
			return;
		}
		if (data === "K") {
			this.jumpToUserMessage(-1);
			return;
		}
		if (data === "j" || matchesKey(data, Key.down)) {
			this.scrollBy(1);
			return;
		}
		if (data === "k" || matchesKey(data, Key.up)) {
			this.scrollBy(-1);
			return;
		}
		if (matchesKey(data, Key.pageDown) || matchesKey(data, Key.ctrl("d"))) {
			this.scrollBy(this.vh() - 1);
			return;
		}
		if (matchesKey(data, Key.pageUp) || matchesKey(data, Key.ctrl("u"))) {
			this.scrollBy(-(this.vh() - 1));
			return;
		}
	}

	render(width: number): string[] {
		if (width !== this.capturedWidth) {
			// Terminal resized: re-snapshot at the new width using the same
			// safe, public, read-only method. No forced full redraw needed.
			this.capture(width);
			this.scrollOffset = Math.min(this.scrollOffset, this.maxScroll());
		}

		const th = this.theme;
		const vh = this.vh();
		const total = this.capturedLines.length;
		const lines: string[] = [];

		const badge = this.fromFallback ? " (reconstructed)" : "";
		const pos = this.currentUserMessagePosition();
		const posText = pos.total > 0 ? ` · msg ${pos.index}/${pos.total}` : "";
		const title = ` Lookback${badge} — lines ${this.scrollOffset + 1}-${Math.min(this.scrollOffset + vh, total)} of ${total}${posText} `;
		lines.push(truncateToWidth(th.fg("accent", title), width));

		const visible = this.capturedLines.slice(this.scrollOffset, this.scrollOffset + vh);
		for (const line of visible) lines.push(truncateToWidth(line, width));
		for (let i = visible.length; i < vh; i++) lines.push("");

		if (this.searchMode) {
			lines.push(truncateToWidth(th.fg("accent", ` /${this.searchQuery}█`), width));
		} else if (this.matches.length > 0) {
			lines.push(
				truncateToWidth(
					th.fg("dim", ` ${this.currentMatch + 1}/${this.matches.length} matches · n/N next/prev`),
					width,
				),
			);
		} else {
			lines.push(
				truncateToWidth(th.fg("dim", " j/k scroll · J/K jump message · g/G top/bottom · / search · q/esc close"), width),
			);
		}

		return lines;
	}

	invalidate(): void {}
}

async function openLookback(ctx: ExtensionContext): Promise<void> {
	if (!ctx.hasUI) return;
	if (!ctx.isIdle()) {
		ctx.ui.notify("Wait for the agent to finish before opening lookback", "warning");
		return;
	}

	const draft = ctx.ui.getEditorText();

	await ctx.ui.custom<void>(
		(tui, theme, _keybindings, done) => new LookbackComponent(tui, theme, ctx, done),
		{
			overlay: true,
			overlayOptions: { anchor: "center", width: "100%", maxHeight: "100%", margin: 0 },
		},
	);

	// Read-only viewer never changes the draft; restore it defensively in
	// case opening/closing the overlay ever touches editor state.
	ctx.ui.setEditorText(draft);
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("lookback", {
		description: "Read-only viewer for the current session transcript (no branching, no history changes)",
		handler: async (_args, ctx) => openLookback(ctx),
	});

	pi.registerShortcut("alt+r", {
		description: "Open lookback (read-only session viewer)",
		handler: async (ctx) => openLookback(ctx),
	});
}
