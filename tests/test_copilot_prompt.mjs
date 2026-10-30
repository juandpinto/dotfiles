// Checks the deployed Copilot CLI setup (see README, "GitHub Copilot CLI").
//
//   node tests/test_copilot_prompt.mjs
//     Runs Copilot offline against a local fake model that records the first
//     request, once per model family (each gets its own prompt template and
//     editing tools). Needs no GitHub account; nothing leaves the machine.
//     COPILOT_BIN overrides the binary (default: copilot on PATH);
//     COPILOT_TEST_MODELS overrides the models (comma-separated).
//
//   node tests/test_copilot_prompt.mjs --otel <file>
//     Checks a real, online session instead, from a local trace written by
//       COPILOT_OTEL_FILE_EXPORTER_PATH=<file> \
//       OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=true copilot
//     and prints every block of its system prompt with its approximate size.
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const repo = realpathSync(fileURLToPath(new URL("..", import.meta.url)));
const deployed = process.env.COPILOT_HOME ?? join(homedir(), ".copilot");
const entries = ["copilot-instructions.md", "skills", "extensions/pi-prompt"];
const otelFile = process.argv[2] === "--otel" ? process.argv[3] : undefined;
// Top-level prompt blocks we expect once the extension has trimmed it. The
// content-exclusion policy comes from the organization and stays.
const expectedBlocks = ["rules", "environment_context", "tools", "custom_instruction", "system_notifications", "session_context", "content_exclusion_policy"];
const allowedTools = ["bash", "view", "edit", "create", "apply_patch", "skill"];
let failures = 0;

function check(ok, label, hint = "") {
	console.log(`${ok ? "ok  " : "FAIL"} ${label}${ok || !hint ? "" : ` (${hint})`}`);
	if (!ok) failures++;
}

const tokens = (text) => Math.round(text.length / 4); // rough, tokenizer-free

/** Top-level <blocks> (opening tag at a line start or right after a closing tag). */
function topLevelBlocks(system) {
	const opener = /(?:^|(?<=<\/[a-z_]+>))[ \t]*<([a-z_]+)>/gm;
	const blocks = [];
	const loose = [];
	let cursor = 0;
	for (let match; (opener.lastIndex = cursor), (match = opener.exec(system)); ) {
		const tag = match[1];
		const start = match.index + match[0].indexOf("<");
		const close = system.indexOf(`</${tag}>`, start);
		const end = close === -1 ? system.length : close + tag.length + 3;
		loose.push(system.slice(cursor, start));
		blocks.push({ tag, text: system.slice(start, end) });
		cursor = end;
	}
	loose.push(system.slice(cursor));
	return { blocks, loose: loose.map((text) => text.trim()).filter(Boolean) };
}

