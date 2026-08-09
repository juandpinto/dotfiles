// Plain-node test suite for guard-secrets's pure rules. Run with:
//   node --experimental-strip-types rules.test.mjs
// No pi module resolution needed — rules.ts has no external imports.
// Never runs a real `git commit` or touches the actual repo index; all
// git-shaped output here is hand-written sample text.

import { commitIncludesAllFlag, commitSegments, scanDiffContent, scanFilenames } from "./rules.ts";

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

// ── commitSegments: only matches actual git-commit invocations ─────────
assert("plain commit", commitSegments('git commit -m "msg"').length, 1);
assert("chained add+commit+push", commitSegments('git add -A && git commit -m "x" && git push').length, 1);
assert("not a commit (status)", commitSegments("git status").length, 0);
assert("not git at all", commitSegments("npm commit-lint"), []); // "commit" without "git" shouldn't match

// ── commitIncludesAllFlag ───────────────────────────────────────────────
assert("commit -am flag", commitIncludesAllFlag('git commit -am "msg"'), true);
assert("commit --all flag", commitIncludesAllFlag('git commit --all -m "msg"'), true);
assert("commit plain -m (no -a)", commitIncludesAllFlag('git commit -m "msg"'), false);

// ── scanFilenames ─────────────────────────────────────────────────────────
assert("finds .env filename", scanFilenames(".env\nREADME.md\n").some((h) => h.includes(".env")), true);
assert("finds id_rsa filename", scanFilenames("id_rsa\nsrc/index.ts\n").some((h) => h.includes("id_rsa")), true);
assert("clean filenames -> no hits", scanFilenames("README.md\nsrc/index.ts\n").length, 0);

// ── scanDiffContent ───────────────────────────────────────────────────────
assert(
	"finds AWS key pattern",
	scanDiffContent('+aws_key = "AKIAABCDEFGHIJKLMNOP"\n').some((h) => h.includes("AWS access key")),
	true,
);
assert(
	"finds password assignment pattern",
	scanDiffContent('+password: "supersecretvalue"\n').some((h) => h.includes("password")),
	true,
);
assert(
	"finds private key content",
	scanDiffContent("-----BEGIN RSA PRIVATE KEY-----\nMIIExyz\n").some((h) => h.includes("private key")),
	true,
);
assert("clean diff -> no hits", scanDiffContent("+const key = process.env.FOO;\n").length, 0);
assert("short value doesn't false-positive", scanDiffContent('+token = "abc"\n').length, 0);

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILURE(S)`);
process.exit(failures === 0 ? 0 : 1);
