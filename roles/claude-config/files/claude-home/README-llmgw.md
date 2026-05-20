# Claude Code と Qwen gateway の使い分け (全 VPS 共通)

## 方針: Option 3 (ハイブリッド)

**通常利用はそのまま OAuth / Max plan**。`ANTHROPIC_BASE_URL` は team VPS の shared settings には**入れない**。各ユーザーの Max plan 課金 (定額) を維持する。

Qwen を使いたいときだけ、専用スクリプトで明示的に gateway 経由で呼ぶ。Anthropic API key 従量課金は発生しない構造。

## 通常の claude コマンド (変更なし)

```bash
claude -p "何か作業"              # OAuth で Anthropic 直叩き (Max plan 定額)
claude -p --model sonnet ...      # 同上、モデル指定のみ
```

## Qwen を使いたいとき

```bash
~/.claude/scripts/claude-qwen.sh -p "軽い作業"
```

`.bashrc` / `.zshrc` に以下を入れておくと短く書ける:

```bash
alias claude-qwen="$HOME/.claude/scripts/claude-qwen.sh"
```

使いどころ:

- Anthropic API が障害中 → 冗長系として即時切替
- 大量に雑な処理を流したい (Opus を使うまでもない用途)
- Qwen3.6-27B の性能検証

## 仕組み

`claude-qwen.sh` はサブプロセスの env で以下を一時設定する:

- `ANTHROPIC_BASE_URL=<runpod gateway>`
- `ANTHROPIC_AUTH_TOKEN=<gateway master key>`
- `--model vllm-qwen,Qwen/Qwen3.6-27B-FP8`

**親シェルの `claude` (OAuth) には一切影響しない**。

## Qwen → Claude エスカレーション (`escalate-to-claude` skill)

Qwen3.6-27B が推論能力的に厳しいタスク (複雑な refactor / 深い architecture 分析 /
セキュリティレビュー等) に当たったときに、**子プロセスで upstream Claude を呼ん
で結果を受け取る** スキル。

```bash
# Qwen-backed セッションの中で Claude が判断して呼び出す形:
~/.claude/skills/escalate-to-claude/escalate.sh "Refactor src/auth.ts to ..."

# または stdin で長文プロンプト:
~/.claude/skills/escalate-to-claude/escalate.sh <<'PROMPT'
3 ファイル分のコードを review。worker rotation logic に race 無いか確認...
PROMPT

# モデル選択 (default sonnet):
~/.claude/skills/escalate-to-claude/escalate.sh --model opus "..."
```

**通常の `claude` (OAuth) には影響しない設計:**
- description に「QWEN-BACKED SESSIONS ONLY」「self-recursive になるので通常 claude
  では呼ばない」と明記 → 通常 Claude は LLM 判断で invoke しない
- スクリプトが二重チェック: `ANTHROPIC_BASE_URL` 未設定なら **exit 2 で hard-fail**
  (= 通常 claude セッションで誤って呼ばれても無害に拒否)
- 子プロセスで `env -u ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ...` で gateway 系
  env を全部剥がすので、内側の `claude -p` は OAuth keychain (Max plan) で動く
  → Anthropic API key 従量課金は発生しない

**コスト:** 1 escalation = 1 Claude turn が operator の Max-plan inference budget
を消費。多用すると Qwen 運用の節約効果を相殺するので、3 回/session 超えるなら
そのセッションは普通の `claude` で回すのが正解。

詳細: `~/.claude/skills/escalate-to-claude/SKILL.md`

## gateway 実装詳細

- Pod ID: `qbvnnk0acmjbdk` (RunPod L40S 48GB COMMUNITY)
- モデル: Qwen/Qwen3.6-27B-FP8, 131K context, enforce-eager
- ルーター: claude-code-router (CCR), Anthropic format を受けて vLLM に変換
- 料金: Qwen 常時稼働 ~$570/月。Claude API は **誰も使わなければ $0**
- 変更管理: `plans/qwen-llmgw/` に config 一式

## なぜ shared settings.json に入れないか

`ANTHROPIC_BASE_URL` を全 VPS のデフォルトに設定すると、通常の `claude` コマンドも gateway 経由 → Anthropic API key (従量) に流れ、Max plan の定額課金が無効化される。21 VPS 分の usage が API 従量に化けるため、**月数千ドル** のコスト膨張リスクあり。よって明示呼び出し時のみに限定する。

## トラブルシュート

- `claude-qwen` が 401 → gateway の API KEY がローテされた可能性。ops に連絡
- gateway 障害時 → `claude` (素の OAuth) に戻るだけ。影響局所
- Qwen 応答に `<think>...</think>` が混じる → 既知。Phase 2 で filter 実装予定
