/**
 * Pure string-matching rules for guard-destructive — no pi imports, no
 * I/O, no side effects. Kept separate from index.ts so this logic can be
 * unit-tested with a plain `node` invocation (see rules.test.mjs) without
 * needing pi's module loader to resolve `@earendil-works/pi-coding-agent`.
 */

// ── Shell-segment splitting ──────────────────────────────────────────────
// Multi-command chains (`a && b`, `a; b`, `a | b`) shouldn't cross-
// contaminate flag detection between unrelated commands, e.g. `rm -r foo &&
// ls -f` should not read as "rm" + "force".

export function shellSegments(command: string): string[] {
	return command
		.split(/&&|\|\||;|\n|\|/)
		.map((segment) => segment.trim())
		.filter((segment) => segment.length > 0);
}

// ── rm -rf detection ─────────────────────────────────────────────────────

const RECURSIVE_FLAG = /^-[a-zA-Z]*[rR][a-zA-Z]*$|^--recursive$/;
const FORCE_FLAG = /^-[a-zA-Z]*f[a-zA-Z]*$|^--force$/;

// Whole-drive/home/repo wipes: no everyday legitimate use, always hard-blocked.
// `.`/`./` included deliberately per explicit request: always be specific
// about the directory being deleted instead of relying on cwd being safe.
const CATASTROPHIC_RM_TARGETS = new Set(["/", "/*", "~", "~/", ".", "./", "$HOME", "${HOME}"]);

