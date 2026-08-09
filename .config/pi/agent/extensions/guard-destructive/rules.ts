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
	if (forcePushNamesProtectedBranch(command)) {
		return { reason: "Blocked: force-push to main/master is not allowed." };
	}
	return undefined;
}

// ── Tier 2: confirm-worthy, not catastrophic ─────────────────────────────

const SUDO = /\bsudo\b/i;
const CHMOD_CHOWN_777 = /\b(chmod|chown)\b[^&|;\n]*\b(777|a\+rwx)\b/i;

export function isTier2Destructive(command: string): boolean {
	if (rmInvocations(command).some((segment) => checkRmSegment(segment).recursiveForce)) return true;
	if (SUDO.test(command)) return true;
	if (CHMOD_CHOWN_777.test(command)) return true;
	return false;
}
