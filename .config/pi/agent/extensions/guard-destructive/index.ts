import { accessSync, constants, lstatSync } from "node:fs";
import { join } from "node:path";
import { isToolCallEventType, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
	checkTier1Patterns,
	checkTier2,
	DEFAULT_SAFE_ROOTS,
	hasForcePushWithoutExplicitBranch,
	hasPermanentDeleteMarker,
} from "./rules.ts";

// $TMPDIR (macOS's per-session temp dir, e.g. /var/folders/xx/.../T/) is
// also a safe-to-auto-allow root, alongside the fixed defaults in rules.ts.
const SAFE_ROOTS = process.env.TMPDIR
	? [...DEFAULT_SAFE_ROOTS, process.env.TMPDIR.endsWith("/") ? process.env.TMPDIR : `${process.env.TMPDIR}/`]
	: DEFAULT_SAFE_ROOTS;

/**
 * Guard: Destructive — a bash safety net with two tiers.
 *
 * Tier 1 (hard block, no override, no confirm): commands whose literal form
 * cannot safely reveal their scope, or whose effect has no legitimate everyday
 * use, where even a confirm prompt adds risk (a tired "yes" click) rather
 * than safety. This includes recursive forced deletion
 * whose target comes from a shell variable or substitution, and process
 * termination whose PID set comes from shell expansion, process enumeration,
 * xargs, PID 0, or a process group: the literal command cannot safely reveal
 * its real scope. These never run, regardless of UI availability.
 *
 * Tier 2 (review): commands that are *plausibly* destructive but have
 * completely normal everyday uses.
 * - `rm -rf` on a path that isn't recognizably disposable is blocked with a
 *   message telling the agent to use the trash command instead, which is
 *   recoverable. The agent can ask the user in conversation when a delete
 *   must be permanent; once agreed, `PI_PERMANENT_DELETE=1 rm -rf <path>`
 *   routes to the interactive yes/no below. If no trash command is
 *   installed, every such rm goes to the interactive confirm.
 * - Broad permission changes (`chmod 777`) pause for an interactive yes/no
 *   via `ctx.ui.select`.
 * If there's no UI to ask (print/JSON/RPC-without-UI mode), the confirm
 * cases fail closed (block) rather than silently proceeding.
 *
 * This is a best-effort net, not a sandbox (see pi's security.md). String
 * matching on a shell command can be evaded by someone determined to evade
 * it; the goal here is to catch the ordinary "oops" case, not to be
 * adversarial-proof.
 *
 * All string-matching logic lives in rules.ts (no pi imports, unit-tested
 * in rules.test.mjs). This file is the thin pi-facing wrapper: the I/O
 * tier 1 needs (is the current branch main/master, for a force-push with
 * no branch named on the command line), the I/O tier 2 needs (does the rm
 * target exist; which trash command is installed), plus the `tool_call`
 * registration itself.
 */

/**
 * The trash command the agent should use instead of `rm -rf`. `trash` is
 * macOS's built-in (14+) or Homebrew's, and trash-cli's alias on Linux;
 * both put files in the desktop's normal Trash. `gio trash` is glib's,
 * present on any Linux desktop. Undefined means neither is installed.
 */
function detectTrashCommand(): string | undefined {
	const dirs = (process.env.PATH ?? "").split(":").filter(Boolean);
	const onPath = (name: string) =>
		dirs.some((dir) => {
			try {
				accessSync(join(dir, name), constants.X_OK);
				return true;
			} catch {
				return false;
			}
		});
	if (onPath("trash")) return "trash";
	if (onPath("gio")) return "gio trash";
	return undefined;
}

const TRASH_COMMAND = detectTrashCommand();

/** True unless the path is definitely absent; any other lookup failure counts as present. */
function pathExists(absolutePath: string): boolean {
	try {
		lstatSync(absolutePath);
		return true;
	} catch (error) {
		const code = (error as NodeJS.ErrnoException).code;
		return code !== "ENOENT" && code !== "ENOTDIR";
	}
}

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

		const homeDir = process.env.HOME;
		const match = checkTier2(command, {
			safeRoots: SAFE_ROOTS,
			cwdContext: homeDir ? { startCwd: ctx.cwd, homeDir } : undefined,
			pathExists,
		});
		if (!match) return undefined;

		let prompt: string;
		if (match.kind === "rm" && hasPermanentDeleteMarker(match.segment)) {
			prompt = `⚠️ Permanent delete (not trash) requested:\n\n  ${command}\n\nAllow?`;
		} else if (match.kind === "rm" && TRASH_COMMAND) {
			return {
				block: true,
				reason:
					`Blocked: \`rm -rf\` on a path that isn't recognizably disposable (build artifacts, OS temp dirs and anything inside a \`tmp\` directory run without asking). ` +
					`Use \`${TRASH_COMMAND} <path>\` instead; it is recoverable. ` +
					`If this deletion truly must be permanent, explain why and ask the user in your reply; once they agree, rerun it as \`PI_PERMANENT_DELETE=1 rm -rf <path>\` and pi will confirm with them.`,
			};
		} else {
			prompt = `⚠️ Potentially destructive command:\n\n  ${command}\n\nAllow?`;
		}

		if (!ctx.hasUI) {
			return { block: true, reason: "Potentially destructive command blocked (no UI available to confirm)." };
		}

		const choice = await ctx.ui.select(prompt, ["Yes", "No"]);
		if (choice !== "Yes") {
			return { block: true, reason: "Blocked by user" };
		}
		return undefined;
	});
}
