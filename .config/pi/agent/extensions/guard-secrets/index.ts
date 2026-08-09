import { isToolCallEventType, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { commitIncludesAllFlag, commitSegments, scanDiffContent, scanFilenames } from "./rules.ts";

/**
 * Guard: Secrets-at-commit — confirms before `git commit` if the
 * about-to-be-committed changes look like they contain a secret (API
 * key/token shape, private key header, or a protected filename like
 * `.env`).
 *
 * Deliberately does NOT touch `read`/`write`/`edit` tool calls: editing
 * `.env`-style files locally is completely normal and not itself risky.
 * The moment that actually matters is the commit — once something lands in
 * git history it's hard to fully remove — so that's the only place this
 * gates, and it confirms rather than silently blocking, since these
 * patterns can false-positive (an example/placeholder key in docs, etc.).
 *
 * String/pattern-matching logic lives in rules.ts (no pi imports,
 * unit-tested in rules.test.mjs). This file is the thin pi-facing wrapper:
 * the live `git diff` calls the scan needs, plus the `tool_call`
 * registration itself.
 */

async function findSecretHits(pi: ExtensionAPI, includeUnstaged: boolean, signal?: AbortSignal): Promise<string[]> {
	const diffArgs = includeUnstaged ? ["diff", "HEAD"] : ["diff", "--cached"];

	const nameResult = await pi.exec("git", [...diffArgs, "--name-only"], { timeout: 2_000, signal });
	const nameHits = nameResult.code === 0 ? scanFilenames(nameResult.stdout) : [];

	const diffResult = await pi.exec("git", diffArgs, { timeout: 2_000, signal });
	const contentHits = diffResult.code === 0 ? scanDiffContent(diffResult.stdout) : [];

	return [...nameHits, ...contentHits];
}

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx) => {
		if (!isToolCallEventType("bash", event)) return undefined;
		const command = event.input.command;
		if (typeof command !== "string") return undefined;

		const segments = commitSegments(command);
		if (segments.length === 0) return undefined;

		const includeUnstaged = segments.some(commitIncludesAllFlag);

		let hits: string[];
		try {
			hits = await findSecretHits(pi, includeUnstaged, ctx.signal);
		} catch {
			return undefined; // fail open — best-effort net, not a sandbox
		}
		if (hits.length === 0) return undefined;

		const summary = hits.join("\n  ");

		if (!ctx.hasUI) {
			return { block: true, reason: `Commit blocked (no UI to confirm): ${summary}` };
		}

		const choice = await ctx.ui.select(
			`⚠️ Possible secret in changes about to be committed:\n\n  ${summary}\n\nCommit anyway?`,
			["Yes", "No"],
		);
		if (choice !== "Yes") {
			return { block: true, reason: "Commit blocked by user (possible secret in staged changes)" };
		}
		return undefined;
	});
}
