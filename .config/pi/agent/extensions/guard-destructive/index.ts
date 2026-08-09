import { isToolCallEventType, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
	checkTier1Patterns,
	hasForcePushWithoutExplicitBranch,
	isTier2Destructive,
} from "./rules.ts";

/**
 * Guard: Destructive — a bash safety net with two tiers.
 *
 * Tier 1 (hard block, no override, no confirm): commands with no
 * legitimate everyday use, where even a confirm prompt adds risk (a tired
 * "yes" click) rather than safety. These never run, regardless of UI
 * availability.
 *
 * Tier 2 (confirm): commands that are *plausibly* destructive but have
 * completely normal everyday uses (`rm -rf node_modules`, `sudo`, etc.).
 * These pause for an interactive yes/no via `ctx.ui.select`. If there's no
 * UI to ask (print/JSON/RPC-without-UI mode), they fail closed (block)
 * rather than silently proceeding.
 *
 * This is a best-effort net, not a sandbox (see pi's security.md). String
 * matching on a shell command can be evaded by someone determined to evade
 * it; the goal here is to catch the ordinary "oops" case, not to be
 * adversarial-proof.
 *
 * All string-matching logic lives in rules.ts (no pi imports, unit-tested
 * in rules.test.mjs). This file is the thin pi-facing wrapper: the one
 * live `git` lookup tier 1 needs (is the current branch main/master, for a
 * force-push with no branch named on the command line), plus the
 * `tool_call` registration itself.
 */

async function checkTier1(pi: ExtensionAPI, command: string): Promise<{ reason: string } | undefined> {
	const patternMatch = checkTier1Patterns(command);
	if (patternMatch) return patternMatch;

	if (hasForcePushWithoutExplicitBranch(command)) {
		try {
			const result = await pi.exec("git", ["branch", "--show-current"], { timeout: 1_000 });
			const branch = result.code === 0 ? result.stdout.trim() : "";
			if (branch === "main" || branch === "master") {
				return { reason: "Blocked: force-push to main/master is not allowed." };
			}
		} catch {
			// fail open on lookup failure — best-effort net, not a sandbox
		}
	}
	return undefined;
}

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx) => {
		if (!isToolCallEventType("bash", event)) return undefined;
		const command = event.input.command;
		if (typeof command !== "string" || command.trim() === "") return undefined;

		const tier1 = await checkTier1(pi, command);
		if (tier1) return { block: true, reason: tier1.reason };

		if (!isTier2Destructive(command)) return undefined;

		if (!ctx.hasUI) {
			return { block: true, reason: "Potentially destructive command blocked (no UI available to confirm)." };
		}

		const choice = await ctx.ui.select(`⚠️ Potentially destructive command:\n\n  ${command}\n\nAllow?`, [
			"Yes",
			"No",
		]);
		if (choice !== "Yes") {
			return { block: true, reason: "Blocked by user" };
		}
		return undefined;
	});
}
