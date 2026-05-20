#!/usr/bin/env bash
# verify-write.sh: PostToolUse hook for Write / Edit / MultiEdit / NotebookEdit.
#
# Catches Qwen / model hallucinations where the model claims a file was created
# but the tool actually didn't persist anything (silently rejected, wrong path,
# permission denied, etc.). After every Write-family tool call, check the
# expected file_path is present on disk; if not, exit 2 with stderr feedback so
# Claude Code surfaces the warning to the model on the next turn.
#
# Inputs (via stdin, JSON):
#   {
#     "session_id": "...",
#     "tool_name": "Write" | "Edit" | "MultiEdit" | "NotebookEdit",
#     "tool_input": {"file_path": "...", ...},
#     "tool_response": {...}
#   }
#
# Behaviour:
#   - exit 0 (silent): file_path exists OR no file_path field present.
#   - exit 2 (block + feed back): file_path was specified but file is missing.
#
# False-positive guard: only trigger on Write/Edit/MultiEdit/NotebookEdit. Other
# tools may set file_path with different semantics (e.g. Read on a non-existent
# file).
set -u

# Need jq; bail silently if unavailable rather than blocking the whole tool.
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
case "$tool_name" in
  Write|Edit|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
[ -z "$file_path" ] && exit 0

# Resolve to absolute (avoids cwd-drift edge cases when the hook runs in a
# subshell). If file_path is already absolute, realpath is a no-op.
abs_path="$file_path"
case "$abs_path" in
  /*) ;;
  *)  abs_path="$(pwd)/$file_path" ;;
esac

if [ -f "$abs_path" ]; then
  exit 0
fi

# File missing — feed back to Claude.
{
  echo "POST-WRITE VERIFY FAILED: After ${tool_name} to '${file_path}', the file does NOT exist on disk."
  echo "Possible causes:"
  echo "  - Path was wrong (off-cwd absolute path that doesn't resolve)"
  echo "  - Tool silently rejected the operation (permission, hooks, etc.)"
  echo "  - You hallucinated success without running the tool"
  echo "Run: pwd && ls $(dirname "$file_path" 2>/dev/null || echo .)"
  echo "Then retry ${tool_name} with the corrected relative path."
  echo "Do NOT claim '${file_path}' was created in your turn summary unless this verify passes."
} >&2
exit 2
