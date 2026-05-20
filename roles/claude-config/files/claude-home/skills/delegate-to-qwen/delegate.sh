#!/usr/bin/env bash
# delegate-to-qwen: hand off a cheap / one-shot subtask to the self-hosted
# Qwen gateway. Mirror of escalate-to-claude, opposite direction.
#
# Usage:
#   delegate.sh "prompt"                   # arg
#   echo "prompt" | delegate.sh            # stdin
#   delegate.sh --max-tokens 8192 "..."    # override (default 4096 for delegations)
#
# Refuses to run when ANTHROPIC_BASE_URL is set (= already inside a
# Qwen-backed session) to prevent self-loops.

set -euo pipefail

MAX_TOKENS=4096   # delegated tasks are usually small — keep tight
PROMPT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --max-tokens)
      MAX_TOKENS="${2:?--max-tokens requires a value}"
      shift 2
      ;;
    --max-tokens=*)
      MAX_TOKENS="${1#--max-tokens=}"
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
      if [ -z "$PROMPT" ]; then
        PROMPT="$*"
      fi
      break
      ;;
  esac
done

# Read from stdin if no arg given
if [ -z "$PROMPT" ] && [ ! -t 0 ]; then
  PROMPT="$(cat)"
fi

if [ -z "$PROMPT" ]; then
  echo "error: empty prompt." >&2
  exit 1
fi

# --- Sanity gate: refuse if ALREADY in qwen session ---
# ANTHROPIC_BASE_URL is set by claude-qwen.sh's ephemeral settings. If it's
# set, we're inside Qwen and delegating to Qwen would loop.
if [ -n "${ANTHROPIC_BASE_URL:-}" ]; then
  cat >&2 <<EOF
error: 'delegate-to-qwen' is for regular Claude sessions only.
       ANTHROPIC_BASE_URL is set ($ANTHROPIC_BASE_URL), so you appear to
       be inside Qwen already. Delegating Qwen → Qwen is a no-op self-loop.
       Just answer the user with the existing Qwen context.
EOF
  exit 2
fi

# --- Verify the wrapper exists ---
WRAPPER="$HOME/.claude/scripts/claude-qwen.sh"
if [ ! -x "$WRAPPER" ]; then
  echo "error: $WRAPPER not found / not executable. Has the claude-config role been deployed?" >&2
  exit 3
fi

# --- Optional invocation log ---
LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
{
  printf '%s delegate-to-qwen max_tokens=%s\n' "$(date -u +%FT%TZ)" "$MAX_TOKENS"
  printf '  prompt: %s\n' "$(printf '%s' "$PROMPT" | head -c 200 | tr '\n' ' ')"
} >> "$LOG_DIR/delegate.log" 2>/dev/null || true

# --- Run via claude-qwen wrapper in non-interactive mode ---
# The wrapper exec's `claude --settings <ephemeral> --model vllm-qwen,...`.
# We pass `-p` for one-shot mode. CLAUDE_CODE_MAX_OUTPUT_TOKENS env override
# tightens the response budget vs the wrapper default (16384) since
# delegations are usually short.
CLAUDE_CODE_MAX_OUTPUT_TOKENS="$MAX_TOKENS" "$WRAPPER" -p "$PROMPT"
