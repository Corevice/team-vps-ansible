#!/bin/bash
# Generate per-member welcome kit (private key + ssh config + README)
#
# Output: dist/<slug>/{ssh-key, ssh-config-snippet, README.md}
# 各 dir をまとめて 1Password に upload + メンバーに share
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEYS_DIR="$ROOT/keys"
DIST_DIR="$ROOT/dist"
MEMBERS_FILE="$ROOT/members.yml"

mkdir -p "$DIST_DIR"
chmod 700 "$DIST_DIR"

# members.yml から (slug, owner_email, display_name, domain, warp_ip, warp_team, language) を取り出す
# heredoc 内に $ROOT を展開するため一重引用符ではなく無印 heredoc を使う
python3 - "$ROOT" > /tmp/codens-members-list.txt <<'PY'
import sys, yaml, pathlib
root = pathlib.Path(sys.argv[1])
data = yaml.safe_load((root / "members.yml").read_text())
common = data["common"]
domain = common["domain"]
warp_prefix = common.get("warp_network_prefix", "")
warp_team = common.get("warp_team_domain", "")
for slug, m in data["members"].items():
    if m.get("lifecycle_state") != "active":
        continue
    vps_id = m.get("vps_id", "")
    warp_ip = f"{warp_prefix}.{vps_id}" if warp_prefix and vps_id else ""
    language = m.get("language", "en")
    print(f'{slug}|{m["owner_email"]}|{m["display_name"]}|{domain}|{warp_ip}|{warp_team}|{language}')
PY

while IFS='|' read -r slug email display_name domain warp_ip warp_team language; do
  priv="$KEYS_DIR/$slug"
  pub="$KEYS_DIR/$slug.pub"

  if [ ! -f "$priv" ]; then
    echo "[warn] $slug — private key missing ($priv), run generate-member-keys.sh first"
    continue
  fi

  member_dist="$DIST_DIR/$slug"
  mkdir -p "$member_dist"
  chmod 700 "$member_dist"

  # 1. private key (ファイル名は member 側で扱いやすい名前に)
  cp "$priv" "$member_dist/codens-vps-$slug"
  cp "$pub"  "$member_dist/codens-vps-$slug.pub"
  chmod 600 "$member_dist/codens-vps-$slug"

  # 2. ssh config snippet (member の ~/.ssh/config に貼り付ける)
  cat > "$member_dist/ssh-config-snippet" <<EOF
# === Append to ~/.ssh/config ===
Host codens-vps
  HostName ssh-$slug.$domain
  User $slug
  IdentityFile ~/.ssh/codens-vps-$slug
  IdentitiesOnly yes
  ProxyCommand /usr/local/bin/cloudflared access ssh --hostname %h
  ServerAliveInterval 60
EOF

  # 3. README (member guide). language=ja の場合は日本語版を出力
  if [ "$language" = "ja" ]; then
    cat > "$member_dist/README.md" <<EOF
# Codens VPS Welcome Kit — $display_name

$display_name さん、ようこそ。このキットには、あなた専用の Ubuntu 24.04
開発 VPS にアクセスするための情報がまとめてあります。

