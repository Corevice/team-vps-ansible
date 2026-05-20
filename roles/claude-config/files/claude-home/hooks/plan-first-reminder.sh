#!/usr/bin/env bash
# plan-first-reminder.sh: UserPromptSubmit hook.
#
# When the user's prompt contains keywords suggesting a multi-file or
# structural-refactor task (the failure modes Qwen 3.6-27B-FP8 stochastically
# stumbles on per the 2026-04-26 A/B campaign), inject a concise plan-first
# reminder into the prompt context.
#
# Lighter-weight than the always-on _QWEN_SYSTEM_PROMPT_ADDENDUM in
# agent-service: that runs for every Qwen job; this only fires when the user
# is actually asking for the kind of task that benefits from explicit planning.
#
# Inputs (via stdin, JSON):
#   {"session_id": "...", "prompt": "...", "transcript_path": "..."}
#
# Behaviour:
#   - stdout: text to be appended to the prompt context (Claude Code default).
#   - exit 0 always (non-blocking).

set -u

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
prompt="$(printf '%s' "$input" | jq -r '.prompt // empty')"
[ -z "$prompt" ] && exit 0

# Keyword set tuned to the structural failure modes we observed:
#   - "split into N files" / "ファイル分割" / "別ファイル" — multi-file split
#   - "refactor" — semantic restructure
#   - "create new file" / "new module" / "新規ファイル" — fresh module from spec
#   - "wire up" / "register in" / "re-export" — integration coordination
#   - "multiple files" / "multi-file" — explicit signal
KEYWORD_RE='(split.{0,20}into|別ファイル|分割|ファイル作成|新規ファイル|new module|create new file|create [a-z_/]+\.py|create [a-z_/]+\.ts|wire[ -]?up|re[ -]?export|register in.*__init__|multi[- ]?file|multiple files|refactor.{0,20}into|extract.{0,20}into)'

# Match case-insensitively. Use grep -E rather than echo+pipe to avoid issues
# with tricky prompts (newlines, control chars).
if printf '%s' "$prompt" | grep -qiE "$KEYWORD_RE"; then
  cat <<'REMINDER_EOF'
[VPS-HOOK plan-first-reminder]
This prompt mentions multi-file or structural-refactor work. Before any tool call:
1. Output a numbered plan listing every file you will CREATE (with exact relative path) and every file you will EDIT (with exact relative path).
2. Implement in that order.
3. Before ending the turn, run `ls` or `test -f` on each CREATE path to confirm the file exists.
4. Do NOT inline classes or functions into existing files when the task says "create file X.py" — the path in your plan is a hard contract.
5. If you conclude no change is needed, emit `[PURPLE-NO-OP-VERIFIED-OK]` early in your summary so the no-op signal survives potential session kills.
REMINDER_EOF
fi

exit 0
