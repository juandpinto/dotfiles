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
	hasForcePushWithoutExplicitBranch,
	hasForkBomb,
	hasRawDiskWrite,
	isTier2Destructive,
	looksLikeForcePush,
	pushHasExplicitBranchRef,
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

// ── Tier 2: confirm-worthy but not catastrophic ─────────────────────────
const tier2Cases = [
	["rm -rf node_modules", true],
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
