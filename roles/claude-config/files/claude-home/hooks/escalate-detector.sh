#!/usr/bin/env bash
# escalate-detector.sh: Stop hook — detect "Qwen is stuck" patterns and remind
# the user to escalate.
#
# Heuristics:
#   - Transcript file (last ~200 lines) contains 3+ verify_commands failures
#     in the current session
#   - Or: same path/error appears 3+ times (model loop)
#   - Or: session ended after >10 minutes wallclock (stale / cold)
#
# When triggered, emit a short hint to stdout pointing the user at the
# `escalate-to-claude` skill (Qwen-only sessions) or suggesting they re-run
# with plain `claude`.
#
# Inputs (via stdin, JSON):
#   {"session_id": "...", "transcript_path": "...", "stop_hook_active": false}
#
# Behaviour:
#   - exit 0 always; stdout is shown to the user (not the model).
#   - Avoid loops: if stop_hook_active is true, no-op.

set -u

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
stop_active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false')"
[ "$stop_active" = "true" ] && exit 0

transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty')"
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0

# Qwen-only gate: ANTHROPIC_BASE_URL is set by claude-qwen.sh's ephemeral
# settings.json and propagated through to hook subprocesses. If it isn't set
# OR doesn't point at the Codens RunPod gateway, this is plain `claude` —
# exit silently. The earlier "transcript mentions Qwen" fallback false-fired
# in plain Anthropic sessions that merely discussed Qwen (observed 2026-04-28).
case "${ANTHROPIC_BASE_URL:-}" in
  *proxy.runpod.net*|*qwen-gw.vps.example.com*) ;;
  *) exit 0 ;;
esac

# Heuristic: count "verify_rc=" non-zero or "POST-WRITE VERIFY FAILED" warnings.
fail_count=$(tail -n 500 "$transcript" 2>/dev/null | grep -cE 'verify_rc=[1-9]|POST-WRITE VERIFY FAILED|exceeded max executions|exited with code [^0]' || true)

if [ "${fail_count:-0}" -ge 3 ]; then
  cat <<'HINT_EOF'

[VPS-HOOK escalate-detector] このセッションで verify / write が 3 回以上失敗しています。
Qwen が同じパターンに引っかかっている可能性があります。次のいずれかを検討してください:
  • `~/.claude/skills/escalate-to-claude` を呼び出して upstream Claude (Sonnet/Opus) に投げる
  • そのまま `claude` (OAuth Max) で同じプロンプトを再実行する
  • verify_commands / プロンプトを見直して制約を明示する (.claude/rules/verify-commands.md 参照)

HINT_EOF
fi

exit 0
