# qwen-llmgw — Self-hosted Qwen Gateway (config 一式の正本)

`roles/claude-config` の claude-qwen / pre-warm / escalate が指す **Qwen LLM ゲートウェイ**の
サーバー側構成・スケジューラの正本。元はこのディレクトリに置かれていたが一度紛失し、
**2026-06-03 に稼働 RunPod ポッドから実機回収して復元**した(経緯は下記)。

## アーキテクチャ（現世代）

```
member VPS / laptop  ──claude-qwen (ANTHROPIC_BASE_URL=qwen-gw.corevice-vps.com,
                       x-api-key=qwen_vps_keys[owner])──►
  Cloudflare  qwen-gw.corevice-vps.com  ──tunnel b2910379──►  RunPod pod :4000
     nginx (bearer→owner auth map, /v1/messages を素通しプロキシ)  ──►  :8000 vLLM
        Qwen/Qwen3.6-27B-FP8  (FP8, ctx 262144, MTP spec decode, RTX PRO 6000 Blackwell)
```

> 注: `roles/claude-config/files/claude-home/README-llmgw.md` の「CCR / L40S / 131K」は
> **旧世代**の記述。現世代は **nginx router / RTX PRO 6000 / 256K / MTP** に更新済み(本 PR)。

## 中身

| パス | 役割 |
|---|---|
| `restore/start-vllm.sh` | vLLM 起動(実機ログから回収した正確な引数: qwen3_xml / mtp:3 / gpu0.94 / mamba float16 / ctx262144 / host127.0.0.1)|
| `restore/nginx-qwen.conf` | :4000 の bearer→owner auth map + `/v1/messages` プロキシ。**本番は `group_vars/vps/qwen-keys.yml`(vault)の `qwen_vps_keys` から map を生成**すること(本ファイルの token はプレースホルダ)|
| `restore/start-cf.sh` | cloudflared(tunnel b2910379)起動 |
| `restore/bootstrap.sh` | 冪等起動: vLLM 未導入なら pip install→モデルDL→vLLM/nginx/cloudflared を setsid 起動 |
| `restore/post_start.sh` | RunPod entrypoint フック(reboot 自己修復)|
| `scheduler/qwen-pod-scheduler.sh` | 平日 9-21 JST の **create/terminate** スケジューラ本体 |
| `scheduler/github-workflow.reference.yml` | GH Actions 定義の**参照コピー**(下記)|

## スケジューラ（create/terminate 方式）

希少 GPU(RTX PRO 6000 Blackwell)は **stop/start だと host 固定で再起動失敗**するため
(2026-06-03 に発生)、**毎朝 create / 夜 terminate** に変更:
- `up`: RTX PRO 6000 系統(≥90GB)を動的列挙し SECURE→COMMUNITY で空きを探して**新規作成** → restore 配置 → bootstrap
- `down`: 名前 `qwen-gateway` の pod を terminate

⚠️ **現在この GH Actions は `Corevice/codens-main` リポジトリで稼働中**(secrets も同リポジトリ:
`RUNPOD_API_KEY` / `QWEN_POD_SSH_KEY` / `CF_TUNNEL_TOKEN`)。`github-workflow.reference.yml` は
その参照コピー。**team-vps-ansible 側で `.github/workflows/` に置くと二重起動するので置かない**こと
(運用を本 repo へ移すなら codens-main 側を無効化してから)。

## 紛失と復元の経緯（2026-06-03）

- このディレクトリ(`plans/qwen-llmgw/`)の正本が消失し、稼働ポッドの起動コマンド・nginx・cloudflared も
  手動起動だったため記録が無かった
- SSH 鍵も紛失 → RunPod env の `PUBLIC_KEY` に手持ち鍵を追加して recreate → SSH で `/workspace/logs`
  を回収し、vLLM 起動引数・nginx ログ形式・cloudflared ingress を確定して復元
- 旧 pod は GPU 容量枯渇で start 不能になり、新 pod を作成して移行(create/terminate 方式へ)
- 詳細な回収ログ: `codens-main:gtm/infra/qwen-vllm/recovered/`

## 未復元 / 要対応

- **token→owner マップ**は `group_vars/vps/qwen-keys.yml`(vault)が正。回収時は gabri のみ既知で
  復元し他は shared-fallback。vault から nginx map を再生成して owner 計上を完全復元すること
- モデル(~29GB)を毎朝再DL する(terminate で volume 破棄のため)。RunPod network volume 常設で回避可
