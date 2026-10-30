// Trims Copilot CLI's built-in system prompt and tools to roughly pi's size
// (~3.6k tokens per request instead of ~15k), keeping our AGENTS.md
// (custom_instructions), the skills list and the environment details.
//
// Needs `copilot config experimental true`, which enables user extensions.
// Without it, Copilot simply runs with its full default prompt.
// Section names: SystemMessageSection in the bundled copilot-sdk types.d.ts.
import { joinSession } from "@github/copilot-sdk/extension";

// pi's intro and rules, with Copilot's tool names.
const identity = `You are an expert coding assistant operating inside GitHub Copilot CLI. You help users by reading files, executing commands, editing code, and creating new files.

<rules>
- Use bash for file operations like ls, rg, fd
- Use view to examine files instead of cat or sed
- Use edit for precise changes to existing files; use create only for new files
- Be concise in your responses
- Show file paths clearly when working with files
</rules>`;

const remove = { action: "remove" };
// The per-tool instructions also carry the skills list; keep only that.
const keepSkills = (content) => content.match(/<available_skills>[\s\S]*<\/available_skills>/)?.[0] ?? "";
// Drop the model-specific "be extremely biased for action" block, which
// contradicts AGENTS.md's ask-when-ambiguous rule.
const dropPersistence = (content) =>
	content.replace(/<solution_persistence>[\s\S]*?<\/solution_persistence>\s*/, "");

await joinSession({
	availableTools: ["bash", "view", "edit", "create", "skill"],
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
			runtime_instructions: { action: dropPersistence },
			last_instructions: remove,
		},
	},
});
