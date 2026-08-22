---
name: personal-wiki
description: Personal, LLM-maintained knowledge base for life outside work — job search, consulting/freelance work, personal finances, personal-computing setup, and other side projects. Use ONLY when the user explicitly references the personal wiki, e.g. "ingest into the personal wiki", "update the personal wiki", "promote to the personal wiki", "query the personal wiki", or "file this into the personal wiki".
---

# Personal wiki — operations

This wiki is a personal, LLM-maintained knowledge base covering job search, consulting/freelance work, personal finances, personal-computing setup, and other side projects, located at `~/Documents/personal-wiki/`. It's a curated synthesis, not a transcript — project-specific mechanics stay in each project's own docs (see `related-sources.md` in the wiki). **When performing wiki operations** (Ingest, Update wiki, Promote, Query, Lint), treat source files in project repos as read-only — only create or modify files within `~/Documents/personal-wiki/`.

## Directory structure

- `index.md` — catalog of all wiki pages with one-line summaries per page; read this during Query and Ingest to identify relevant pages — page summaries surface files that semantic search misses when terminology varies across pages
- `log.md` — append-only operations log; format: `## [YYYY-MM-DD] <operation> | <description>`
- `related-sources.md` — pointers to directories *outside* the wiki that are relevant to it (the `zk` research vault, active job-search folders, the beancount ledger, dotfiles, etc.); read this alongside `index.md` when a query or ingest source touches one of those domains
- `wip/` — in-flight scratchpad; not stable knowledge
- `concepts/` — cross-cutting ideas and decisions that span multiple projects/domains — this is the cross-pollination layer
- `projects/` — one subfolder per active area (`job-search/`, `finances/`, `consulting/`, `personal-computing/`, plus new ones as they come up)

## Conventions

- Cross-references use Foam-style wikilinks: `[[emergency-fund-policy]]` or with display text: `[[emergency-fund-policy|emergency fund policy]]` — plain-text convention, no specific editor/tool required
- Every concept page has a `## Decisions` section using structured bullet lists (not tables): each entry is a `### [YYYY-MM] Title` subheading with `**Decision**`, `**Rationale**`, `**Alternatives rejected**`, and optionally `**Caveats / open questions**` bullets
- Every wiki page has YAML frontmatter with at least `tags:` (comma-separated, lowercase, hyphenated)
- Every new or updated page gets its entry updated in `index.md`
- Every wiki operation appends a line to `log.md`
- Don't hard-wrap prose — let lines wrap naturally (see `/skill:documentation`)

## Named operations

### Ingest

User says: "ingest [source] into the personal wiki" or "file this into the personal wiki"

- Source can be a local file or a pasted excerpt

1. Read the source material
2. Read `index.md` to see what pages already exist on the topic; also check `related-sources.md` if the source touches job search, consulting, finances, research background, or personal-computing setup/dotfiles — those directories may already have relevant context
3. Read the relevant existing pages
4. Determine what is new vs. what updates existing pages
5. Update or create pages as needed; keep each page to one concept
6. Update `index.md` with any new pages or changed summaries; append to `log.md`
7. Summarize what was changed and what pages were touched

### Update wiki

User says: "update the personal wiki with this decision/finding"

Same as Ingest but scoped to a single item rather than a full source document. Skip the `index.md` scan if you already know which page to update.

### Promote

User says: "promote [wip file] to the personal wiki" (or: highlight text in a wip file and say "promote this to the personal wiki")

1. Read the wip content (or use the user's text selection as the source)
2. Determine the appropriate destination folder and file name
3. Create or update the target page, integrating the content
4. Update `index.md`; append to `log.md`
5. Delete the wip file or selected content (ask if unsure)

### Query

User asks a question against the personal wiki.

1. Read `index.md` to identify which pages are relevant to the question — page summaries often surface files that semantic search misses when terminology varies
2. Read the relevant pages
3. If the question touches a domain listed in `related-sources.md` (e.g. research background, a specific job application, the ledger itself, or personal-computing setup), read the relevant non-wiki source too — treat it as read-only
4. Synthesize an answer with links to the source pages
5. If the answer represents a significant new synthesis, ask the user if it should be filed as a `concepts/` or `projects/` page

### Semantic lint

User says: "run a semantic lint pass on the personal wiki" (or: "check [specific pages] for contradictions")

- Targeted scope only: user must specify which pages or topics to check
- Check for: contradictions between the specified pages, stale claims superseded by newer pages, concepts mentioned without a dedicated page
- Structural issues (orphan pages, broken links) are handled by markdownlint, not by this operation
- Report findings as a list; do not auto-fix
