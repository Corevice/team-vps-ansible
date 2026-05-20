---
name: notion-write
description: Writing to Notion (creating pages, updating database entries, adding comments, modifying properties). TRIGGER when the user wants to add/update/sync content TO Notion — task creation, log entries, doc updates, property changes. DO NOT TRIGGER for read-only Notion lookup (use Notion MCP fetch directly), and DO NOT trigger for Archon plan-loop tasks (use archon-notion-task skill instead, which has trigger-status protocol). Covers schema-fetch-first workflow, property type JSON formatting (the #1 cause of Qwen failures), and recovery from validation errors.
---

# Notion Write

Most Notion write failures come from **guessing the property schema** instead of fetching it first, and from **wrong JSON shape per property type**. This skill enforces both.

## Mandatory Workflow

1. **Identify target** — get the page or database ID from URL / user message. If only a name is given, run `mcp__claude_ai_Notion__notion-search` to find it.
2. **Fetch schema FIRST** — for database writes, run `mcp__claude_ai_Notion__notion-fetch` against the database URL. Read back: property names (case-sensitive), property types, and (for select / multi-select / status) the allowed option names.
3. **Build payload** matching the schema (see cheatsheet below).
4. **POST or PATCH** via `mcp__claude_ai_Notion__notion-create-pages` / `notion-update-page`.
5. **Verify** by reading back the page (one fetch is enough — don't re-read repeatedly).

Skipping step 2 is the most common cause of failure. **Always fetch the schema for the database you're writing to, even if you "know" it.** Schemas drift.

## Property Type JSON Cheatsheet

These are the EXACT shapes the Notion API expects. Wrong nesting = `validation_error`.

### Title (every database has exactly one)
```json
{"Name": {"title": [{"text": {"content": "My page title"}}]}}
```
Note: NOT `"title": "My page title"` — must be wrapped in `[{"text": {"content": ...}}]`.

### Rich text (long-form text properties + page body)
```json
{"Description": {"rich_text": [{"text": {"content": "free-form content"}}]}}
```
Annotations (bold, italic, color) go inside each rich_text element:
```json
{"rich_text": [{"text": {"content": "bold word"}, "annotations": {"bold": true}}]}
```

### Select (single value)
```json
{"Priority": {"select": {"name": "High"}}}
```
**The `name` MUST match an existing option exactly (case-sensitive).** If you need a new option, the Notion API will reject; ask the user or update the schema first.

### Multi-select
```json
{"Tags": {"multi_select": [{"name": "bug"}, {"name": "urgent"}]}}
```

### Status (NOT the same as select — added 2022)
```json
{"Status": {"status": {"name": "In Progress"}}}
```
A common mistake: the schema shows `Status` is type `status`, but you build `{"select": {"name": ...}}`. → fails. Always check the schema's reported type.

### Date (single point or range)
```json
{"Due": {"date": {"start": "2026-05-03"}}}
{"Sprint": {"date": {"start": "2026-05-01", "end": "2026-05-15"}}}
```
Format: ISO 8601 (`YYYY-MM-DD` for date-only, `YYYY-MM-DDTHH:MM:SS+09:00` for datetime). Arbitrary strings like "May 3, 2026" fail.

### Number
```json
{"Estimate": {"number": 5}}
```
Must be a JSON number, not a string `"5"`.

### Checkbox
```json
{"Done": {"checkbox": false}}
```

### URL / Email / Phone
```json
{"Link":  {"url": "https://example.com"}}
{"Email": {"email": "user@example.com"}}
{"Phone": {"phone_number": "+81-90-..."}}
```

### People (assignees)
```json
{"Assignee": {"people": [{"id": "USER-UUID"}]}}
```
You need the **user UUID**, not email or name. Use `mcp__claude_ai_Notion__notion-get-users` to look it up first. Email rejection is a common failure mode.

### Relation (link to other DB pages)
```json
{"Project": {"relation": [{"id": "PAGE-UUID"}]}}
```
The page UUID must come from a database that the property is configured to relate to. Cross-database relations need both DBs in the same workspace.

### Files (attachments via URL)
```json
{"Files": {"files": [{"name": "diagram.png", "external": {"url": "https://..."}}]}}
```
Notion-hosted file uploads are not directly supported via API — use external URLs.

### Read-only properties (never write these)
- `formula` — computed
- `rollup` — computed
- `created_time` / `last_edited_time` — auto
- `created_by` / `last_edited_by` — auto

If you include these in a write, the API rejects with `body failed validation`.

## Writing the Page Body (Children Blocks)

Page bodies use a separate `children` array of block objects, not `properties`:

```json
{
  "children": [
    {"object": "block", "type": "heading_1", "heading_1": {"rich_text": [{"text": {"content": "Section title"}}]}},
    {"object": "block", "type": "paragraph",  "paragraph":  {"rich_text": [{"text": {"content": "Body text."}}]}},
    {"object": "block", "type": "to_do",      "to_do":      {"rich_text": [{"text": {"content": "Item"}}], "checked": false}},
    {"object": "block", "type": "code",       "code":       {"rich_text": [{"text": {"content": "x = 1"}}], "language": "python"}}
  ]
}
```

Block types you'll commonly need: `paragraph`, `heading_1` / `heading_2` / `heading_3`, `bulleted_list_item`, `numbered_list_item`, `to_do`, `code`, `quote`, `divider`, `callout`, `bookmark`, `image`.

## Common Validation Errors and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `body.properties.X.title should be defined` | Wrote `select`/`rich_text`/etc. into the title property | Title is always type `title`; use `{"title": [{"text": {"content": "..."}}]}` |
| `body.properties.X.select.name should be a valid option` | Option name typo / case mismatch | Re-fetch schema, copy exact spelling |
| `body.properties.X should be type Y but is Z` | Confused select vs status, or wrote rollup | Check schema, match property's actual type |
| `body.parent.database_id should match UUID format` | Using URL slug instead of UUID | Strip dashes/letters from URL: last 32 hex chars are the UUID |
| `Could not find database with ID` | DB not shared with the integration | User adds integration to the page (Notion UI: ⋯ → Connections) |
| `body.properties.X.people.[0].id should be a valid uuid` | Passed email/name instead of user UUID | `notion-get-users` to map name → UUID |

## Update vs Create

- **Create new page in DB**: `notion-create-pages` with `parent.database_id` and `properties`.
- **Update existing page properties**: `notion-update-page` with the page UUID and only the changed properties.
- **Append to page body**: `notion-update-page` is for properties only — to add blocks to the body, use the MCP server's append endpoint or recreate the page.

## Don't

- **Don't guess property names** — the schema may have non-obvious capitalization (`Owner` vs `owner`, `Last Edit` vs `Last edit`).
- **Don't re-read the same page** repeatedly during a single write — fetch once, build payload, post.
- **Don't fail-loop**: if the API rejects 2 times for related reasons, STOP and ask the user. Same wrong shape on attempt 3 is unproductive.
- **Don't emit secrets** — Notion content is searchable. Don't paste API keys, credentials, or internal tokens into pages.

## Quick Recipe — Add a Task to a Generic DB

```
1. Fetch schema:    notion-fetch <db-url>
2. Identify properties to set (Title, Status, Assignee, Due, Tags)
3. Look up referenced UUIDs (notion-get-users for assignee)
4. Build properties dict matching exact types from step 1
5. notion-create-pages with parent.database_id + properties (+ children if body needed)
6. Read back once to confirm
```
