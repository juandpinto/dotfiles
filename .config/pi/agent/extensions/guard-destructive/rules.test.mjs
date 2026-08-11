// Plain-node test suite for guard-destructive's pure rules. Run with:
//   node --experimental-strip-types rules.test.mjs
// (or plain `node rules.test.mjs` on Node versions where .ts stripping is
// unflagged by default). No pi module resolution needed — rules.ts has no
// external imports.
//
// Deliberately never executes a real destructive command: every case here
// only feeds a *string* into the pure detector functions. `checkTier1`'s
// one live-git branch check lives in index.ts, not here — see
// guard-destructive/index.ts for why that's kept as the sole bit of I/O.

import {
	checkRmSegment,
	checkTier1Patterns,
	forcePushNamesProtectedBranch,
	hasCatastrophicSql,
	hasDynamicRecursiveForceRmTarget,
	hasForcePushWithoutExplicitBranch,
	hasForkBomb,
	hasRawDiskWrite,
	hasUnsafeSignalInvocation,
	isRmSegmentAutoAllowed,
	isTier2Destructive,
	isUnderSafeRoot,
	looksLikeForcePush,
	parseCdTarget,
	pushHasExplicitBranchRef,
	resolvePathToken,
	segmentsWithCwd,
} from "./rules.ts";

