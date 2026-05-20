#!/usr/bin/env bash
# qwen-no-action-detector.sh: Stop hook for Qwen-routed sessions.
#
# Detects the "verbal acknowledgment with no action" pattern (observed
# 2026-04-27 on peoplex-1: user asks Qwen to fetch + read docs, Qwen replies
# "了解です。確認します。" and ends the turn without making any tool call).
#
# When the most recent user message looks like a directive AND the most
# recent assistant turn made zero tool calls, output decision=block so
# Claude Code re-prompts the model with a corrective message. The model
# then has another shot at actually doing the work using tools.
#
# Loop guard: respect the stop_hook_active field — Claude Code sets this
# when the previous Stop hook already blocked once. Skipping on the second
# pass prevents infinite loops if the model genuinely cannot act.
#
# Scope guard: only fire for Qwen-routed sessions (CLAUDE_QWEN_GATEWAY_URL
# in env or transcript references the gateway). For plain `claude` we don't
# need this — Anthropic models follow directives reliably.
#
# Inputs (stdin JSON):
#   {"session_id": "...", "transcript_path": "...", "stop_hook_active": false}
set -u

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
stop_active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false')"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"

# Per-session retry budget: claude code's stop_hook_active flag flips to true
# after a single block, which historically capped recovery at 1 retry per turn.
# That's not enough for Qwen — observed 2026-05-05 uninote-pbx-1 case where
# the model emitted thinking-only on retry, which the hook would normally
# catch but was silenced by the guard. We track retries per session_id in
# /tmp/qwen-stop-retries-<session_id>.cnt and allow up to MAX_RETRIES blocks
# per Stop event before respecting the guard.
MAX_RETRIES=3
retry_file="/tmp/qwen-stop-retries-${session_id:-unknown}.cnt"
if [ "$stop_active" = "true" ]; then
  current_retries=$(cat "$retry_file" 2>/dev/null || echo 0)
  if [ "$current_retries" -ge "$MAX_RETRIES" ]; then
    rm -f "$retry_file"  # reset for next Stop event
    exit 0  # respect the guard, give up
  fi
  echo "$((current_retries + 1))" > "$retry_file"
else
  # Fresh Stop event — reset retry counter
  rm -f "$retry_file" 2>/dev/null || true
fi

transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty')"
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0

# Qwen-only gate: ANTHROPIC_BASE_URL is set by claude-qwen.sh's ephemeral
# settings.json and propagated through to hook subprocesses. If it isn't set
# OR doesn't point at the Codens RunPod gateway, this is a plain `claude`
# session — exit silently. The earlier "transcript mentions Qwen" fallback
# false-fired in plain Anthropic sessions where the user just *talked* about
# Qwen (observed 2026-04-28).
case "${ANTHROPIC_BASE_URL:-}" in
  *proxy.runpod.net*|*qwen-gw.vps.example.com*) ;;
  *) exit 0 ;;
esac

