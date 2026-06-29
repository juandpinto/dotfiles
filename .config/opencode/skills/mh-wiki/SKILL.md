---
name: mh-wiki
description: Personal DS knowledge base wiki operations for McGraw Hill projects. Use ONLY when user says "ingest", "update the wiki", "promote", "query the wiki", "semantic lint", or "file this into the wiki".
---

# MH wiki — operations

This wiki is a personal, LLM-maintained knowledge base covering multiple active data science projects at McGraw Hill, located at `~/Documents/MH/mh-wiki/`. Projects span two product platforms: Connect (Databricks, event lake, mhhe_dsai_prod fact tables, Pendo) and Sharpen (BigQuery, dbt, microservice databases). The wiki is a curated synthesis, not a transcript. **When performing wiki operations** (Ingest, Update wiki, Promote, Query, Lint), treat source files in project repos as read-only — only create or modify files within `~/Documents/MH/mh-wiki/`.

## Directory structure

- `index.md` — catalog of all wiki pages with one-line summaries per page; read this during Query and Ingest to identify relevant pages — page summaries surface files that semantic search misses when terminology varies across pages
- `log.md` — append-only operations log; format: `## [YYYY-MM-DD] <operation> | <description>`
- `wip/` — in-flight scratchpad; not stable knowledge
- `concepts/` — cross-cutting domain concepts (time-spent variants, AI Reader, learner models, platform architectures)
- `data/` — data sources and table groups from both platforms (Connect/Databricks and Sharpen/BigQuery); each page includes a `platform:` frontmatter field to distinguish current storage
- `projects/` — one subfolder per project area (insights-lab, ai-reader-analysis, sharpen-radar, lomap-locam, mhplus-proficiency)
- `org/` — organizational context (org chart, glossary, project links, roles)
- `analyses/` — filed analysis outputs and validated methodologies

## Conventions

- Cross-references use Foam wikilinks: `[[time-spent-smartbook]]` or with display text: `[[time-spent-smartbook|SmartBook time spent]]`
- Every concept page has a `## Decisions` section using structured bullet lists (not tables): each entry is a `### [YYYY-MM] Title` subheading with `**Decision**`, `**Rationale**`, `**Alternatives rejected**`, and optionally `**Caveats / open questions**` bullets
- Every wiki page has YAML frontmatter with at least `tags:` (comma-separated, lowercase, hyphenated)
- Every new or updated page gets its entry updated in `index.md`
- Every wiki operation appends a line to `log.md`

## Named operations

### Ingest

User says: "ingest [source]" or "file this into the wiki"

- Source can be a local file, a pasted excerpt, or a Confluence page (say "ingest [Confluence page title or URL]" — the Atlassian MCP will fetch the page content)

1. Read the source material
2. Read `index.md` to see what pages already exist on the topic; this surfaces pages that semantic search might miss because their text doesn't share exact terminology with the source
3. Read the relevant existing pages
4. Determine what is new vs. what updates existing pages
5. Update or create pages as needed; keep each page to one concept
6. Update `index.md` with any new pages or changed summaries; append to `log.md`
7. Summarize what was changed and what pages were touched

### Update wiki

User says: "update the wiki with this decision/finding/methodology"

Same as Ingest but scoped to a single item rather than a full source document. Skip the `index.md` scan if you already know which page to update.

### Promote

User says: "promote [wip file] to the wiki" (or: highlight text in a wip file and say "promote this to the wiki")

1. Read the wip content (or use the user's text selection as the source)
2. Determine the appropriate destination folder and file name
3. Create or update the target page, integrating the content
4. Update `index.md`; append to `log.md`
5. Delete the wip file or selected content (ask if unsure)

### Query

User asks a question against the wiki.

1. Read `index.md` to identify which pages are relevant to the question — page summaries often surface files that semantic search misses when terminology varies
2. Read the relevant pages (supplement with `@workspace` if the index scan suggests related pages not already identified)
3. If the user says "also check Confluence", use the Atlassian MCP to search Confluence for relevant pages and incorporate findings alongside wiki content
4. Synthesize an answer with links to the source pages
5. If the answer represents a significant new synthesis, ask the user if it should be filed as an `analyses/` page

### Semantic lint

User says: "run a semantic lint pass" (or: "check [specific pages] for contradictions")

- Targeted scope only: user must specify which pages or topics to check (e.g. "check the three time-spent concept pages for contradictions")
- Check for: contradictions between the specified pages, stale claims superseded by newer pages, concepts mentioned without a dedicated page, platform confusion (Connect/Databricks concepts in Sharpen pages or vice versa)
- Structural issues (orphan pages, broken links) are handled by Foam and markdownlint, not by this operation
- Report findings as a list; do not auto-fix
