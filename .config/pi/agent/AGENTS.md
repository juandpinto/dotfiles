# Global agent instructions

- Prefer the simplest solution that fully solves the problem. Add abstraction, configuration, or generality only when there's a concrete, current need for it — not speculative future-proofing. Some complexity is necessary; don't strip it out just to look simple.
- If a decision is genuinely ambiguous and consequential, ask before proceeding rather than guessing and moving on.
- After changing code, verify it actually works: run the project's tests/linters if it has them, otherwise do a concrete manual check (syntax check, dry run, sanity read). Don't declare a change done on faith.
- Match existing conventions in a repo (style, structure, tooling) before introducing new patterns or dependencies.
- Don't commit, push, force-push, or rewrite git history without being asked. Follow a repo's existing commit-message conventions.
- Never commit secrets, tokens, or credentials. Flag it if a change risks exposing something sensitive.
- Confirm before destructive or hard-to-reverse operations (e.g. `rm -rf`, overwriting files, force-push).
- Prefer `rg`/`fd` over `grep`/`find` for searching — faster, and skip `.gitignore`'d noise (`node_modules`, `.git`) by default. Use `--no-ignore`/`-uu` if you need to search inside ignored paths.
- Use `curl` for web/research lookups (docs, Google/Scholar, general info gathering), and `gh` for anything involving GitHub repos, issues, or PRs.

## Skills

- When writing, editing, or running any Python (`.py`) file, make sure you're following the conventions laid out in the `python` skill — don't rely on inferring these from context.
- When writing or editing any Markdown documentation, make sure you're following the conventions laid out in the `documentation` skill — don't rely on inferring these from context.