# Pull the LAST assistant turn's content blocks as JSON array.
# Note: filter on type only — newer claude code transcript format (observed
# 2026-05-05) sets message.role to null on streaming chunks, which would
# exclude them from the older `role == "assistant"` filter and silently fall
# back to a stale earlier turn. Filter by type alone catches both formats.
last_assistant_blocks=$(jq -c -r '
  select(.type == "assistant" and (.message.content | type == "array"))
  | .message.content
' "$transcript" 2>/dev/null | tail -1)

# Count tool_use blocks in last assistant turn
last_tool_count=$(printf '%s' "$last_assistant_blocks" | jq -r '[.[]? | select(.type == "tool_use")] | length' 2>/dev/null || echo 0)

# Find what the LAST block was (text vs tool_use). When tool_use is the last block
# the model exited right after firing a tool without summarizing — that's the
# "fire-and-forget" partial-execution pattern (observed 2026-04-28 on a Slack MCP
# setup session: model called slack-personal once and ended the turn).
last_block_type=$(printf '%s' "$last_assistant_blocks" | jq -r '.[-1].type // ""' 2>/dev/null)

# Length of the trailing text block, if any
last_text_len=$(printf '%s' "$last_assistant_blocks" | jq -r '
  [.[] | select(.type == "text") | .text] | last // "" | length
' 2>/dev/null || echo 0)

# Total text length across all text blocks in this assistant turn
total_text_len=$(printf '%s' "$last_assistant_blocks" | jq -r '
  [.[] | select(.type == "text") | .text] | join("") | length
' 2>/dev/null || echo 0)

# Total tool_use count (same as last_tool_count, computed once)
total_tool_count=$(printf '%s' "$last_assistant_blocks" | jq -r '
  [.[] | select(.type == "tool_use")] | length
' 2>/dev/null || echo 0)

# Most recent user turn — text content. Same role-may-be-null caveat as above.
last_user_text=$(jq -r '
  select(.type == "user")
  | .message.content
  | if type == "string" then . else (.[]? | select(.type == "text") | .text) end
' "$transcript" 2>/dev/null | tail -1)

# Stop / cancel guard: if the user literally asked to stop, don't fire any
# pattern — they may legitimately want the assistant to stop.
stop_request_pattern='(中止|止めて|やめて|キャンセル|cancel|abort|^stop$|stop now|stop it|やめろ|止めろ)'
if printf '%s' "$last_user_text" | grep -qiE "$stop_request_pattern"; then
  exit 0
fi

# Directive language detection — "do work" patterns. Includes Japanese and
# English imperatives plus "続けて" / "進めて" / "continue" continuation cues.
directive_pattern='(してください|してくれ|くれます|して$|して。|確認して|取ってき|読んで|やって|実装して|作って|続けて|進めて|やり直して|fetch|create|implement|run|build|fix|read|edit|write|find|search|check|verify|reproduce|investigate|push|merge|deploy|setup|install|continue|finish|complete|keep going)'

# Only check directive prompts — non-directive (questions / chat) are fine to end
# with just text or even silence.
if ! printf '%s' "$last_user_text" | grep -qiE "$directive_pattern"; then
  exit 0
fi

# Pattern C: phantom-stop — model volunteered to stop / abort / pause work.
# Always fires if assistant text matches stop-volunteering phrases (we
# already passed the user-actually-wants-stop guard above).
last_assistant_text=$(printf '%s' "$last_assistant_blocks" | jq -r '
  [.[] | select(.type == "text") | .text] | join(" ")
' 2>/dev/null)

if printf '%s' "$last_assistant_text" | grep -qE 'やめます|中止します|止めます|stop here|I.{0,3}ll stop|let me know when to continue|何を中止|何を止め'; then
  reason='You volunteered to stop / abort / pause work that the user did not ask you to stop. Phrases like "了解、やめます" or "中止します" or "should I continue?" mid-task are hallucinations of a stop request. The user'\''s message is a directive — keep working toward the goal. Resume now: identify the next concrete sub-step toward the user'\''s original ask and execute it (with tool calls). If you genuinely need a yes/no decision, ask ONE specific question — but never apologise-and-pause. Phantom-stop overrides the [FINISHED] marker — you cannot end the turn this way.'
  jq -nc --arg r "$reason" '{decision: "block", reason: $r}'
  exit 0
fi

# Pattern D: explicit [FINISHED] marker — model confirms it's intentionally
# ending the turn (work done OR genuinely waiting on user). Allow.
# This comes AFTER phantom-stop check so "やめます [FINISHED]" still blocks.
if printf '%s' "$last_assistant_text" | grep -qF '[FINISHED]'; then
  exit 0
fi

# Pattern F: thinking-only end_turn (CCR-bypass / native Anthropic mode).
# After 2026-05-04 we expose vLLM /v1/messages directly which preserves
# thinking blocks. Some Qwen turns end with ONLY a thinking block and no
# text/tool — invisible to the user, looks like the session went silent.
# Catch this before Pattern A because Pattern A's reason talks about
# "acknowledgment text" which doesn't match thinking-only.
if [ "$last_block_type" = "thinking" ] && [ "${last_tool_count:-0}" -eq 0 ] && [ "${total_text_len:-0}" -eq 0 ]; then
  reason='Your previous turn ended with ONLY a thinking block — no visible text and no tool calls. The user sees nothing. You must EITHER: (1) output a plain-text answer summarizing what you found and emit [FINISHED] on its own line if the task is complete, OR (2) run the next tool needed to advance the user'\''s task. Do not end the turn after thinking only — the thinking is invisible to the user. If you genuinely believe the task is done, write a 1-2 line confirmation in plain text and end with [FINISHED].'
  jq -nc --arg r "$reason" '{decision: "block", reason: $r}'
  exit 0
fi

# Pattern A: zero tool calls — pure verbal acknowledgment
if [ "${last_tool_count:-0}" -eq 0 ]; then
  reason='Your previous turn produced only acknowledgment text with NO tool calls. The user'\''s message is a directive that requires action. You MUST use tools (Bash, Read, Edit, Write, Glob, Grep, etc) in this turn to actually do the work. Do NOT respond with "I will do that" and stop again. Make the tool call now. If you genuinely need clarification, ask ONE specific question and emit [FINISHED] on its own line — but never just acknowledge and exit silently. If the work IS truly complete and you'\''re reporting status, emit [FINISHED] alone on its own line as your final output.'
  jq -nc --arg r "$reason" '{decision: "block", reason: $r}'
  exit 0
fi

# Pattern B: turn ends ON tool_use, but only fire when this looks like
# "fire-and-forget" rather than a productive multi-tool exploration.
#
# Heuristic:
#   - tool_count == 1 AND text < 30 chars → naked single-shot, definitely fire
#   - tool_count >= 2 AND text >= 30 chars → multi-tool with narration, ALLOW
#     (model is in the middle of an exploratory chain like git status →
#     git diff → git log; forcing a stop after each is over-aggressive and
#     produces the "Ran 4 stop hooks" loop observed 2026-04-30 okibi-1)
#   - otherwise (mixed) → fire
# (total_tool_count + total_text_len computed earlier near top)

if [ "$last_block_type" = "tool_use" ]; then
  # Allow productive multi-tool chains with substantive narration
  if [ "${total_tool_count:-0}" -ge 2 ] && [ "${total_text_len:-0}" -ge 30 ]; then
    exit 0
  fi
  reason='You ran tool(s) but ended the turn ON a tool_use block with little or no narration — this is the "fire-and-forget" pattern. The user expects you to (1) read the tool output, (2) say in plain text what you found, and (3) either run the next required tool call or finalize the answer. Continue this turn now: review the tool result(s) above, summarize them in 1-3 lines, and either invoke the next tool needed for the user'\''s task (e.g. if they asked for "commit + push + tag", make sure all three actually ran) or write a complete confirmation that the task is finished and emit [FINISHED] on its own line.'
  jq -nc --arg r "$reason" '{decision: "block", reason: $r}'
  exit 0
fi

# Pattern E (strict): for directive prompts on Qwen-routed sessions, REQUIRE
# the [FINISHED] marker to end a turn. Pattern D (above) already lets through
# any turn with [FINISHED]; getting here means the model emitted a text-only
# conclusion after tool calls but never declared finished. Common failure mode:
# multi-tool research, narration ("Now let me check..."), then turn ends without
# actually creating the artifact the user asked for (investigation paralysis).
# Block to force either continuation OR explicit finalization.
reason='Turn ended without [FINISHED]. The user issued a directive that requires concrete action — research alone is not completion. Either continue with the next tool call needed to finish the work (e.g. if they asked you to CREATE something, the create tool must run), or — if the work is genuinely done — emit [FINISHED] on its own line as the very last text of the turn. Do not end with a "Now let me..." narration that was never followed up.'
jq -nc --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
