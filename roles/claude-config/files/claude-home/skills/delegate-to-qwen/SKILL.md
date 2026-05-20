---
name: delegate-to-qwen
description: |
  [REGULAR CLAUDE SESSIONS ONLY] Hand off a cheap / bulk subtask to the
  self-hosted Qwen3.6-27B gateway to save Anthropic Max-plan tokens. Use
  when the current session is plain `claude` (Anthropic OAuth) AND the
  pending step is small enough that Qwen can handle it well: short summary,
  routine extraction, simple format conversion, mass parallel processing,
  or one-shot questions where you don't need Sonnet/Opus reasoning. The
  bundled `delegate.sh` script enforces the gate (refuses to run from
  Qwen-backed sessions, where it would be a self-loop).
---

# delegate-to-qwen

Push a one-shot subtask to the Codens self-hosted Qwen3.6-27B gateway and
return the response. Mirror of `escalate-to-claude`, opposite direction —
this is for regular Claude sessions to offload cheap work.

## When to use

✅ **Invoke when all of the following are true:**

1. The current session is regular `claude` (Anthropic OAuth via Max plan).
2. The pending step does NOT need Sonnet/Opus-level reasoning. Good
   candidates:
   - Summarize this Slack thread / log file in 5 lines
   - Extract entities (names, URLs, dates) from a blob
   - Translate / reformat / rewrite tone
   - Generate boilerplate (one file, no architecture choices)
   - Parallel: process N independent items where each is small
   - "Just answer this trivia / lookup question"
3. You have either a clear, self-contained prompt OR can construct one
   without too much round-tripping.

❌ **Do NOT invoke when:**

- The session is already Qwen-backed (`claude-qwen`). Calling Qwen from
  Qwen is a no-op self-loop. The gate script will refuse.
- The task needs precise multi-file reasoning, security review, deep
  architecture understanding, or anything where Qwen's known weaknesses
  bite (see `~/.claude/CLAUDE.md` notes about Qwen behaviour: partial
  implementation, fire-and-forget tool calls, structural skips).
- Output quality matters more than cost (e.g. final user-facing prose,
  production code reviews).

## How to call

The skill ships `delegate.sh`. Two invocation styles:

```bash
# arg form
~/.claude/skills/delegate-to-qwen/delegate.sh "Summarize the last 50 lines of /var/log/foo.log in 5 bullet points"

# stdin form (preferred for large prompts)
cat /tmp/big-prompt.txt | ~/.claude/skills/delegate-to-qwen/delegate.sh
```

The script:
1. Verifies you are NOT inside a Qwen session (`ANTHROPIC_BASE_URL` unset).
2. Sets the Qwen gateway env vars + invokes `claude-qwen.sh -p "<prompt>"`.
3. Streams the response back to stdout.
4. Logs each call to `~/.claude/logs/delegate.log` with model + prompt
   preview, so you can audit cost/usage.

Exit codes:
- `0` — Qwen returned a response (forwarded to stdout).
- `2` — refused: session is already Qwen-backed (would self-loop).
- non-zero — Qwen / gateway / wrapper itself failed.

## Tips

- Keep prompts self-contained. Qwen does not see your conversation history
  unless you include it in the prompt explicitly.
- For parallel bulk work, spawn multiple `delegate.sh` calls via
  `xargs -P` or shell `&`. The Qwen gateway has 8 concurrent slots — going
  beyond means some queue. (Hours: only available when the production pod
  is running; check `~/.claude/hooks/monitor-qwen.log`.)
- Cost per delegation is effectively zero from the user's perspective
  (the pod runs on a fixed weekday cron — incremental requests are free).

## Why this exists

Anthropic Max plan tokens are a finite weekly budget. Routine work like
summarization and extraction doesn't require Sonnet/Opus and burns budget
that's better spent on hard reasoning. The Qwen gateway is paid for as a
flat hourly rental, so additional calls cost nothing extra. This skill
lets a regular Claude session push the cheap stuff to Qwen and keep its
own context for the work that actually needs Anthropic-grade reasoning.