function stripQuotes(token: string): string {
	return token.replace(/^['"]|['"]$/g, "");
}

// A literal command cannot safely reveal the final scope of these values.
const DYNAMIC_SHELL_VALUE = /\$\(|`|\$\{[^}]+\}|\$[A-Za-z_][A-Za-z0-9_]*|\$[0-9@*#?]/;

function bareCommandName(token: string | undefined): string {
	return (token ?? "").replace(/^.*\//, "");
}

/** Return non-option tokens after the rm command, including tokens after --. */
function rmTargetTokens(segment: string): string[] {
	const tokens = segment.split(/\s+/).map(stripQuotes).filter(Boolean);
	const rmIndex = tokens.findIndex((token) => bareCommandName(token) === "rm");
	if (rmIndex < 0) return [];

	let parsingOptions = true;
	const targets: string[] = [];
	for (const token of tokens.slice(rmIndex + 1)) {
		if (parsingOptions && token === "--") {
			parsingOptions = false;
			continue;
		}
		if (parsingOptions && token.startsWith("-")) continue;
		targets.push(token);
	}
	return targets;
}

export function rmInvocations(command: string): string[] {
	return shellSegments(command).filter((segment) => /\brm\b/.test(segment));
}

export function checkRmSegment(segment: string): { recursiveForce: boolean; catastrophicTarget: boolean } {
	const tokens = segment.split(/\s+/).map(stripQuotes);
	let recursive = false;
	let force = false;
	for (const token of tokens) {
		if (!token.startsWith("-")) continue;
		if (RECURSIVE_FLAG.test(token)) recursive = true;
		if (FORCE_FLAG.test(token)) force = true;
	}
	const catastrophicTarget = tokens.some((t) => CATASTROPHIC_RM_TARGETS.has(t));
	return { recursiveForce: recursive && force, catastrophicTarget };
}

/**
 * True when recursive forced removal gets any target from the shell rather
 * than naming it literally. This includes cleanup traps such as
 * `trap 'rm -rf "$ROOT"' EXIT`: the command text cannot reveal what ROOT
 * will resolve to when the trap eventually runs.
 */
export function hasDynamicRecursiveForceRmTarget(segment: string): boolean {
	if (!checkRmSegment(segment).recursiveForce) return false;
	return rmTargetTokens(segment).some((target) => DYNAMIC_SHELL_VALUE.test(target));
}

// ── Other tier-1 patterns ────────────────────────────────────────────────

const FORK_BOMB = /:\(\)\s*\{[^}]*:\s*\|\s*:[^}]*\}\s*;\s*:/;
const SQL_CATASTROPHIC = /\b(drop\s+(database|schema)|truncate\s+table)\b/i;
const RAW_DISK_WRITE = /\bmkfs(\.\w+)?\b|\bdd\b[^|;&\n]*\bof=\/dev\//i;

export function hasForkBomb(command: string): boolean {
	return FORK_BOMB.test(command);
}

export function hasCatastrophicSql(command: string): boolean {
	return SQL_CATASTROPHIC.test(command);
}

export function hasRawDiskWrite(command: string): boolean {
	return RAW_DISK_WRITE.test(command);
}

const PUSH_FORCE_FLAG = /(^|\s)(--force(-with-lease)?|-f)(\s|$)/;
const PROTECTED_BRANCH_NAME = /\b(main|master)\b/;

export function looksLikeForcePush(command: string): boolean {
	return shellSegments(command).some(
		(segment) => /\bgit\b/.test(segment) && /\bpush\b/.test(segment) && PUSH_FORCE_FLAG.test(segment),
	);
}

export function forcePushNamesProtectedBranch(command: string): boolean {
	return shellSegments(command).some(
		(segment) =>
			/\bgit\b/.test(segment) &&
			/\bpush\b/.test(segment) &&
			PUSH_FORCE_FLAG.test(segment) &&
			PROTECTED_BRANCH_NAME.test(segment),
	);
}

/**
 * True when the push segment names two or more non-flag tokens after
 * `push` (e.g. `push origin some-branch`) — i.e. an explicit remote+branch
 * was given, as opposed to a bare `git push --force` that relies on the
 * current branch's configured upstream. A single non-flag token (just a
 * remote name, e.g. `push --force origin`) still pushes the *current*
 * branch, so it does not count as an explicit branch ref here.
 */
export function pushHasExplicitBranchRef(segment: string): boolean {
	const afterPush = segment.split(/\bpush\b/)[1] ?? "";
	const nonFlagTokens = afterPush
		.split(/\s+/)
		.map(stripQuotes)
		.filter((t) => t.length > 0 && !t.startsWith("-"));
	return nonFlagTokens.length >= 2;
}

/**
 * True if any segment force-pushes without an explicit branch ref named —
 * the only case where "is the current branch main/master?" (a live `git`
 * lookup) matters. That lookup lives in index.ts, the one bit of I/O this
 * tier-1 check needs.
 */
export function hasForcePushWithoutExplicitBranch(command: string): boolean {
	return shellSegments(command).some(
		(segment) =>
			/\bgit\b/.test(segment) &&
			/\bpush\b/.test(segment) &&
			PUSH_FORCE_FLAG.test(segment) &&
			!pushHasExplicitBranchRef(segment),
	);
}

// ── Process-signal detection ─────────────────────────────────────────────

const SIGNAL_COMMAND_NAMES = new Set(["kill", "pkill", "killall"]);
const SHELL_CONTROL_WORDS = new Set(["then", "do", "else", "elif", "{", "}", "(", ")"]);

type SignalCommandName = "kill" | "pkill" | "killall";

interface SignalInvocation {
	name: SignalCommandName;
	args: string[];
}

function isShellAssignment(token: string | undefined): boolean {
	return /^[A-Za-z_][A-Za-z0-9_]*=/.test(token ?? "");
}

function signalInvocation(segment: string): SignalInvocation | undefined {
	const tokens = segment.split(/\s+/).map(stripQuotes).filter(Boolean);
	let index = 0;

	while (SHELL_CONTROL_WORDS.has(tokens[index] ?? "")) index++;
	while (isShellAssignment(tokens[index])) index++;
	if (bareCommandName(tokens[index]) === "env") {
		index++;
		while (tokens[index]?.startsWith("-") || isShellAssignment(tokens[index])) index++;
	}
	if (bareCommandName(tokens[index]) === "command" || bareCommandName(tokens[index]) === "builtin") {
		index++;
	}
	if (bareCommandName(tokens[index]) === "sudo") {
		index++;
		while (tokens[index]?.startsWith("-")) index++;
	}

	const name = bareCommandName(tokens[index]);
	if (!SIGNAL_COMMAND_NAMES.has(name)) return undefined;
	return { name: name as SignalCommandName, args: tokens.slice(index + 1) };
}

function xargsInvokesSignal(segment: string): boolean {
	const tokens = segment.split(/\s+/).map(stripQuotes).filter(Boolean);
	const xargsIndex = tokens.findIndex((token) => bareCommandName(token) === "xargs");
	if (xargsIndex < 0) return false;

	let index = xargsIndex + 1;
	while (index < tokens.length) {
		const token = tokens[index]!;
		if (!token.startsWith("-")) return SIGNAL_COMMAND_NAMES.has(bareCommandName(token));
		if (["-E", "-e", "-I", "-L", "-n", "-P", "-s"].includes(token)) {
			index += 2;
		} else {
			index++;
		}
	}
	return false;
}

function killHasBroadTarget(args: string[]): boolean {
	let index = 0;
	let signalSpecified = false;
	while (index < args.length) {
		const arg = args[index]!;
		if (arg === "--") {
			index++;
			break;
		}
		if (arg === "-s" || arg === "--signal") {
			signalSpecified = true;
			index += 2;
			continue;
		}
		if (arg.startsWith("--signal=")) {
			signalSpecified = true;
			index++;
			continue;
		}
		if (/^-[A-Za-z]+$/.test(arg)) {
			signalSpecified = true;
			index++;
			continue;
		}
		if (/^-\d+$/.test(arg) && !signalSpecified) {
			signalSpecified = true;
			index++;
			continue;
		}
		break;
	}
	return args.slice(index).some((arg) => arg === "0" || /^-\d+$/.test(arg));
}

/**
 * True for process termination whose target set is dynamic or inherently
 * broad. These are Tier 1 rather than confirmation-worthy because a human
 * cannot safely infer the expanded PID set from the literal command.
 */
export function hasUnsafeSignalInvocation(command: string): boolean {
	for (const segment of shellSegments(command)) {
		if (xargsInvokesSignal(segment)) return true;
		const invocation = signalInvocation(segment);
		if (!invocation) continue;
		if (invocation.args.some((arg) => DYNAMIC_SHELL_VALUE.test(arg))) return true;
		if (invocation.name === "kill" && killHasBroadTarget(invocation.args)) return true;
	}
	return false;
}

// ── Tier 1: pattern-only checks (no I/O) ─────────────────────────────────

export interface Tier1Match {
	reason: string;
}

/**
 * Everything tier-1 except the "force-push with no branch named" case,
 * which needs a live `git branch --show-current` lookup and lives in
 * index.ts instead (the only I/O in the whole tier-1 check).
 */
export function checkTier1Patterns(command: string): Tier1Match | undefined {
	for (const segment of rmInvocations(command)) {
		const { recursiveForce, catastrophicTarget } = checkRmSegment(segment);
		if (recursiveForce && catastrophicTarget) {
			return {
				reason:
					"Blocked: rm -rf on /, ~, $HOME, or . would wipe the whole drive/home/repo. Re-run naming a specific subdirectory instead.",
			};
		}
		if (hasDynamicRecursiveForceRmTarget(segment)) {
			return {
				reason:
					"Blocked: rm -rf must name a literal target; variables and command substitutions hide its scope. Use a specific literal path or leave temporary files for the OS to clean up.",
			};
		}
	}
	if (hasForkBomb(command)) {
		return { reason: "Blocked: fork bomb pattern detected." };
	}
	if (hasCatastrophicSql(command)) {
		return { reason: "Blocked: destructive SQL (DROP DATABASE/SCHEMA or TRUNCATE TABLE) detected." };
	}
	if (hasRawDiskWrite(command)) {
		return { reason: "Blocked: command formats or writes directly to a raw disk device." };
	}
	if (hasUnsafeSignalInvocation(command)) {
		return {
			reason:
				"Blocked: process termination must name inspected literal PID(s), never lsof/pgrep/ps output, xargs, shell expansion, PID 0, or a process group.",
		};
	}
	if (forcePushNamesProtectedBranch(command)) {
		return { reason: "Blocked: force-push to main/master is not allowed." };
	}
	return undefined;
}

// ── Tier 2: confirm-worthy, not catastrophic ─────────────────────────────
//
// Auto-allow (skip the confirm entirely) when *every* rm target is
// recognizably disposable: a well-known build/cache/dependency-artifact
// directory name, anything that resolves to a path actually rooted
// under a real OS temp directory, or anything inside a directory named
// exactly `tmp`. Anything else in the same rm invocation
// (an unrecognized target, or a bare wildcard like `*` whose safety
// depends on cwd) keeps the review for the whole command — err toward
// asking when uncertain. A separate shortcut below lets through an rm whose
// targets provably don't exist yet, since that rm is a no-op.
//
// Deliberately NOT included: generic "test"/"tmp"/"scratch" substring
// matching (too easy to collide with a real, meaningful directory such as
// `tmp-data` or `tmpl`), and bare `*`
// (its safety depends on cwd, which resolving via a preceding `cd` doesn't
// change — a wildcard could still expand to something unexpected).

export const DEFAULT_SAFE_ROOTS = ["/tmp/", "/var/tmp/", "/private/tmp/", "/private/var/tmp/"];

const SAFE_DISPOSABLE_BASENAMES = new Set([
	"node_modules",
	"dist",
	"build",
	".next",
	".nuxt",
	".turbo",
	".parcel-cache",
	".cache",
	"coverage",
	".nyc_output",
	"__pycache__",
	".pytest_cache",
	".mypy_cache",
	".ruff_cache",
	".tox",
	"htmlcov",
	".venv",
	"venv",
	".eggs",
	".gradle",
]);

function basenameOf(token: string): string {
	const trimmed = token.replace(/\/+$/, "");
	const idx = trimmed.lastIndexOf("/");
	return idx === -1 ? trimmed : trimmed.slice(idx + 1);
}

/** True if `target` is strictly inside (not equal to) one of `safeRoots`. */
export function isUnderSafeRoot(target: string, safeRoots: string[] = DEFAULT_SAFE_ROOTS): boolean {
	const withSlash = target.endsWith("/") ? target : `${target}/`;
	return safeRoots.some((root) => withSlash.startsWith(root) && withSlash !== root);
}

/**
 * True if `path` is strictly inside a directory named exactly `tmp`, wherever
 * it sits (`.sandbox/tmp/run-1`, `~/.npm/_cacache/tmp/x`, a Maildir's `tmp/`).
 * A directory named `tmp` conventionally holds only transient files. The
 * `tmp` directory itself still asks, as do look-alikes such as `tmp-data`.
 * Only pass a normalized path, or `..` could climb back out.
 */
export function isInsideTmpDir(path: string): boolean {
	return path.split("/").filter(Boolean).slice(0, -1).includes("tmp");
}

/**
 * Resolve a single path-shaped token against a known-absolute base
 * directory, expanding `~`/`$HOME`/`${HOME}`. Returns null if the token
 * contains anything else this can't confidently resolve (another `$VAR`,
 * command substitution `` $(...) ``/backticks) — callers should treat null
 * as "don't know, don't optimize."
 */
export function resolvePathToken(token: string, baseDir: string, homeDir: string): string | null {
	let expanded = token;
	if (expanded === "~" || expanded === "$HOME" || expanded === "${HOME}") {
		expanded = homeDir;
	} else if (expanded.startsWith("~/")) {
		expanded = `${homeDir}/${expanded.slice(2)}`;
	} else if (expanded.startsWith("$HOME/")) {
		expanded = `${homeDir}/${expanded.slice("$HOME/".length)}`;
	} else if (expanded.startsWith("${HOME}/")) {
		expanded = `${homeDir}/${expanded.slice("${HOME}/".length)}`;
	}
	if (expanded.includes("$") || expanded.includes("`")) return null; // unresolved variable/substitution

	const absolute = expanded.startsWith("/") ? expanded : `${baseDir}/${expanded}`;
	const parts = absolute.split("/");
	const resolved: string[] = [];
	for (const part of parts) {
		if (part === "" || part === ".") continue;
		if (part === "..") {
			resolved.pop();
			continue;
		}
		resolved.push(part);
	}
	return `/${resolved.join("/")}`;
}

/**
 * Parse a `cd <path>` segment into its single target path.
 *
 * Returns:
 * - `undefined` if this segment isn't a `cd` invocation at all (cwd is
 *   simply unaffected — tracking continues unchanged).
 * - `null` if it *is* a `cd` but not confidently resolvable: `cd -`
 *   (depends on $OLDPWD), multiple arguments, or no argument at all (bare
 *   `cd`, which goes to $HOME — deliberately not special-cased to keep
 *   this parser simple). Callers must treat this as "tracking is no longer
 *   reliable from here on," not "cwd unchanged."
 * - the target string otherwise.
 */
export function parseCdTarget(segment: string): string | null | undefined {
	const tokens = segment.split(/\s+/).map(stripQuotes);
	if (tokens[0] !== "cd") return undefined;
	const args = tokens.slice(1);
	if (args.length !== 1) return null;
	if (args[0] === "-") return null;
	return args[0];
}

export interface CwdContext {
	/** The bash tool's actual starting directory for this command (pi's `ctx.cwd`). */
	startCwd: string;
	/** The user's home directory, for resolving `~`/`$HOME` in `cd` targets. */
	homeDir: string;
}

/**
 * Walk a command's segments in order, tracking the effective cwd through
 * any `cd` segments so a later `rm` segment can be checked against where
 * it will *actually* run rather than just its literal (possibly relative)
 * argument text. `cwd` is null for a segment once tracking becomes
 * unreliable (an unparseable `cd`) — every segment from that point on is
 * treated as "cwd unknown," which simply disables this optimization
 * without disabling any of the other, non-cwd-dependent checks.
 */
export function segmentsWithCwd(
	command: string,
	ctx?: CwdContext,
): Array<{ segment: string; cwd: string | null }> {
	const segments = shellSegments(command);
	let currentDir: string | null = ctx?.startCwd ?? null;
	const result: Array<{ segment: string; cwd: string | null }> = [];
	for (const segment of segments) {
		result.push({ segment, cwd: currentDir });
		const cdTarget = parseCdTarget(segment);
		if (cdTarget === undefined) continue; // not a cd at all — cwd unaffected
		if (cdTarget === null || currentDir === null || !ctx) {
			currentDir = null; // cd present but not confidently resolvable — stop tracking
			continue;
		}
		currentDir = resolvePathToken(cdTarget, currentDir, ctx.homeDir);
	}
	return result;
}

function isRmTargetSafe(token: string, cwd: string | null, homeDir: string | undefined, safeRoots: string[]): boolean {
	if (SAFE_DISPOSABLE_BASENAMES.has(basenameOf(token))) return true;
	// Check only normalized paths, so `..` cannot climb back out of a safe
	// place (`/tmp/../home/me`, `.sandbox/tmp/../../src`). With an unknown cwd,
	// a relative path is normalized against `/` as a stand-in: that can't say
	// where the path really is, but the components left over still show
	// whether it stays inside a `tmp` directory.
	const resolved = resolvePathToken(token, cwd ?? "/", homeDir ?? "/");
	if (resolved === null) return false;
	if (isInsideTmpDir(resolved)) return true;
	const locationKnown = token.startsWith("/") || (cwd !== null && homeDir !== undefined);
	return locationKnown && isUnderSafeRoot(resolved, safeRoots);
}

/**
 * True if every actual target (non-flag token, excluding the `rm` word
 * itself) in an rm segment is recognizably disposable — either by name,
 * by literal absolute path, or (given `cwd`/`homeDir`) by resolving a
 * relative target against the directory a preceding `cd` put us in. A
 * segment with no targets at all (shouldn't happen in practice) is
 * treated as NOT safe.
 */
export function isRmSegmentAutoAllowed(
	segment: string,
	cwd: string | null = null,
	homeDir: string | undefined = undefined,
	safeRoots: string[] = DEFAULT_SAFE_ROOTS,
): boolean {
	const tokens = segment.split(/\s+/).map(stripQuotes);
	const targets = tokens.filter((t) => t !== "rm" && !t.startsWith("-"));
	if (targets.length === 0) return false;
	return targets.every((t) => isRmTargetSafe(t, cwd, homeDir, safeRoots));
}

const CHMOD_CHOWN_777 = /\b(chmod|chown)\b[^&|;\n]*\b(777|a\+rwx)\b/i;

// ── Absent targets: `rm -rf` on a path that doesn't exist is a no-op ─────
//
// Only trusted when the command text leaves no room for the real target to
// differ from the one we checked: the segment is a plain `rm` (or `sudo
// rm`) invocation, not something that embeds rm (`find -exec rm`, `xargs
// rm`, `sh -c "rm ..."`); each target is a simple literal path with no
// quotes, backslashes, globs, `~user`, redirections or `&`; and every
// earlier segment is a `cd`, since anything else (`mv precious X && rm -rf
// X`) could create the target between our check and the rm. The caller
// does the actual filesystem lookup, see Tier2Options.pathExists.

const PLAIN_PATH = /^(~\/)?[A-Za-z0-9._/@:,=-]+$/;

/**
 * Absolute paths of every target in a plain `rm` segment, or null when
 * the absent-target shortcut must not apply (see the comment above).
 * Relative targets need a known cwd; `~/` targets need homeDir.
 */
export function plainRmTargetPaths(segment: string, cwd: string | null, homeDir: string | undefined): string[] | null {
	if (/["'\\]/.test(segment)) return null;
	const tokens = segment.split(/\s+/).filter(Boolean);
	let index = 0;
	if (bareCommandName(tokens[index]) === "sudo") index++;
	if (bareCommandName(tokens[index]) !== "rm") return null;

	const targets = rmTargetTokens(segment);
	if (targets.length === 0) return null;
	const paths: string[] = [];
	for (const target of targets) {
		if (!PLAIN_PATH.test(target)) return null;
		let base: string;
		if (target.startsWith("/")) base = "/";
		else if (target.startsWith("~/")) {
			if (homeDir === undefined) return null;
			base = homeDir;
		} else {
			if (cwd === null || homeDir === undefined) return null;
			base = cwd;
		}
		const resolved = resolvePathToken(target, base, homeDir ?? "/");
		if (resolved === null) return null;
		paths.push(resolved);
	}
	return paths;
}

// ── Permanent-delete marker ──────────────────────────────────────────────
//
// `PI_PERMANENT_DELETE=1 rm -rf <path>` routes an otherwise-blocked rm to
// the interactive confirm instead. The agent is told to use it only after
// the user has agreed in conversation; adding it without asking just earns
// the same prompt the guard used to show for every rm -rf.

export function hasPermanentDeleteMarker(segment: string): boolean {
	return /(^|\s)PI_PERMANENT_DELETE=1(\s|$)/.test(segment);
}

export interface Tier2Options {
	safeRoots?: string[];
	cwdContext?: CwdContext;
	/**
	 * True if anything (file, directory, symlink even if dangling) exists at
	 * this absolute path. When provided, enables the absent-target shortcut.
	 */
	pathExists?: (absolutePath: string) => boolean;
}

export type Tier2Match = { kind: "rm"; segment: string } | { kind: "chmod" };

export function checkTier2(command: string, options: Tier2Options = {}): Tier2Match | undefined {
	const safeRoots = options.safeRoots ?? DEFAULT_SAFE_ROOTS;
	const homeDir = options.cwdContext?.homeDir;
	let precededOnlyByCd = true;
	for (const { segment, cwd } of segmentsWithCwd(command, options.cwdContext)) {
		const isCd = parseCdTarget(segment) !== undefined;
		const needsReview =
			/\brm\b/.test(segment) &&
			checkRmSegment(segment).recursiveForce &&
			// Dynamic recursive-force targets are Tier 1 and never reach confirmation.
			!hasDynamicRecursiveForceRmTarget(segment) &&
			!isRmSegmentAutoAllowed(segment, cwd, homeDir, safeRoots) &&
			!(precededOnlyByCd && allTargetsAbsent(segment, cwd, homeDir, options.pathExists));
		if (needsReview) return { kind: "rm", segment };
		precededOnlyByCd &&= isCd;
	}
	if (CHMOD_CHOWN_777.test(command)) return { kind: "chmod" };
	return undefined;
}

function allTargetsAbsent(
	segment: string,
	cwd: string | null,
	homeDir: string | undefined,
	pathExists: Tier2Options["pathExists"],
): boolean {
	if (!pathExists) return false;
	const paths = plainRmTargetPaths(segment, cwd, homeDir);
	if (paths === null) return false;
	return paths.every((path) => !pathExists(path));
}

export function isTier2Destructive(command: string, options: Tier2Options = {}): boolean {
	return checkTier2(command, options) !== undefined;
}