- **ブラウザ (VS Code):** https://vps-$slug.$domain
- **ターミナル (SSH):** \`ssh codens-vps\` (下記セットアップ後)
- **ログイン用 email:** \`$email\`

## 初回セットアップ (約 5 分)

### 1. cloudflared をインストール (SSH に必須)

SSH は Cloudflare Tunnel 経由で繋がるため \`cloudflared\` CLI が必要です。

\`\`\`bash
# macOS
brew install cloudflare/cloudflare/cloudflared

# Linux (Debian/Ubuntu)
sudo curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \\
  -o /usr/local/bin/cloudflared && sudo chmod +x /usr/local/bin/cloudflared

# Windows
# https://github.com/cloudflare/cloudflared/releases から .exe を取得し PATH に追加
\`\`\`

### 2. SSH 秘密鍵を配置

このキット内の \`codens-vps-$slug\` を \`~/.ssh/\` にコピー
(パーミッションは **必ず 0600**):

\`\`\`bash
mkdir -p ~/.ssh
cp codens-vps-$slug ~/.ssh/
chmod 600 ~/.ssh/codens-vps-$slug
\`\`\`

### 3. SSH config を追加

同梱の \`ssh-config-snippet\` を \`~/.ssh/config\` に追記:

\`\`\`bash
cat ssh-config-snippet >> ~/.ssh/config
\`\`\`

### 4. 初回 SSH 接続

\`\`\`bash
ssh codens-vps
\`\`\`

初回はブラウザが自動で開き、Cloudflare Access のログイン画面が表示されます:

1. email を入力: \`$email\`
2. **Send me a code** をクリック
3. 受信箱に届く 6 桁の PIN を確認 (数秒以内に届きます)
4. ブラウザで PIN を入力

認証後、SSH セッションが繋がります。Cloudflare のセッションは 24 時間有効、
失効後は再度 PIN を入力するだけで OK です。

## ブラウザ版 VS Code (code-server)

任意のブラウザで:

**https://vps-$slug.$domain**

同じ Cloudflare Access フロー (email → PIN) で VS Code が開きます。
拡張機能のインストール、統合ターミナル、デバッグなど通常の VS Code が
そのまま使えます。Cloudflare の 24 時間セッションはブラウザと SSH 共通です。

## スマホからの接続 (iPhone / Android) — 任意

PC を経由せずに、スマホ・タブレットの SSH クライアント (Termius / Blink /
JuiceSSH 等) から VPS に直接 SSH したい場合は **Cloudflare WARP** を入れます。
バックグラウンドで動いて SSH トラフィックを VPS まで通してくれます。

### 1. Cloudflare One Agent をインストール

- iOS: **Cloudflare One Agent** (App Store)
- Android: **Cloudflare One Agent** (Play Store):
  https://play.google.com/store/apps/details?id=com.cloudflare.cloudflareoneagent

> ⚠️ 通常の **\`1.1.1.1\` / WARP** アプリではなく、必ず **Cloudflare One Agent**
> を使ってください。1.1.1.1 アプリだと Android 端末で Zero Trust の sign-in
> error が出ます。Cloudflare One Agent はチーム向けの公式版で、当環境では
> こちらが安定動作します。

### 2. Codens チームに enroll

1. **Cloudflare One Agent** を起動
2. **Team name** を聞かれたら: \`$warp_team\` を入力
3. ブラウザが開く → email 入力: \`$email\` →
   **One-time PIN** を選択 → 受信箱の 6 桁 PIN を入力
4. アプリに戻ってプライバシー通知の **Accept** をタップ
5. アプリ上でチーム名 \`$warp_team\` / connected 状態が表示されれば OK

> 注意: Cloudflare One Agent 上で **WARP / Gateway の status が OFF** に
> 見えることがありますが、これは当環境では **正常動作**です。Zero Trust の
> private network access は WARP / Gateway トグルとは独立で、\`$warp_team\`
> チームに sign-in できていれば \`$warp_ip\` に到達できます。

### 3. ターミナルアプリで接続

ターミナルアプリで新しい SSH ホストを追加:

- **Host:** \`$warp_ip\`
- **Port:** \`22\`
- **Username:** \`$slug\`
- **秘密鍵:** \`codens-vps-$slug\` (本キット内)

保存して接続。WARP が ON ならそのまま繋がります — ブラウザ・PIN 不要。

### 4. 長時間ジョブを切らないコツ

\`tmux\` (インストール済) を使うと、ネットワーク切断や Wi-Fi → モバイル
切替後でも作業を継続できます:

\`\`\`bash
# 初回ログイン
tmux new -s main

# 切断後、再接続して再開
tmux attach -t main
\`\`\`

ネットワーク切替の追従をさらに滑らかにしたい場合は **mosh**
(これもインストール済) が便利です。Termius / Blink Shell ともに対応で、
接続種別を "Mosh" に切り替えて同じ host / 鍵を指定するだけです。

## インストール済ツール

- **Docker** / \`docker compose\`
- **mise** (runtime manager): Node.js LTS、Python 3.12、Go
- **Claude Code** (\`claude\` コマンド。\`claude --help\` で確認)
- **gh** (GitHub CLI)
- **git, tmux, zsh, ripgrep (\`rg\`), fd, bat, eza, jq, direnv, htop, btop**

## VPS で動かしたサービスにローカル PC から接続する

Codens VPS は外部から直接 port を叩けない設計になっています。Cloud Firewall
が perimeter で全 port (22 以外) を deny してるのに加え、Docker daemon も
**コンテナ port を \`127.0.0.1\` のみにバインド**するよう設定済 (二重防御)。

そのため \`docker run -p 3000:3000\` で起動したサービスを laptop の
ブラウザから叩きたい場合は、以下のいずれかの方法で繋いでください。

### 方法 1: SSH local port forward (ターミナル派)

VPS 側でサービスを起動:

\`\`\`bash
ssh codens-vps
docker run -p 3000:3000 my-app    # → VPS 内で 127.0.0.1:3000 にバインド
\`\`\`

別タブで laptop からトンネル:

\`\`\`bash
ssh -L 3000:localhost:3000 codens-vps
\`\`\`

→ laptop のブラウザで \`http://localhost:3000\` でアクセスできます。
トンネルは 2 つ目の SSH セッションが開いてる間だけ有効。

ワンライナーも可: \`ssh -L 3000:localhost:3000 codens-vps 'docker run -p 3000:3000 my-app'\`

### 方法 2: VS Code Remote-SSH の自動 port forward

VS Code の Remote-SSH 拡張で VPS に接続していれば、listen 中の port を
VS Code が自動検出し、**Forwarded Ports パネル**から 1-click で laptop に
トンネルを張れます。Docker コンテナでも、ネイティブの dev server でも同じ。

### 方法 3: code-server (ブラウザ版 VS Code) — トンネル不要

\`https://vps-$slug.$domain\` で開いた code-server は VPS 上で動いてるので、
内蔵 terminal でサービスを起動すれば \`localhost:3000\` にそのままアクセス
できます。laptop のブラウザで別タブで開きたい場合は、code-server の
**Forward a Port** 機能で Cloudflare Access 認証付きの URL が払い出されます。

### 方法 4: Termius / Blink (スマホ派) — GUI で port forward

Termius の **Settings → Port Forwarding** で \`Local 3000 → Remote localhost:3000\`
を追加して接続するだけ。\`ssh -L\` の GUI 版です。

### 方法 5: 長期公開 URL が欲しい (Slack webhook 等)

webhook receiver 等で **インターネットから到達可能な URL** が必要な場合は
ops チームに依頼してください。Cloudflare Tunnel に ingress を追加し、
Cloudflare Access 認証越しの URL を払い出します
(あなたの email でしか開けないので "公開" とは違います)。

## sudo (root 権限)

**パスワード無し sudo** が使えます。パッケージ追加・システム設定変更など
自由にどうぞ。ただし以下は**触らないでください** (アクセス不能になる恐れ):

- \`/etc/ssh/sshd_config\` (ロックアウト)
- \`ufw\` ファイアウォールルール
- \`systemctl stop cloudflared\` (アクセス経路が切れる)

これらの変更が必要な場合は ops チームに連絡してください。

## トラブルシューティング

| 症状 | 対処 |
|------|------|
| laptop から \`curl http://<vps-ip>:8080\` が timeout する | 仕様です。Cloud Firewall + Docker の \`127.0.0.1\` bind で外部到達不可。SSH tunnel か code-server 経由でアクセスを |
| \`https://vps-$slug.$domain\` に繋がらない | Slack #ops |
| \`ssh codens-vps\` が timeout する | \`cloudflared access login ssh-$slug.$domain\` を実行して再試行 |
| 認証セッションが切れた | もう一度 SSH すれば PIN プロンプトが再表示される |
| 壊してしまった、初期化したい | Slack #ops (再構築可。先に必要データを退避) |

## セキュリティ

- 秘密鍵 \`codens-vps-$slug\` は **あなた専用**です。
  共有・Git にコミット・Slack にペーストは厳禁。
- グローバルな \`.gitignore\` に \`codens-vps-*\` を追加しておくと安全です。
- 鍵漏えいの疑い、PC 紛失等の場合は **すぐに ops チームに連絡**してください
  (新しい鍵を発行します)。

## 連絡先

- ops@example.com
- Slack DM: #ops
EOF
  else
    cat > "$member_dist/README.md" <<EOF
# Codens VPS Welcome Kit — $display_name

Hi $display_name, welcome! This kit gives you access to your dedicated
development VPS running Ubuntu 24.04 with a full dev environment.

- **Browser (VS Code):** https://vps-$slug.$domain
- **Terminal (SSH):** \`ssh codens-vps\` (after setup below)
- **Your login email:** \`$email\`

## One-time setup (~5 minutes)

### 1. Install cloudflared (required for SSH)

SSH goes through a Cloudflare Tunnel, so you need \`cloudflared\` CLI.

\`\`\`bash
# macOS
brew install cloudflare/cloudflare/cloudflared

# Linux (Debian/Ubuntu)
sudo curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \\
  -o /usr/local/bin/cloudflared && sudo chmod +x /usr/local/bin/cloudflared

# Windows
# Download the .exe from https://github.com/cloudflare/cloudflared/releases
# and add it to your PATH
\`\`\`

### 2. Install your SSH key

Copy the private key \`codens-vps-$slug\` from this kit to \`~/.ssh/\`
(permissions **must** be 0600):

\`\`\`bash
mkdir -p ~/.ssh
cp codens-vps-$slug ~/.ssh/
chmod 600 ~/.ssh/codens-vps-$slug
\`\`\`

### 3. Add SSH config

Append the provided \`ssh-config-snippet\` to \`~/.ssh/config\`:

\`\`\`bash
cat ssh-config-snippet >> ~/.ssh/config
\`\`\`

### 4. First SSH connection

\`\`\`bash
ssh codens-vps
\`\`\`

The first time, a browser window opens with a Cloudflare Access login screen:

1. Enter your email: \`$email\`
2. Click **Send me a code**
3. Check your inbox — a 6-digit PIN arrives within seconds
4. Enter the PIN in the browser

Once authenticated, the SSH session connects. Your Cloudflare session is
valid for 24 hours; after that you'll be prompted for a new PIN.

## Using VS Code in the browser (code-server)

Open in any browser:

**https://vps-$slug.$domain**

Same Cloudflare Access flow: email → PIN → VS Code opens. It's a full
VS Code — you can install Extensions, open the integrated terminal, debug, etc.

Your 24-hour Cloudflare session is shared between browser and SSH.

## Mobile access (iPhone / Android) — optional

If you want to SSH into your VPS from a phone / tablet with a native terminal
app (Termius, Blink, JuiceSSH, etc.), install **Cloudflare WARP**. It runs in
the background and lets your SSH client reach your VPS directly.

### 1. Install Cloudflare One Agent

- iOS: **Cloudflare One Agent** (App Store)
- Android: **Cloudflare One Agent** (Play Store) — link:
  https://play.google.com/store/apps/details?id=com.cloudflare.cloudflareoneagent

> ⚠️ Do **NOT** install the regular **\`1.1.1.1\` / WARP** app. Some Android
> devices get a "sign-in error" when trying to enroll in Zero Trust through
> the 1.1.1.1 app. The dedicated **Cloudflare One Agent** is the team-grade
> app that works reliably for our setup.

### 2. Enroll in the Codens team

1. Open **Cloudflare One Agent**
2. When asked for the **Team name**, enter: \`$warp_team\`
3. A browser window opens → enter your email: \`$email\` →
   choose **One-time PIN** → check your inbox for the 6-digit PIN → enter it
4. Back in the app, tap **Accept** on the privacy notice
5. The app should show your \`$warp_team\` team label / connected state

> Note: Inside Cloudflare One Agent you may see **WARP and Gateway status as OFF**.
> This is **normal for our setup** — Zero Trust private network access works
> independently of those toggles. As long as you are signed in to the
> \`$warp_team\` team, you can reach your VPS at \`$warp_ip\`.

### 3. Connect from a terminal app

Add a new SSH host in your terminal app:

- **Host:** \`$warp_ip\`
- **Port:** \`22\`
- **Username:** \`$slug\`
- **Private key:** \`codens-vps-$slug\` (the one in this kit)

Save and tap connect. If WARP is on, it works — no browser, no PIN dance.

### 4. Keep long-running work alive

Use \`tmux\` (already installed) to survive network drops and switches
between Wi-Fi / mobile / airplane mode:

\`\`\`bash
# first login
tmux new -s main

# later, reconnect and resume
tmux attach -t main
\`\`\`

For even smoother reconnection across network changes, use **mosh** (also
pre-installed). Termius and Blink Shell both support it — switch the
connection type to "Mosh" and use the same host/key.

## What's already installed

- **Docker** / \`docker compose\`
- **mise** (runtime manager) with Node.js LTS, Python 3.12, Go
- **Claude Code** (\`claude\` command; run \`claude --help\`)
- **gh** (GitHub CLI)
- **git, tmux, zsh, ripgrep (\`rg\`), fd, bat, eza, jq, direnv, htop, btop**

## Connecting to a VPS-side service from your laptop

Your VPS does **not** accept direct connections from the public internet.
Three layers block it: the Contabo Cloud Firewall (network perimeter), the
Docker daemon (binds container ports to \`127.0.0.1\` by default), and a
\`DOCKER-USER\` iptables rule (drops any external NIC inbound to containers,
even if a container explicitly binds \`0.0.0.0\` via \`docker compose\`).

To reach a service you're running inside the VPS (a dev server, a Docker
container, a docker-compose stack...) from your laptop, use one of:

### 1. SSH local port forward (terminal)

\`\`\`bash
# laptop terminal #1 — start the service inside the VPS
ssh codens-vps
docker run -p 3000:3000 my-app   # binds to 127.0.0.1:3000 on the VPS

# laptop terminal #2 — open a tunnel to it
ssh -L 3000:localhost:3000 codens-vps
# now in laptop browser: http://localhost:3000
\`\`\`

One-liner: \`ssh -L 3000:localhost:3000 codens-vps 'docker run -p 3000:3000 my-app'\`

### 2. VS Code Remote-SSH — auto-forwarded ports

If you SSH into the VPS via the **Remote-SSH** extension, VS Code detects
listening ports and offers a 1-click forward in the **Forwarded Ports** panel.
Works for Docker, native dev servers, anything that listens.

### 3. code-server (browser VS Code) — no tunnel

Open \`https://vps-$slug.$domain\` and the integrated terminal sees \`localhost\`
the same way you would inside the VPS. To open a port in your laptop's
browser, use code-server's **Forward a Port** feature — it issues a Cloudflare
Access-protected URL.

### 4. Termius / Blink (mobile) — GUI port forward

Termius **Settings → Port Forwarding** → add \`Local 3000 → Remote localhost:3000\`,
then connect. Same as \`ssh -L\` with a UI.

### 5. Long-lived public URL (e.g. webhook receiver)

If you need an internet-reachable URL (Slack webhook, GitHub webhook...),
ask ops to add a Cloudflare Tunnel ingress entry. The URL will sit
behind Cloudflare Access (your email-only) so it's not truly public.

## Root access (sudo)

You have **passwordless sudo** — use freely for installing packages, editing
system files, etc. However, please **do not touch** the following (they
protect your access to the VPS):

- \`/etc/ssh/sshd_config\` (lockout risk)
- \`ufw\` firewall rules
- \`systemctl stop cloudflared\` (breaks your access)

If you need changes in any of these, contact the ops team first.

## Troubleshooting

| Symptom | What to do |
|---------|-----------|
| \`curl http://<vps-ip>:8080\` from my laptop times out | Expected — public ingress is closed by design. Use SSH tunnel or code-server (see "Connecting to a VPS-side service" above). |
| Cannot reach \`https://vps-$slug.$domain\` | Slack #ops |
| \`ssh codens-vps\` fails / times out | Run \`cloudflared access login ssh-$slug.$domain\` then retry |
| Forgot to auth and session expired | Just try again; a new PIN prompt will appear |
| Broke something, want to start fresh | Slack #ops (the VPS can be reinstalled; back up your work first) |

## Security

- The private key file \`codens-vps-$slug\` is **yours and yours alone**.
  Do not share, do not commit to Git, do not paste in Slack.
- Add \`codens-vps-*\` to your global \`.gitignore\`.
- If you suspect the key leaked or you lose your laptop, **tell ops
  immediately** so we can issue a fresh key.

## Contact

- ops@example.com
- Slack DM: #ops
EOF
  fi

  echo "[done] $slug → $member_dist/ (lang=$language)"

done < /tmp/codens-members-list.txt

rm -f /tmp/codens-members-list.txt

echo
echo "===== Summary ====="
echo "Welcome kits in: $DIST_DIR"
echo
echo "Next: 各 dist/<slug>/ ディレクトリを zip 化 → 1Password に upload → メンバーと share"
echo "例:"
echo "  cd dist && for d in */; do zip -r \"\${d%/}.zip\" \"\$d\"; done"
