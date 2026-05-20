#!/usr/bin/env bash
# escalate-to-claude: delegate a hard subtask to upstream Anthropic Claude.
#
# Usage:
#   escalate.sh "prompt"                # arg
#   echo "prompt" | escalate.sh         # stdin
#   escalate.sh --model opus "..."      # override model (default: sonnet)
#
# Refuses to run when ANTHROPIC_BASE_URL is unset (= regular Claude session)
# to prevent self-recursion. Stripped env vars in subprocess so the inner
# `claude -p` falls back to OAuth Max plan keychain.

set -euo pipefail

MODEL="sonnet"
PROMPT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --model)
      MODEL="${2:?--model requires a value}"
      shift 2
      ;;
    --model=*)
      MODEL="${1#--model=}"
      shift
      ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --)
      shift
      PROMPT="$*"
      break
      ;;
    -*)
      echo "error: unknown flag: $1" >&2
      exit 1
      ;;
    *)
      PROMPT="$1"
      shift
      break
      ;;
  esac
done

# fallback to stdin if no arg
if [ -z "$PROMPT" ]; then
  if [ -t 0 ]; then
    echo "error: no prompt given. usage: $0 'prompt' or pipe via stdin." >&2
    exit 1
  fi
  PROMPT="$(cat)"
fi

if [ -z "$PROMPT" ]; then
  echo "error: empty prompt." >&2
  exit 1
fi

# --- Sanity gate: refuse if not running under qwen gateway ---
# claude-qwen.sh sets ANTHROPIC_BASE_URL via the ephemeral settings.json.
# If unset, we're in a regular Claude session and escalating would be
# self-recursive (Claude calling Claude).
if [ -z "${ANTHROPIC_BASE_URL:-}" ]; then
  cat >&2 <<'EOF'
error: 'escalate-to-claude' is for Qwen-backed sessions only.
       ANTHROPIC_BASE_URL is unset, so you appear to be running under
       regular Claude. Calling Claude from Claude is self-recursive and
       wastes Max-plan tokens — just answer the user directly.
EOF
  exit 2
fi

# --- Verify gateway URL looks legitimate (defense vs. accidental misconfigure) ---
case "$ANTHROPIC_BASE_URL" in
  *proxy.runpod.net*) ;;
  *)
    echo "warn: ANTHROPIC_BASE_URL ($ANTHROPIC_BASE_URL) doesn't look like the" >&2
    echo "      Codens RunPod gateway. proceeding anyway, but check for misconfig." >&2
    ;;
esac

# --- Optional invocation log ---
LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
{
  printf '%s escalate-to-claude model=%s\n' "$(date -u +%FT%TZ)" "$MODEL"
  printf '  prompt: %s\n' "$(printf '%s' "$PROMPT" | head -c 200 | tr '\n' ' ')"
} >> "$LOG_DIR/escalate.log" 2>/dev/null || true

# --- Run upstream Claude ---
# Strip all qwen gateway env vars so the inner `claude -p` uses the OAuth
# keychain (Max plan), not the qwen gateway.
# Use absolute path /usr/bin/env to avoid PATH-wrapper shadowing on operator
# host (~/.local/bin/env is a PATH-setup wrapper, not real env).
exec /usr/bin/env \
  -u ANTHROPIC_BASE_URL \
  -u ANTHROPIC_AUTH_TOKEN \
  -u ANTHROPIC_API_KEY \
  -u CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS \
  -u CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC \
  -u CLAUDE_CODE_MAX_OUTPUT_TOKENS \
  -u API_TIMEOUT_MS \
  claude -p --model "$MODEL" -- "$PROMPT"
