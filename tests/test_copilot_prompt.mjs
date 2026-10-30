// Checks the deployed Copilot CLI setup (see README, "GitHub Copilot CLI")
// without a GitHub account or a model: Copilot runs offline against a local
// fake model that records the first request, and we check exactly what it
// would have sent. Nothing leaves the machine. Copilot picks a different
// prompt template and editing tools per model family, so each family runs.
//   node tests/test_copilot_prompt.mjs
// COPILOT_BIN overrides the binary (default: copilot on PATH);
// COPILOT_TEST_MODELS overrides the models (comma-separated).
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const repo = realpathSync(fileURLToPath(new URL("..", import.meta.url)));
const deployed = process.env.COPILOT_HOME ?? join(homedir(), ".copilot");
const entries = ["copilot-instructions.md", "skills", "extensions/pi-prompt"];
// Top-level prompt blocks we expect once the extension has trimmed it.
const expectedBlocks = ["rules", "environment_context", "tools", "custom_instruction", "system_notifications", "session_context"];
let failures = 0;

function check(ok, label, hint = "") {
	console.log(`${ok ? "ok  " : "FAIL"} ${label}${ok || !hint ? "" : ` (${hint})`}`);
	if (!ok) failures++;
}

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
if (failures > 0) process.exit(1);

// ── Requests: one offline turn per model against a recording fake model ─
const scratch = mkdtempSync(join(tmpdir(), "copilot-prompt-"));
const home = join(scratch, "home");
mkdirSync(join(home, ".copilot", "extensions"), { recursive: true });
mkdirSync(join(scratch, "work"));
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
	const child = spawn(process.env.COPILOT_BIN ?? "copilot", ["-p", "hi"], {
		cwd: join(scratch, "work"),
		env,
		stdio: ["ignore", "ignore", "pipe"],
	});
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

// ── What each model would have received ─────────────────────────────────
const textOf = (content) => (typeof content === "string" ? content : (content ?? []).map((part) => part.text ?? "").join("\n"));
const instructions = readFileSync(join(deployed, "copilot-instructions.md"), "utf8").split("\n")[0];
const skills = readdirSync(join(deployed, "skills"), { withFileTypes: true }).filter((d) => !d.name.startsWith("."));
const models = process.env.COPILOT_TEST_MODELS?.split(",") ?? [
	...new Set([settings.model, "claude-sonnet-5.5", "gpt-5.6-luna"].filter((m) => m && m !== "auto")),
];

for (const model of models) {
	console.log(`\n── ${model}`);
	const { request, status, stderr } = await firstRequest(model);
	if (!request) {
		check(false, `Copilot sent no model request (exit ${status})`, stderr.trim().split("\n").slice(-3).join(" | "));
		continue;
	}
	const system = request.messages
		.filter((m) => m.role === "system" || m.role === "developer")
		.map((m) => textOf(m.content))
		.join("\n");
	const tools = request.tools.map((tool) => tool.function?.name ?? tool.custom?.name ?? tool.name);
	// Opening tags at the start of a line or right after a closing tag, outside
	// our own instructions and the skills list.
	const outline = system
		.replace(/<custom_instruction>[\s\S]*?<\/custom_instruction>/g, "<custom_instruction>")
		.replace(/<available_skills>[\s\S]*?<\/available_skills>/g, "");
	const blocks = [...outline.matchAll(/(?:^|<\/[a-z_]+>\s*)<([a-z_]+)>/gm)].map((m) => m[1]);
	const unexpected = blocks.filter((block) => !expectedBlocks.includes(block));

	check(system.includes("operating inside GitHub Copilot CLI"), "pi-style intro replaces Copilot's");
	check(system.includes(instructions), `AGENTS.md is included ("${instructions}")`);
	const missing = skills.filter((skill) => !system.includes(`<name>${skill.name}</name>`)).map((skill) => skill.name);
	check(missing.length === 0, `all ${skills.length} pi skills are listed`, `missing: ${missing.join(", ")}`);
	check(!system.includes("customize-cloud-agent"), "Copilot's built-in skills are left out");
	check(unexpected.length === 0, "only expected prompt blocks remain", `unexpected: ${unexpected.join(", ")}; drop them in the extension if they're guidance`);
	const extra = tools.filter((tool) => !["bash", "view", "edit", "create", "apply_patch", "skill"].includes(tool));
	check(extra.length === 0, `tools: ${tools.join(", ")}`, `unexpected: ${extra.join(", ")}`);
	check(tools.includes("edit") || tools.includes("apply_patch"), "the model has a file-editing tool");
	const estimate = Math.round((system.length + JSON.stringify(request.tools).length) / 4);
	check(estimate < 6000, `about ${estimate} tokens of system prompt and tools (default is ~15k)`);
}

server.close();
rmSync(scratch, { recursive: true, force: true });
process.exit(failures > 0 ? 1 : 0);
