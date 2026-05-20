#!/bin/bash
# Generate per-member mobile SSH supplement (filled-in from docs/mobile-ssh-guide.md)
#
# Welcome kit は既に配布済のため、追加情報として「スマホ SSH 手順 (個別値入り)」を
# 別ファイル dist/<slug>/mobile-ssh.md として生成。Slack / 1Password から共有する。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT/dist"
MEMBERS_FILE="$ROOT/members.yml"
TEMPLATE="$ROOT/docs/mobile-ssh-guide.md"

mkdir -p "$DIST_DIR"

python3 - "$ROOT" > /tmp/codens-members-mobile.txt <<'PY'
import sys, yaml, pathlib
root = pathlib.Path(sys.argv[1])
data = yaml.safe_load((root / "members.yml").read_text())
common = data["common"]
warp_prefix = common.get("warp_network_prefix", "")
for slug, m in data["members"].items():
    if m.get("lifecycle_state") != "active":
        continue
    vps_id = m.get("vps_id", "")
    warp_ip = f"{warp_prefix}.{vps_id}" if warp_prefix and vps_id else ""
    print(f'{slug}|{warp_ip}')
PY

while IFS='|' read -r slug warp_ip; do
  out_dir="$DIST_DIR/$slug"
  mkdir -p "$out_dir"
  out_file="$out_dir/mobile-ssh.md"

  # sed で placeholder を置換
  sed -e "s|{{SLUG}}|$slug|g" \
      -e "s|{{WARP_IP}}|$warp_ip|g" \
    "$TEMPLATE" > "$out_file"
  chmod 600 "$out_file"
  echo "[done] $slug → $out_file (warp_ip=$warp_ip)"
done < /tmp/codens-members-mobile.txt

rm -f /tmp/codens-members-mobile.txt

echo
echo "===== Summary ====="
echo "Mobile SSH supplements: $DIST_DIR/<slug>/mobile-ssh.md"
echo "Next: Slack DM で各メンバーに配布 (or 1Password の既存 item に追加)"
