#!/bin/bash
# Secret-scan hook for Claude Code (PreToolUse on Write/Edit/MultiEdit/NotebookEdit)
# Reads tool_input JSON from stdin, scans `content` / `new_string` for credential patterns.
# Exit 0 = allow, exit 2 = block (Claude Code aborts the tool call and shows reason).

set -u
INPUT=$(cat)

# Extract content fields the hook should scan.
PAYLOAD=$(jq -r '
  [
    (.tool_input.content // empty),
    (.tool_input.new_string // empty),
    (.tool_input.command // empty),
    ([(.tool_input.edits // [])[].new_string // empty] | join("\n"))
  ] | join("\n")
' <<<"$INPUT" 2>/dev/null)

[ -z "$PAYLOAD" ] && exit 0

# Allowlist: when these markers are present, we trust the user knows what they're doing.
if grep -qE '(SECRET_SCAN_ALLOW|EXAMPLE_KEY_INTENTIONAL)' <<<"$PAYLOAD"; then
  exit 0
fi

# Pattern set — focused, low FP rate.
# Format: <name>|<regex>
PATTERNS=$(cat <<'EOF'
AWS_AccessKeyId|AKIA[0-9A-Z]{16}
AWS_SecretAccessKey|aws_secret_access_key\s*=\s*['\"]?[A-Za-z0-9/+=]{40}['\"]?
GCP_ServiceAccount|"private_key": "-----BEGIN PRIVATE KEY-----
SSH_PrivateKey|-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----
PGP_PrivateKey|-----BEGIN PGP PRIVATE KEY BLOCK-----
GitHub_FineGrainedPAT|github_pat_[0-9a-zA-Z_]{82}
GitHub_ClassicPAT|ghp_[A-Za-z0-9]{36}
GitHub_OAuth|gho_[A-Za-z0-9]{36}
GitHub_AppToken|(ghu|ghs)_[A-Za-z0-9]{36}
Slack_BotToken|xoxb-[0-9]{10,}-[0-9]{10,}-[A-Za-z0-9]{20,}
Slack_UserToken|xoxp-[0-9]{10,}-[0-9]{10,}-[0-9]{10,}-[A-Za-z0-9]{32,}
Slack_AppToken|xapp-1-[A-Z0-9]{11}-[0-9]{12,}-[a-f0-9]{32,}
Cloudflare_APIToken|cfat_[A-Za-z0-9]{40,}
Cloudflare_APIKey|cf_api_key\s*=\s*['\"]?[a-f0-9]{37}['\"]?
Anthropic_APIKey|sk-ant-[A-Za-z0-9_-]{20,}
OpenAI_APIKey|sk-(proj-)?[A-Za-z0-9_-]{40,}
Stripe_SecretKey|sk_(live|test)_[A-Za-z0-9]{24,}
Notion_IntegrationToken|ntn_[A-Za-z0-9]{40,}
Contabo_OAuthClient|INT-[0-9]{8}.*(?:client_secret|password)
GenericBearerToken|Bearer\s+[A-Za-z0-9._=+/-]{40,}
EOF
)

HITS=""
while IFS='|' read -r name pattern; do
  [ -z "$name" ] && continue
  # `grep -E -- "$pattern"` で leading `-` を flag 解釈させない
  if echo "$PAYLOAD" | grep -qE -- "$pattern" 2>/dev/null; then
    HITS="$HITS\n  - $name"
  fi
done <<<"$PATTERNS"

if [ -n "$HITS" ]; then
  cat >&2 <<MSG
🛑 secret-scan hook BLOCKED this write.

Detected potential credential patterns:$(echo -e "$HITS")

Common fixes:
  • Move the secret to ~/.envrc / 1Password / vault, reference via env var
  • Use placeholder (REPLACE_ME, AKIA_EXAMPLE) and load actual value at runtime
  • If genuinely an example/test value, mark with 'SECRET_SCAN_ALLOW' comment

If false positive, escalate to ops — do NOT silently bypass.
MSG
  exit 2
fi

exit 0