function printOutline(system) {
	const { blocks, loose } = topLevelBlocks(system);
	console.log("\nSystem prompt outline (approximate tokens):");
	console.log(`${String(tokens(loose.join(""))).padStart(7)}  (text outside blocks)`);
	for (const text of loose.filter((chunk) => tokens(chunk) >= 25)) {
		console.log(`${String(tokens(text)).padStart(9)}  starting "${text.split("\n")[0].slice(0, 90)}"`);
	}
	for (const { tag, text } of blocks) {
		const headings = tag === "custom_instruction" ? text.split("\n").filter((line) => /^#{1,2} /.test(line)) : [];
		const skills = tag === "tools" ? [...text.matchAll(/<name>([^<]+)<\/name>/g)].map((match) => match[1]) : [];
		const details = [...headings, ...(skills.length ? [`${skills.length} skills: ${skills.join(", ")}`] : [])];
		const note = expectedBlocks.includes(tag) ? "" : "   <- unexpected";
		console.log(`${String(tokens(text)).padStart(7)}  <${tag}>${note}${details.length ? `: ${details.join(" | ")}` : ""}`);
	}
}

function checkPrompt(system, tools, toolDefinitions) {
	const instructions = readFileSync(join(deployed, "copilot-instructions.md"), "utf8").split("\n")[0];
	const skills = readdirSync(join(deployed, "skills"), { withFileTypes: true }).filter((d) => !d.name.startsWith("."));
	const unexpected = topLevelBlocks(system).blocks.map((b) => b.tag).filter((tag) => !expectedBlocks.includes(tag));

	check(system.includes("operating inside GitHub Copilot CLI"), "pi-style intro replaces Copilot's");
	check(system.includes(instructions), `AGENTS.md is included ("${instructions}")`);
	const missing = skills.filter((skill) => !system.includes(`<name>${skill.name}</name>`)).map((skill) => skill.name);
	check(missing.length === 0, `all ${skills.length} pi skills are listed`, `missing: ${missing.join(", ")}`);
	check(!system.includes("customize-cloud-agent"), "Copilot's built-in skills are left out");
	check(unexpected.length === 0, "only expected prompt blocks remain", `unexpected: ${unexpected.join(", ")}; see the outline`);
	const extra = tools.filter((tool) => !allowedTools.includes(tool));
	check(extra.length === 0, `tools: ${tools.join(", ")}`, `unexpected: ${extra.join(", ")}`);
	check(tools.includes("edit") || tools.includes("apply_patch"), "the model has a file-editing tool");
	const estimate = tokens(system) + tokens(JSON.stringify(toolDefinitions));
	check(estimate < 6000, `about ${estimate} tokens of system prompt and tools (default is ~15k)`);
	return unexpected.length === 0;
}

const toolName = (tool) => tool.name ?? tool.function?.name ?? tool.custom?.name;
const textOf = (content) => (typeof content === "string" ? content : (content ?? []).map((part) => part.text ?? part.content ?? "").join("\n"));

// ── Deployment: links into this repo, and user extensions enabled ───────
for (const entry of entries) {
	const path = join(deployed, entry);
	const target = existsSync(path) ? realpathSync(path) : "";
	check(target.startsWith(repo), `~/.copilot/${entry} resolves into ${repo}`, "re-run Stow");
}
let settings = {};
try {
	settings = JSON.parse(readFileSync(join(deployed, "settings.json"), "utf8"));
} catch {}
check(settings.experimental === true, "experimental is enabled in ~/.copilot/settings.json", "copilot config experimental true");
check(
	(settings.disabledMcpServers ?? []).includes("github-mcp-server"),
	"the built-in GitHub MCP server is disabled",
	"copilot mcp disable github-mcp-server",
);
if (failures > 0) process.exit(1);

// ── A real session, from its OpenTelemetry trace ────────────────────────
if (otelFile) {
	if (!existsSync(otelFile)) {
		console.log(`FAIL no trace at ${otelFile} (use the same path as COPILOT_OTEL_FILE_EXPORTER_PATH)`);
		process.exit(1);
	}
	const records = readFileSync(otelFile, "utf8")
		.split("\n")
		.filter(Boolean)
		.map((line) => JSON.parse(line));
	const spans = records.map((record) => record.attributes ?? {});
	const calls = spans.filter((a) => a["gen_ai.operation.name"] === "chat" && a["gen_ai.system_instructions"]);
	const call = calls[0] ?? spans.find((a) => a["gen_ai.system_instructions"] && a["gen_ai.tool.definitions"]);
	if (!call) {
		console.log(`FAIL no system prompt in ${otelFile} (was OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=true set, and a message sent?)`);
		process.exit(1);
	}
	const system = JSON.parse(call["gen_ai.system_instructions"]).map((part) => textOf(part.content ?? part)).join("\n");
	const toolDefinitions = JSON.parse(call["gen_ai.tool.definitions"] ?? "[]");
	console.log(`\n── your session (${call["gen_ai.request.model"] ?? "unknown model"}; first of ${calls.length} model calls)`);
	checkPrompt(system, toolDefinitions.map(toolName), toolDefinitions);
	printOutline(system);

	// Context Copilot injects into the conversation rather than the system prompt.
	console.log("\nMessages sent with it (approximate tokens):");
	for (const message of JSON.parse(call["gen_ai.input.messages"] ?? "[]")) {
		const text = (message.parts ?? []).map((part) => (typeof part.content === "string" ? part.content : JSON.stringify(part))).join("\n");
		const tags = [...new Set([...text.matchAll(/<([a-z_]+)>/g)].map((match) => `<${match[1]}>`))];
		console.log(`${String(tokens(text)).padStart(7)}  ${message.role}${tags.length ? `: ${tags.join(" ")}` : ""}`);
	}
	// Each MCP server's lifecycle: "discovered" alone means it never started.
	const mcpStates = new Map();
	for (const event of records.flatMap((record) => record.events ?? [])) {
		if (event.name !== "github.copilot.mcp.server.lifecycle") continue;
		const name = event.attributes?.["github.copilot.mcp.server.name"];
		const state = event.attributes?.["github.copilot.mcp.server.state"];
		if (name && state && mcpStates.get(name)?.at(-1) !== state) mcpStates.set(name, [...(mcpStates.get(name) ?? []), state]);
	}
	const mcpSummary = [...mcpStates].map(([name, states]) => `${name} (${states.join(" -> ")})`).join(", ");
	console.log(`\nMCP servers: ${mcpSummary || "none"}`);
	const input = call["gen_ai.usage.input_tokens"];
	if (input) console.log(`Input tokens reported by the API for this call (system prompt, tools and messages): ${input}`);
	process.exit(failures > 0 ? 1 : 0);
}

// ── Offline: one turn per model against a recording fake model ──────────
// Shell aliases don't apply here, so name the binary we actually run.
const bin = process.env.COPILOT_BIN ?? "copilot";
const binPath = bin.includes("/")
	? bin
	: ((process.env.PATH ?? "").split(":").map((dir) => join(dir, bin)).find((path) => existsSync(path)) ?? bin);
const version = spawnSync(binPath, ["--version"], { encoding: "utf8" });
const versionLine = (version.stdout || version.stderr || String(version.error)).trim().split("\n")[0];
check(
	versionLine.includes("GitHub Copilot CLI"),
	`testing ${binPath}: ${versionLine}`,
	"not the Copilot CLI you use; set COPILOT_BIN, e.g. COPILOT_BIN=/opt/homebrew/bin/copilot",
);
if (failures > 0) process.exit(1);

const scratch = mkdtempSync(join(tmpdir(), "copilot-prompt-"));
const home = join(scratch, "home");
mkdirSync(join(home, ".copilot", "extensions"), { recursive: true });
mkdirSync(join(scratch, "work"));
// A GitHub remote makes Copilot add its GitHub-specific prompt blocks too.
spawnSync("git", ["init", "-q"], { cwd: join(scratch, "work") });
spawnSync("git", ["remote", "add", "origin", "https://github.com/octo/example.git"], { cwd: join(scratch, "work") });
for (const entry of entries) symlinkSync(join(deployed, entry), join(home, ".copilot", entry));
writeFileSync(join(home, ".copilot", "settings.json"), JSON.stringify({ experimental: true }));

let captured;
const server = createServer((req, res) => {
	let body = "";
	req.on("data", (chunk) => (body += chunk));
	req.on("end", () => {
		const request = body ? JSON.parse(body) : {};
		if (!captured && request.tools) captured = request;
		const message = { role: "assistant", content: "ok" };
		const base = { id: "x", created: 0, model: "fake" };
		if (!request.stream) {
			res.writeHead(200, { "content-type": "application/json" });
			res.end(JSON.stringify({ ...base, object: "chat.completion", choices: [{ index: 0, message, finish_reason: "stop" }] }));
			return;
		}
		res.writeHead(200, { "content-type": "text/event-stream" });
		for (const choices of [[{ index: 0, delta: message }], [{ index: 0, delta: {}, finish_reason: "stop" }]]) {
			res.write(`data: ${JSON.stringify({ ...base, object: "chat.completion.chunk", choices })}\n\n`);
		}
		res.end("data: [DONE]\n\n");
	});
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));

async function firstRequest(model) {
	captured = undefined;
	const env = {
		...process.env,
		HOME: home,
		COPILOT_HOME: join(home, ".copilot"),
		COPILOT_OFFLINE: "true", // also disables auto-update
		COPILOT_PROVIDER_BASE_URL: `http://127.0.0.1:${server.address().port}/v1`,
		COPILOT_PROVIDER_API_KEY: "fake",
		COPILOT_MODEL: model,
		COPILOT_PROVIDER_MAX_PROMPT_TOKENS: "100000",
		COPILOT_PROVIDER_MAX_OUTPUT_TOKENS: "4000",
	};
	for (const name of ["GH_TOKEN", "GITHUB_TOKEN", "COPILOT_GITHUB_TOKEN"]) delete env[name];
	const child = spawn(binPath, ["-p", "hi"], { cwd: join(scratch, "work"), env, stdio: ["ignore", "ignore", "pipe"] });
	let stderr = "";
	child.stderr.on("data", (chunk) => (stderr += chunk));
	const timer = setTimeout(() => child.kill(), 120_000);
	const status = await new Promise((resolve) => {
		child.on("exit", resolve);
		child.on("error", (error) => resolve(error.message));
	});
	clearTimeout(timer);
	return { request: captured, status, stderr };
}

const models = process.env.COPILOT_TEST_MODELS?.split(",") ?? [
	...new Set([settings.model, "claude-sonnet-5.5", "gpt-5.6-luna"].filter((m) => m && m !== "auto")),
];
for (const model of models) {
	console.log(`\n── ${model} (offline)`);
	const { request, status, stderr } = await firstRequest(model);
	if (!request) {
		check(false, `Copilot sent no model request (exit ${status})`, stderr.trim().split("\n").slice(-3).join(" | "));
		continue;
	}
	const system = request.messages
		.filter((m) => m.role === "system" || m.role === "developer")
		.map((m) => textOf(m.content))
		.join("\n");
	if (!checkPrompt(system, request.tools.map(toolName), request.tools)) printOutline(system);
}

server.close();
rmSync(scratch, { recursive: true, force: true });
process.exit(failures > 0 ? 1 : 0);
