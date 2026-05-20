---
name: escalate-to-claude
description: |
  [QWEN-BACKED SESSIONS ONLY] Delegate a hard subtask to upstream Anthropic
  Claude (Sonnet/Opus via OAuth Max plan). Use ONLY when (a) the current
  session is running on the self-hosted Qwen gateway (ANTHROPIC_BASE_URL is
  set to a *.proxy.runpod.net URL) AND (b) the current step requires
  reasoning that Qwen3.6-27B can't reliably handle (complex multi-file
  refactor, deep architecture analysis, security/crypto review, algorithmic
  correctness). DO NOT invoke from a regular Claude session — that would be
  self-recursive and waste tokens; just answer directly. The bundled
  `escalate.sh` script enforces this gate (refuses if ANTHROPIC_BASE_URL is
  unset).
---

# escalate-to-claude

Hand off a specific hard subtask to upstream Claude Sonnet (default) or
Opus, and return the result. Designed for Qwen-backed Claude Code sessions
that have hit Qwen3.6-27B's reasoning ceiling.

## When to use

✅ **Invoke when all of the following are true:**

1. The user is running `claude-qwen` (≈ `ANTHROPIC_BASE_URL` is a
   `*.proxy.runpod.net` URL pointing to the Codens self-hosted Qwen gateway)
2. The current step requires capability beyond what Qwen3.6-27B reliably
   delivers, such as:
   - Complex multi-file refactor with subtle invariants (transactions,
     concurrency, ordering)
   - Deep architecture / system design with non-obvious tradeoffs
   - Security review of authentication / authorization / tenant isolation
   - Cryptographic protocol reasoning
   - Algorithmic correctness or proof-style reasoning
3. You've considered whether Qwen could plausibly handle it, and concluded
   it can't.

❌ **Do NOT invoke when:**

- You're running under regular `claude` (no `ANTHROPIC_BASE_URL`). You ARE
  Claude — calling yourself is self-recursive and wastes Max-plan budget.
  The script exits with code 2 in this case.
- The task is in Qwen's wheelhouse: simple file edits, lookups, doc
  generation, plain refactors, glue-code, summaries. Use Qwen directly.
- The subtask is trivial. One round trip = one Claude turn billed against
  the operator's Max-plan limit. Don't escalate `lint this file`.

## How to invoke

Pass the prompt as an argument or via stdin:

```bash
# short prompt as arg
~/.claude/skills/escalate-to-claude/escalate.sh "Refactor src/auth.ts to use a strategy pattern. Provide the full diff with rationale."

# long / multi-line prompt via stdin (heredoc)
~/.claude/skills/escalate-to-claude/escalate.sh <<'PROMPT'
Review the following 3 files for race conditions in worker rotation logic.
Identify any window where a worker can hold a lock while another claims it.

--- file: worker.py ---
... (paste content)

--- file: scheduler.py ---
...
PROMPT

# choose model (default is sonnet; use opus for very hard reasoning)
~/.claude/skills/escalate-to-claude/escalate.sh --model opus "..."
```

The script writes Claude's reply to stdout. Read it carefully — don't
blindly paste it back to the user; integrate it into your reasoning and
take the next action.

## What the script does

1. Refuses (exit 2) if `ANTHROPIC_BASE_URL` is unset (= you're already real
   Claude). This makes the skill safe to leave in `~/.claude/skills/` on
   regular Claude installs.
2. Strips `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`,
   and qwen-specific tuning env vars from the subprocess environment, so
   the inner `claude -p` falls back to the OAuth keychain (= Max plan
   inference, NOT API metered).
3. Runs `claude -p --model <model> -- "<prompt>"`.
4. Logs invocations to `~/.claude/logs/escalate.log` (200-char prompt
   prefix + timestamp) — useful for tracking how often qwen escalates.

## Cost note

Each invocation = one upstream Claude turn billed against the operator's
**Max-plan inference budget**. Max plan is high but not infinite — burning
escalations on every step defeats the point of running Qwen for cost
savings. Use sparingly; prefer Qwen unless you have a concrete reason it
won't suffice.

If you find yourself escalating > ~3× per session, that's a signal to drop
out of qwen mode and run regular `claude` directly for that session.
