#!/bin/bash
# Weekly Contabo snapshot for all 21 codens VPS
# Runs from ops server (<ops-server-ip>) via cron
#
# Per Contabo plan: typically 1 snapshot slot per VPS (Cloud VPS plans).
# Strategy: delete existing snapshot named codens-weekly, create new one.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="/var/log/codens-snapshot/weekly-$(date +%Y%m%d).log"
ACCOUNTS_FILE="$HOME/.contabo-accounts.yaml"
SNAPSHOT_NAME="codens-weekly"

mkdir -p "$(dirname "$LOG")"

if [ ! -f "$ACCOUNTS_FILE" ]; then
  echo "FATAL: $ACCOUNTS_FILE not found" | tee -a "$LOG"
  exit 1
fi

cd "$ROOT"

# yaml -> json -> jq でループしやすく
python3 - <<EOF > /tmp/snapshot-targets.json
import yaml, json
m = yaml.safe_load(open("members.yml"))
out = []
for slug, mem in m["members"].items():
    if mem.get("lifecycle_state") != "active":
        continue
    out.append({
        "slug": slug,
        "instance_id": mem["contabo_instance_id"],
        "account": mem["contabo_account"],
    })
print(json.dumps(out))
EOF

cntb_creds_for() {
  local account="$1"
  python3 - "$ACCOUNTS_FILE" "$account" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1]))
acc = data["accounts"][sys.argv[2]]
print(f'--oauth2-clientid={acc["client_id"]}')
print(f'--oauth2-client-secret={acc["client_secret"]}')
print(f'--oauth2-user={acc["user"]}')
print(f'--oauth2-password={acc["password"]}')
PY
}

snapshot_one() {
  local slug="$1"
  local instance_id="$2"
  local account="$3"
  local creds
  mapfile -t creds < <(cntb_creds_for "$account")

  echo "[$(date -uIseconds)] vps-$slug ($instance_id @ $account)"

  # 1. delete existing snapshot named codens-weekly (if any)
  local existing
  existing=$(~/.local/bin/cntb get snapshots "$instance_id" "${creds[@]}" --output json 2>/dev/null \
             | jq -r --arg name "$SNAPSHOT_NAME" '.[] | select(.name == $name) | .snapshotId' || true)

  if [ -n "$existing" ]; then
    echo "  deleting existing snapshot $existing"
    ~/.local/bin/cntb delete snapshot "$instance_id" "$existing" "${creds[@]}" 2>&1 | sed 's/^/  /'
    sleep 5
  fi

  # 2. create new snapshot
  echo "  creating snapshot '$SNAPSHOT_NAME'"
  ~/.local/bin/cntb create snapshot "$instance_id" \
    --name "$SNAPSHOT_NAME" \
    --description "Auto weekly snapshot $(date -uIseconds) by $(hostname)" \
    "${creds[@]}" 2>&1 | sed 's/^/  /'
}

# Process all
SUCCESS=0; FAIL=0
while IFS= read -r row; do
  slug=$(jq -r .slug <<< "$row")
  iid=$(jq -r .instance_id <<< "$row")
  acc=$(jq -r .account <<< "$row")

  if snapshot_one "$slug" "$iid" "$acc"; then
    SUCCESS=$((SUCCESS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL: vps-$slug"
  fi
done < <(jq -c '.[]' /tmp/snapshot-targets.json)

echo ""
echo "Summary: $SUCCESS success, $FAIL fail"
rm -f /tmp/snapshot-targets.json
exit $FAIL
