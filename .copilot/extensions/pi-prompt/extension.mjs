// Trims Copilot CLI's built-in system prompt and tools to roughly pi's size
// (~3.5k tokens per request instead of ~15k), keeping our AGENTS.md
// (custom_instructions), the skills list and the environment details.
//
// Needs `copilot config experimental true`, which enables user extensions.
// Without it, Copilot simply runs with its full default prompt.
// Section names: SystemMessageSection in the bundled copilot-sdk types.d.ts.
import { joinSession } from "@github/copilot-sdk/extension";

// pi's intro and rules, worded for both Copilot's edit/create tools (Claude,
// GPT-4.1) and apply_patch (GPT-5).
const identity = `You are an expert coding assistant operating inside GitHub Copilot CLI. You help users by reading files, executing commands, editing code, and creating new files.

<rules>
- Use bash for file operations like ls, rg, fd
- Use view to examine files instead of cat or sed
- Use your file-editing tools for precise changes, not shell commands
- Be concise in your responses
- Show file paths clearly when working with files
</rules>`;

// Model-specific guidance Copilot adds to runtime_instructions. That section
// also carries runtime notifications, the session folder, memories and any
// content-exclusion policy, so known blocks are dropped by name instead.
// "Bias to action" blocks contradict AGENTS.md's ask-when-ambiguous rule.
const guidance = [
	"solution_persistence",
	"autonomy_and_persistence",
	"preamble_messages",
	"user_progress_updates",
	"tool_use_guidelines",
	"editing_constraints",
	"exploration_and_reading_files",
	"destructive_actions",
	"subagent_usage",
	// Online, in GitHub repositories: how to write issue and PR references.
	"github_reference_formatting",
];
const dropGuidance = (content) =>
	guidance.reduce((text, tag) => text.replace(new RegExp(`<${tag}>[\\s\\S]*?</${tag}>\\s*`, "g"), ""), content);

const remove = { action: "remove" };
// The per-tool instructions also carry the skills list; keep only that.
const keepSkills = (content) => content.match(/<available_skills>[\s\S]*<\/available_skills>/)?.[0] ?? "";

await joinSession({
	// Copilot offers each model only its own editing tools: edit and create,
	// or apply_patch for GPT-5.
	availableTools: ["bash", "view", "edit", "create", "apply_patch", "skill"],
	includedBuiltinSkills: [],
	coauthorEnabled: false,
	systemMessage: {
		mode: "customize",
		sections: {
			identity: { action: "replace", content: identity },
			code_change_rules: remove,
			guidelines: remove,
			safety: remove,
			tool_instructions: { action: keepSkills },
			runtime_instructions: { action: dropGuidance },
			last_instructions: remove,
		},
	},
});