let failures = 0;
function assert(name, actual, expected) {
	const ok = JSON.stringify(actual) === JSON.stringify(expected);
	if (!ok) {
		failures++;
		console.error(`FAIL ${name}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
	} else {
		console.log(`ok   ${name}`);
	}
}

function rmSegmentOf(command) {
	return command
		.split(/&&|\|\||;|\n|\|/)
		.map((s) => s.trim())
		.find((s) => /\brm\b/.test(s));
}

// ── Tier 1: catastrophic rm targets — should ALWAYS be caught ───────────
const catastrophicRm = [
	"rm -rf /",
	"rm -rf /*",
	"rm -rf ~",
	"rm -rf ~/",
	"rm -rf .",
	"rm -rf ./",
	'rm -rf "."',
	"rm -rf $HOME",
	"rm -rf ${HOME}",
	"rm -r -f .",
	"rm --recursive --force .",
	"cd /tmp && rm -rf .",
	"rm -rf . # cleanup",
];
for (const cmd of catastrophicRm) {
	assert(`catastrophic rm: "${cmd}"`, checkRmSegment(rmSegmentOf(cmd)), {
		recursiveForce: true,
		catastrophicTarget: true,
	});
}

// ── Should NOT falsely catch ordinary, everyday rm usage ────────────────
const safeRm = ["rm -rf node_modules", "rm -rf ./build", "rm -rf dist/", "rm -f file.txt", "rm somefile", "rm -rf /tmp/scratch-dir-xyz"];
for (const cmd of safeRm) {
	assert(`safe rm not catastrophic: "${cmd}"`, checkRmSegment(rmSegmentOf(cmd)).catastrophicTarget, false);
}

// ── checkTier1Patterns end-to-end (excludes the live-git branch case) ──
const tier1Cases = [
	["rm -rf /", true],
	["rm -rf .", true],
	["rm -rf ~", true],
	[":(){ :|:& };:", true],
	["DROP DATABASE prod;", true],
	["drop schema public cascade;", true],
	["TRUNCATE TABLE users;", true],
	["mkfs.ext4 /dev/sda1", true],
	["dd if=/dev/zero of=/dev/sda", true],
	["git push --force origin main", true],
	["git push -f origin master", true],
	["rm -rf node_modules", false],
	["echo hello", false],
	["ls -la", false],
	["git status", false],
	["git push --force origin some-feature-branch", false], // explicit non-protected branch
];
for (const [cmd, expectBlocked] of tier1Cases) {
	assert(`checkTier1Patterns "${cmd}"`, Boolean(checkTier1Patterns(cmd)), expectBlocked);
}

// ── Tier 1: dynamic recursive-force rm targets — hard-blocked ──────────
// A cleanup trap can run long after its setup, so its variable target is no
// safer than a direct `rm -rf "$ROOT"`. These must not fall through to the
// Tier 2 confirmation path.
const dynamicRmTier1Cases = [
	['rm -rf "$ROOT"', true],
	['rm -rf -- "$ROOT"', true],
	['/bin/rm -rf "$ROOT"', true],
	['rm -rf "${ROOT}/child"', true],
	['rm -rf "$(mktemp -d)"', true],
	['rm -rf "$TMPDIR/aerc-config-parse"', true],
	["ROOT=$(mktemp -d /tmp/aerc-config-parse.XXXXXX); trap 'rm -rf \"$ROOT\"' EXIT", true],
	["rm -rf /tmp/aerc-config-parse-fixed", false],
	["rm -rf node_modules", false],
	['rm -f "$file"', false],
];
for (const [cmd, expected] of dynamicRmTier1Cases) {
	const segment = rmSegmentOf(cmd);
	assert(`hasDynamicRecursiveForceRmTarget "${cmd}"`, hasDynamicRecursiveForceRmTarget(segment), expected);
	assert(`checkTier1Patterns dynamic rm "${cmd}"`, Boolean(checkTier1Patterns(cmd)), expected);
	if (expected) {
		assert(`dynamic rm bypasses Tier 2 "${cmd}"`, isTier2Destructive(cmd), false);
	}
}

// ── Tier 1: unsafe process-signal targets — hard-blocked ───────────────
const unsafeSignalCases = [
	["kill $pids", true],
	['kill "${pids[@]}"', true],
	['kill "$(lsof -t -U "$SOCK")"', true],
	["pids=$(pgrep aerc); kill $pids", true],
	['if [ -n "$pids" ]; then kill $pids; fi', true],
	['lsof -t -U "$SOCK" | xargs -n1 kill', true],
	["pgrep aerc | xargs -n 1 /bin/kill", true],
	["kill 0", true],
	["kill -- -123", true],
	["kill -TERM -123", true],
	["kill 12345", false],
	["kill -TERM 12345", false],
	["kill -1 12345", false], // -1 is a signal selector here, not a target
	["pkill aerc", false], // no new Tier 2 prompt or Tier 1 block requested
	["xargs echo kill", false],
];
for (const [cmd, expected] of unsafeSignalCases) {
	assert(`hasUnsafeSignalInvocation "${cmd}"`, hasUnsafeSignalInvocation(cmd), expected);
	assert(`checkTier1Patterns signal integration "${cmd}"`, Boolean(checkTier1Patterns(cmd)), expected);
}

// ── Tier 2: confirm-worthy but not catastrophic ─────────────────────────
const tier2Cases = [
	["rm -rf some-unrecognized-dir", true], // recursive+force on a target that isn't auto-allowed
	["sudo apt-get install foo", true],
	["chmod 777 file.txt", true],
	["chmod -R 777 .", true],
	["echo hello", false],
	["ls -la", false],
	["rm -f file.txt", false], // force but not recursive
	["rm -r somedir", false], // recursive but not force
];
for (const [cmd, expected] of tier2Cases) {
	assert(`isTier2Destructive "${cmd}"`, isTier2Destructive(cmd), expected);
}

// ── Auto-allow: known-disposable rm targets skip the confirm entirely ──
const autoAllowCases = [
	["rm -rf node_modules", true],
	["rm -rf ./node_modules", true],
	["rm -rf src/node_modules", true],
	["rm -rf node_modules/", true],
	["rm -rf dist build coverage", true], // multiple disposable targets, one invocation
	["rm -rf __pycache__", true],
	["rm -rf .pytest_cache .ruff_cache", true],
	["rm -rf /tmp/pi-guard-demo", true],
	["rm -rf /tmp/pi-guard-demo/*", true],
	["rm -rf /var/tmp/scratch-xyz", true],
	// Not auto-allowed: unrecognized target, mixed target, bare wildcard, bare temp root
	["rm -rf some-random-project-folder", false],
	["rm -rf node_modules ~/Documents/notes", false],
	["rm -rf *", false],
	["rm -rf /tmp", false], // the bare root itself, not a subpath
	["rm -rf /tmp/", false],
	["rm -rf target", false], // deliberately not on the safe list (see rules.ts comment)
];
for (const [cmd, expectAutoAllowed] of autoAllowCases) {
	const isDestructive = isTier2Destructive(cmd);
	// auto-allowed means Tier 2 does NOT flag it as needing confirmation
	assert(`auto-allow "${cmd}"`, !isDestructive, expectAutoAllowed);
}

// Mixed-target command still requires confirmation for the *whole* command,
// even though one of its targets is individually safe.
assert(
	"isRmSegmentAutoAllowed rejects mixed safe/unsafe targets",
	isRmSegmentAutoAllowed("rm -rf node_modules ~/Documents/notes"),
	false,
);

// isUnderSafeRoot: bare root doesn't count, subpaths do
assert("isUnderSafeRoot subpath", isUnderSafeRoot("/tmp/foo"), true);
assert("isUnderSafeRoot bare root (no subpath)", isUnderSafeRoot("/tmp"), false);
assert("isUnderSafeRoot bare root with trailing slash", isUnderSafeRoot("/tmp/"), false);
assert("isUnderSafeRoot unrelated path", isUnderSafeRoot("/Users/juanpinto/Documents"), false);

// ── cd-aware resolution: `cd /tmp && rm -rf dir` and friends ────────────
const cwdCtx = { startCwd: "/Users/juanpinto/myproject", homeDir: "/Users/juanpinto" };

assert("parseCdTarget plain", parseCdTarget("cd /tmp"), "/tmp");
assert("parseCdTarget relative", parseCdTarget("cd subdir"), "subdir");
assert("parseCdTarget rejects cd -", parseCdTarget("cd -"), null);
assert("parseCdTarget rejects multiple args", parseCdTarget("cd foo bar"), null);
assert("parseCdTarget rejects non-cd", parseCdTarget("echo cd"), undefined);

assert("resolvePathToken absolute", resolvePathToken("/tmp/foo", "/Users/juanpinto/proj", "/Users/juanpinto"), "/tmp/foo");
assert(
	"resolvePathToken relative against cwd",
	resolvePathToken("subdir", "/Users/juanpinto/proj", "/Users/juanpinto"),
	"/Users/juanpinto/proj/subdir",
);
assert("resolvePathToken tilde", resolvePathToken("~/Documents", "/tmp", "/Users/juanpinto"), "/Users/juanpinto/Documents");
assert("resolvePathToken $HOME", resolvePathToken("$HOME/Documents", "/tmp", "/Users/juanpinto"), "/Users/juanpinto/Documents");
assert("resolvePathToken dot-dot", resolvePathToken("../sibling", "/Users/juanpinto/proj/sub", "/Users/juanpinto"), "/Users/juanpinto/proj/sibling");
assert("resolvePathToken bails on unresolved var", resolvePathToken("$RANDOM_VAR/x", "/tmp", "/Users/juanpinto"), null);

{
	const tracked = segmentsWithCwd("cd /tmp && rm -rf dir", cwdCtx);
	assert("segmentsWithCwd tracks cd", tracked, [
		{ segment: "cd /tmp", cwd: "/Users/juanpinto/myproject" },
		{ segment: "rm -rf dir", cwd: "/tmp" },
	]);
}

{
	// unparseable cd disables tracking for the rest of the chain
	const tracked = segmentsWithCwd("cd - && rm -rf dir", cwdCtx);
	assert("segmentsWithCwd bails on cd -", tracked[1].cwd, null);
}

// The reported case: cd into a safe root, then rm -rf a plain relative dir.
const cdCases = [
	["cd /tmp && rm -rf dir", true],
	["cd /tmp/scratch && rm -rf some-output", true],
	["cd /tmp && rm -rf a b c", true], // multiple relative targets, all resolve under /tmp
	["cd /var/tmp && rm -rf leftovers", true],
	["cd subdir && rm -rf dir", false], // relative cd target under the *project* dir — not a safe root
	["cd /Users/juanpinto/Documents && rm -rf notes", false], // cd resolves fine, just not to a safe root
	["cd - && rm -rf dir", false], // cd - can't be resolved — falls back to today's (unsafe) behavior
	["cd /tmp && cd .. && rm -rf dir", false], // walks back out of /tmp via ..
	["cd /tmp/foo && cd bar && rm -rf dir", true], // chained cd's, still resolves under /tmp
];
for (const [cmd, expectAutoAllowed] of cdCases) {
	const isDestructive = isTier2Destructive(cmd, { cwdContext: cwdCtx });
	assert(`cd-aware auto-allow "${cmd}"`, !isDestructive, expectAutoAllowed);
}

// Without a cwdContext at all, behavior is unchanged from before this feature
// (relative rm targets are never resolved, so this still requires confirm).
assert(
	"no cwdContext -> relative rm after cd still confirms (unchanged prior behavior)",
	isTier2Destructive("cd /tmp && rm -rf dir"),
	true,
);

// ── Force-push helpers ────────────────────────────────────────────────────
assert("force push explicit main", forcePushNamesProtectedBranch("git push --force origin main"), true);
assert("force push explicit master", forcePushNamesProtectedBranch("git push -f origin master"), true);
assert("force push feature branch", forcePushNamesProtectedBranch("git push --force origin my-feature"), false);
assert("plain push main (no force)", looksLikeForcePush("git push origin main"), false);
assert("looksLikeForcePush with -f", looksLikeForcePush("git push -f origin main"), true);
assert("bare force push has no explicit branch", hasForcePushWithoutExplicitBranch("git push --force"), true);
assert(
	"force push with remote+branch has explicit branch",
	hasForcePushWithoutExplicitBranch("git push --force origin some-branch"),
	false,
);
assert(
	"force push with just a remote still ambiguous (no explicit branch)",
	pushHasExplicitBranchRef("git push --force origin"),
	false,
);

// ── Other patterns ───────────────────────────────────────────────────────
assert("fork bomb", hasForkBomb(":(){ :|:& };:"), true);
assert("not fork bomb", hasForkBomb("echo hi"), false);
assert("sql drop database", hasCatastrophicSql("psql -c 'DROP DATABASE mydb'"), true);
assert("sql truncate", hasCatastrophicSql("TRUNCATE TABLE logs"), true);
assert("sql select (safe)", hasCatastrophicSql("SELECT * FROM users"), false);
assert("raw disk write dd", hasRawDiskWrite("dd if=/dev/zero of=/dev/disk2"), true);
assert("raw disk write mkfs", hasRawDiskWrite("mkfs.ext4 /dev/sdb1"), true);
assert("dd to regular file (safe)", hasRawDiskWrite("dd if=/dev/zero of=./scratch.img bs=1M count=10"), false);

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILURE(S)`);
process.exit(failures === 0 ? 0 : 1);
