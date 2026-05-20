#!/bin/bash
# PostToolUse hook for Bash — token saver inspired by RTK
# If tool stdout is large, return summary + a path where Claude can re-read full content.
# Reads PostToolUse JSON from stdin, prints replacement JSON to stdout.

set -u

INPUT=$(cat)
TOOL=$(jq -r '.tool_name // empty' <<<"$INPUT")
[ "$TOOL" != "Bash" ] && { echo "$INPUT"; exit 0; }

OUTPUT=$(jq -r '.tool_response.output // empty' <<<"$INPUT")
ORIG_LEN=${#OUTPUT}

# Threshold: keep small output untouched
THRESHOLD=${CLAUDE_OUTPUT_TRUNCATE_BYTES:-5000}
HEAD_LINES=${CLAUDE_OUTPUT_HEAD_LINES:-30}
TAIL_LINES=${CLAUDE_OUTPUT_TAIL_LINES:-30}

if [ "$ORIG_LEN" -le "$THRESHOLD" ]; then
  echo "$INPUT"
  exit 0
fi

# Save full output to /tmp/claude-out/<sha>
SAVE_DIR="/tmp/claude-out"
mkdir -p "$SAVE_DIR"
HASH=$(echo "$OUTPUT" | sha256sum | cut -c1-12)
SAVE_PATH="$SAVE_DIR/$(date +%Y%m%dT%H%M%S)_${HASH}.txt"
echo "$OUTPUT" > "$SAVE_PATH"

# Build summary: head + tail + size info
HEAD=$(echo "$OUTPUT" | head -n "$HEAD_LINES")
TAIL=$(echo "$OUTPUT" | tail -n "$TAIL_LINES")
TOTAL_LINES=$(echo "$OUTPUT" | wc -l)

# Tally common interesting lines (errors / warnings)
ERRORS=$(echo "$OUTPUT" | grep -ciE '^(error|fatal|fail)' || true)
WARNINGS=$(echo "$OUTPUT" | grep -ciE '^(warn|warning)' || true)

REPLACEMENT=$(cat <<TXT
[output-truncate hook] original: ${ORIG_LEN} bytes / ${TOTAL_LINES} lines / errors=${ERRORS} warnings=${WARNINGS}
Full output saved to: ${SAVE_PATH}
To inspect: \`bat ${SAVE_PATH}\` or \`rg <pattern> ${SAVE_PATH}\`

=== first ${HEAD_LINES} lines ===
${HEAD}

=== ... (truncated $((TOTAL_LINES - HEAD_LINES - TAIL_LINES)) lines) ...

=== last ${TAIL_LINES} lines ===
${TAIL}
TXT
)

# Replace .tool_response.output with the summary
jq --arg out "$REPLACEMENT" '.tool_response.output = $out' <<<"$INPUT"
