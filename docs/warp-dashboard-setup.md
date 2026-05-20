# WARP Zero Trust Dashboard Setup

Terraform と Ansible で実装できない **Zero Trust dashboard 側の手動設定** をここにまとめる。

これは F47 (mobile SSH via WARP) を完全動作させるための最終ステップ。

## 1. WARP Client — Device enrollment policy

**Path:** Cloudflare Zero Trust → Settings → WARP Client → Device enrollment permissions

1. **Add a rule**:
   - Rule name: `codens-team`
   - Action: `Allow`
   - Include:
     - Selector: `Emails ending in`
     - Value: `@example.com`
   - Include (OR):
     - Selector: `Emails ending in`
     - Value: `@corevice.com`
2. **Identity providers**: Google + One-time PIN (既存の Access で設定済のもの)
3. **Session duration**: 24h (既存 Access と揃える)

これで 21 メンバー + operator のみが WARP に enroll 可能になる。

## 2. WARP Client — Device profile (Split Tunnel)

**Path:** Zero Trust → Settings → WARP Client → Device profiles → Default

1. **Split Tunnel mode**: `Include IPs and domains` (必ず Include mode、Exclude mode ではない)
2. **Managed networks**: (空で OK)
3. **Included IPs / domains**:
   - `10.200.0.0/24` (codens VPS 仮想ネットワーク全体)
   - `<team-domain>.cloudflareaccess.com` (認証用、WARP が自動で追加する場合あり)
4. **Excluded IPs**: （空）

Include mode にすると、**Included CIDR のみ WARP 経由**になり、その他はメンバーの通常インターネット接続を使う (Google とか LINE とか)。プライバシー・速度両面でベター。

## 3. Tunnel routes (terraform で作成済)

Zero Trust → Networks → Tunnels → (any tunnel) → Private Network に以下が並んでいれば OK:

```
10.200.0.1/32   → vps-gabri
10.200.0.2/32   → vps-ryan
10.200.0.3/32   → vps-rudi
...
10.200.0.21/32  → vps-yusup
```

21 行なければ `terraform apply` を再実行。

## 4. (Optional) Gateway Network Policy — per-user per-VPS restrict

現状 WARP enroll していれば任意の VPS に SSH 接続「試行」は可能 (但し SSH key が無いので login はできない)。
defense-in-depth で per-user per-VPS 制限をかけたい場合は以下を追加。

**Path:** Zero Trust → Gateway → Firewall Policies → Network

rule 例 (21 個):

- Name: `ssh-gabri-owner-only`
- Expression: `Destination IP in 10.200.0.1/32 AND Destination Port == 22 AND User Email not in ("gabri@example.com")`
- Action: `Block`

*(operator email は全台 bypass したい場合は別途 allow rule を優先 precedence で追加)*

terraform で自動化するには `cloudflare_zero_trust_gateway_policy` resource を使う。未実装。

## 5. メンバー側の案内文 (Slack / 1Password に送るテンプレ)

```
【追加配布】スマホから直接 SSH 接続できるようになりました

PC なし・cloudflared なしでスマホの Termius / Blink から
VPS に常時接続できる設定が完了しました。以下の3分セットアップで有効化:

1. アプリ install
   iOS: Cloudflare One Agent (App Store)
   Android: Cloudflare One Agent (Play Store)
   ※ 1.1.1.1 / WARP アプリではなく "Cloudflare One Agent" が正解

2. チーム enroll
   Settings → Account → Login with Cloudflare Zero Trust
   Team: corevice
   サインイン: <あなたの hamasmart.com email>

3. Termius で VPS 追加
   Host: <あなた専用の 10.200.0.X> ※個別に DM 送ります
   Port: 22
   User: <あなたの slug>
   Key: welcome kit の codens-vps-<slug>

詳細: dist/<slug>/mobile-ssh.md を参照 (1Password に追加しました)
```

## Troubleshooting

| Symptom | Diagnosis |
|---------|-----------|
| メンバーが WARP login で "your team is not authorized" | Device enrollment rule の email 条件を確認 (§1) |
| WARP is On だが 10.200.0.X に繋がらない | Split Tunnel に `10.200.0.0/24` が Include されているか (§2) |
| **One Agent / WARP On でも即 `connection refused`** | **Zero Trust team `corevice` に未 enroll**。Cloudflare One Agent で再 enroll |
| `1.1.1.1` アプリで Android 端末が "sign-in error" で詰まる | アプリが違う。**Cloudflare One Agent** を使うよう案内 |
| Cloudflare One Agent で `WARP` / `Gateway` status が OFF 表示 | **正常動作**。Zero Trust private network access はそれらと独立。team `corevice` に sign-in できていれば疎通する |
| VPS 側の cloudflared が route を認識していない | `cloudflared tunnel route list` で該当 /32 を確認、無ければ `terraform apply` |
| SSH 接続できるが `Permission denied (publickey)` | key file の permission 0600、member slug が正しい user 名か |
