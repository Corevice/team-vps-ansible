#!/bin/bash
# Generate per-member SSH keypairs for Codens VPS access
#
# Output:
#   keys/<slug>      (private, mode 0600)
#   keys/<slug>.pub  (public)
#
# 各メンバーが既に SSH 鍵を持っているかどうかに依存しない (operator 側で生成して配布)
# 配布手段: 1Password の per-member item に private key を格納してメンバー本人と share

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEYS_DIR="$ROOT/keys"
MEMBERS_FILE="$ROOT/members.yml"

if [ ! -f "$MEMBERS_FILE" ]; then
  echo "FATAL: members.yml not found at $MEMBERS_FILE" >&2
  exit 1
fi

mkdir -p "$KEYS_DIR"
chmod 700 "$KEYS_DIR"

SLUGS=$(python3 -c "
import yaml
with open('$MEMBERS_FILE') as f:
    data = yaml.safe_load(f)
for slug, m in data['members'].items():
    if m.get('lifecycle_state') == 'active':
        print(slug)
")

CREATED=0
SKIPPED=0

for slug in $SLUGS; do
  priv="$KEYS_DIR/$slug"
  pub="$KEYS_DIR/$slug.pub"

  if [ -f "$priv" ] && [ -f "$pub" ]; then
    echo "[skip] $slug — keys already exist (delete to regenerate)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  ssh-keygen -t ed25519 \
    -N "" \
    -C "codens-vps-$slug ($(date -u +%Y-%m-%d))" \
    -f "$priv" \
    -q

  chmod 600 "$priv"
  chmod 644 "$pub"

  echo "[created] $slug — $pub"
  CREATED=$((CREATED + 1))
done

echo
echo "===== Summary ====="
echo "Created: $CREATED, Skipped: $SKIPPED"
echo "Keys directory: $KEYS_DIR"
echo
echo "Next steps:"
echo "  1. python3 scripts/generate-inventory.py  # → host_vars に pubkey を反映"
echo "  2. scripts/generate-welcome-kits.sh        # → 各メンバーに送る kit を作る"
echo "  3. 各 keys/<slug> を 1Password に upload (item 名: 'Codens VPS - <slug>')"
echo "     1Password item を該当メンバーと share"
echo "  4. local の keys/<slug> private key は upload 後に shred で削除推奨"
