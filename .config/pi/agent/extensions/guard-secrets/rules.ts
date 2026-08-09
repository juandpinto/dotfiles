/**
 * Pure string-matching rules for guard-secrets — no pi imports, no I/O, no
 * side effects. Kept separate from index.ts so this logic can be
 * unit-tested with a plain `node` invocation (see rules.test.mjs) without
 * needing pi's module loader to resolve `@earendil-works/pi-coding-agent`.
 */

export function shellSegments(command: string): string[] {
	return command
		.split(/&&|\|\||;|\n|\|/)
		.map((segment) => segment.trim())
		.filter((segment) => segment.length > 0);
}

export function commitSegments(command: string): string[] {
	return shellSegments(command).filter((segment) => /\bgit\b/.test(segment) && /\bcommit\b/.test(segment));
}

/**
 * `git commit -a`/`--all` stages tracked-file changes as part of running
 * the commit itself, so they won't show up in `git diff --cached` yet when
 * this hook runs (before the tool executes). Detect that flag so the
 * secret scan can diff against HEAD instead of the index in that case.
 * This only ever runs on segments already confirmed to be `git commit`
 * invocations, where a bare `-a`-shaped short flag reliably means --all.
 */
export function commitIncludesAllFlag(segment: string): boolean {
	return /(^|\s)-[a-zA-Z]*a[a-zA-Z]*(\s|$)/.test(segment) || /(^|\s)--all(\s|$)/.test(segment);
}

const SECRET_CONTENT_PATTERNS: Array<{ pattern: RegExp; label: string }> = [
	{ pattern: /-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/, label: "private key" },
	{ pattern: /\bAKIA[0-9A-Z]{16}\b/, label: "AWS access key" },
	{ pattern: /\bghp_[A-Za-z0-9]{36}\b/, label: "GitHub token" },
	{ pattern: /\bxox[baprs]-[A-Za-z0-9-]{10,}\b/, label: "Slack token" },
	{
		pattern: /\b(api[_-]?key|secret|token|password)\s*[:=]\s*["'][^"'\s]{8,}["']/i,
		label: "hardcoded key/secret/token/password assignment",
	},
];

const PROTECTED_FILENAME = /(^|\/)\.env(\..+)?$|(^|\/)id_rsa$|\.pem$|\.key$|(^|\/)credentials\.json$/;

/** Scan a `git diff --name-only`-style file list for protected filenames. */
export function scanFilenames(nameOutput: string): string[] {
	const hits: string[] = [];
	for (const file of nameOutput
		.split("\n")
		.map((f) => f.trim())
		.filter(Boolean)) {
		if (PROTECTED_FILENAME.test(file)) hits.push(`staged file looks like a credential file: ${file}`);
	}
	return hits;
}

/** Scan a `git diff`-style patch body for secret-shaped content. */
export function scanDiffContent(diffOutput: string): string[] {
	const hits: string[] = [];
	for (const { pattern, label } of SECRET_CONTENT_PATTERNS) {
		if (pattern.test(diffOutput)) hits.push(`staged diff looks like it contains a ${label}`);
	}
	return hits;
}
