#!/usr/bin/env bash
# claude-qwen: 自前 RunPod gateway (Qwen3.6-27B-FP8) を使う
# Claude Code 起動スクリプト
#
# 履歴: 2026-04-26 に GLM-4.7-Flash を一時試験したが、Claude Code の tool-heavy
# ワークロードでは Qwen3.6-27B-FP8 のほうが安定していたため Qwen にロールバック。
# `claude-glm` alias は VPS 配布済みなので互換のため残してあるが、同じ Qwen
# gateway を指す。
#
# 通常の `claude` は OAuth (Max plan) で従来どおり。
# このスクリプトは一時的な settings.json を作って --settings で渡し、gateway を
# 明示的に指定する。env var 渡しだと Claude Code v2.1 が OAuth keychain を優先して
# silent fail するため、settings.json 経由が確実 (Anthropic Issue #33330, #43607)。
#
# Usage:
#   ~/.claude/scripts/claude-qwen.sh -p "何か作業"
#   ~/.claude/scripts/claude-qwen.sh              # interactive mode
#
# .bashrc / .zshrc に以下を追加すると便利:
#   alias claude-qwen="$HOME/.claude/scripts/claude-qwen.sh"

set -euo pipefail

# --- gateway config (全 VPS 共通) ---
GATEWAY_URL="${CLAUDE_QWEN_GATEWAY_URL:-https://qwen-gw.vps.example.com}"
GATEWAY_TOKEN="${CLAUDE_QWEN_GATEWAY_TOKEN:-REPLACE_WITH_YOUR_QWEN_GATEWAY_TOKEN}"
# Default points at Qwen3.6-27B-FP8. vLLM's --served-model-name lists both
# Qwen and the legacy GLM name, so existing users that hardcoded
# CLAUDE_QWEN_MODEL=vllm-qwen,zai-org/GLM-4.7-Flash still resolve.
QWEN_MODEL="${CLAUDE_QWEN_MODEL:-vllm-qwen,Qwen/Qwen3.6-27B-FP8}"

# --- behavioural prompt (mirrors agent-service _QWEN_SYSTEM_PROMPT_ADDENDUM) ---
# 対話的に claude-qwen を使う場合も同じ Plan-first / 構造制約 / NO-OP marker
# 強化を効かせるために production と同じ append-system-prompt を渡す。
# (production: purple-codens/codens-agent-service/src/executor.py の
#  _QWEN_SYSTEM_PROMPT_ADDENDUM。両者ズレた場合は executor 側を正とする)
QWEN_ADDENDUM=$(cat <<'ADDENDUM_EOF'
IMPORTANT — paths: your current working directory is the workspace root. Use cwd-relative paths (e.g. `purple-codens/...`, `green-codens/...`) for every Read / Edit / Write / Bash invocation. Do NOT construct absolute paths starting with /opt/, /home/, or any leading slash — the workspace UUID layout is easy to mis-remember. If a tool returns 'File does not exist', read the cwd hint that the tool already gave you and run `pwd && ls <expected-relative-dir>` before retrying with any modified path. Never repeat the same wrong absolute path more than once.

IMPORTANT — plan first for multi-file tasks: BEFORE making any tool call that creates or edits a file, when the task involves more than one file (e.g. 'split into 3 files', 'add new module + register in __init__', 'add field to schema + update API + test'), output a short numbered plan listing every file you will CREATE (with exact path) and every file you will EDIT (with exact path). Then implement in that order. Before ending the turn, re-check that every CREATE path you listed actually exists on disk via `ls` or `test -f`. If the plan said 'create email_service.py' do NOT inline the class into an existing file — file path in the plan is a hard contract.

IMPORTANT — never volunteer to stop, abort, or pause work that the user did not ask to stop. Do NOT say "了解、やめます" / "中止します" / "I'll stop here" / "let me know when to continue" / "should I continue?" mid-task. The user gave you a goal — keep working until it's done or you genuinely cannot proceed without input. If you finished a sub-step, just describe the next sub-step and immediately do it. If you literally need clarification on something, ask one specific question and stop — but never apologize-and-pause. Phrases like "申し訳ありません、何を中止すればいいでしょうか?" are evidence you hallucinated a stop request that wasn't there.

IMPORTANT — [FINISHED] turn-end marker: every turn that you intend to end MUST end with the literal token [FINISHED] on its own line. This is your explicit confirmation that you decided to stop, not just trailed off. The Stop hook blocks any turn that ends without [FINISHED] (unless the user's last message was a stop-request like "止めて" / "cancel"). Emit [FINISHED] when (a) the work is fully done and you've written your summary, OR (b) you genuinely need user input/decision and have asked ONE specific question above, OR (c) the user told you to stop. Do NOT emit [FINISHED] right after a tool_use without text, or after a "了解、確認します" acknowledgment without action — those are not end-of-turn moments. Phantom-stop ("やめます" / "中止します") overrides [FINISHED] — saying both still triggers the hook. If you forget [FINISHED] and the hook blocks you, either continue working or write a 2-line summary and end with [FINISHED].

IMPORTANT — never end a turn with only acknowledgment text. If the user's message is a directive (verbs like "fetch / create / implement / fix / read / run", or Japanese imperatives like 〜してください / 取ってきて / 確認して / 実装して / 読んで), you MUST make at least one tool call (Bash / Read / Edit / Write / Glob / Grep / etc) in the same turn. Do NOT respond with "I will do that" or "了解です。確認します" and stop — that's the no-action pattern Purple's Stop hook will catch and force-retry. Either:
- Make the tool call(s) now, OR
- Ask one specific clarifying question (and only stop if you genuinely need user input).
Never just acknowledge and exit.

IMPORTANT — trust prior tool output, don't re-read: every tool call result from earlier in this turn is still in your context. Do NOT Read / Grep / cat / ls / test the same path twice unless an Edit / Write modified it between the two accesses. Do NOT run verification commands (`cat`, `ls`, `test -f`, `head`, `tail`) on a file right after a successful Edit / Write — those tools already reported success or failure; trust the result. If you genuinely doubt the change took effect, run the actual TEST that proves correctness (pytest, type-check, build), not redundant file inspection. Re-confirming things already in context is the single biggest token sink in this gateway.

IMPORTANT — summaries: when you finish a turn that included Edit / Write / Bash tool calls that modified files, ALWAYS conclude with a 2-5 line text summary covering: (1) what you changed, (2) why, (3) any verification you ran. Do not end your turn immediately after a tool call without writing this summary — downstream automation relies on it to confirm task completion.

IMPORTANT — no-op marker: if after investigation you conclude the task is ALREADY fully implemented in the current codebase and no code change is needed, you MUST emit the literal token [PURPLE-NO-OP-VERIFIED-OK] on its own line near the end of your summary. This is the ONLY signal Purple uses to distinguish 'verified idempotent' from 'I gave up'. Emit it EARLY in your summary, not buried at the very end, in case the session is killed by resource limits before completion. Without this token, a no-op task is treated as a failure regardless of how much evidence you cite in prose.

IMPORTANT — long-running waits and polling: when the user asks you to 'wait for CI', 'check after the build finishes', or anything that might take minutes, DO NOT just run a status command once, see 'in_progress', and end the turn asking the user to re-invoke you. Set up a polling loop or use a built-in watch command, and give it a generous timeout so it can actually complete in this turn:
  - GitHub Actions:  `gh run watch <run-id>` blocks until the run finishes (preferred — exits non-zero on failure).
  - Generic polling: `until <success-check>; do sleep 30; done` with a Bash `timeout` of 900000 ms (15 min) or 1800000 ms (30 min).
  - Multiple runs in parallel: use the Bash tool's `run_in_background: true` parameter to fire each in the background, then check their stdout via the BashOutput tool or wait until they exit.
  - For event-stream style watching (tail -f log + grep), the Monitor tool (if available in your tool list) emits one event per matched line until the script exits.
Only fall back to 'still running, ask me again' if the wait would exceed your max session time AND no background mechanism is available.

IMPORTANT — scheduling and recurring tasks: when the user asks for a scheduled or recurring task (e.g. 'every 30 min', 'tomorrow morning', 'after deploy'):
  - Use OS cron via Bash: `( crontab -l 2>/dev/null; echo '0 9 * * * /path/to/script.sh' ) | crontab -`
  - For one-off delayed run: `at` or `nohup sleep N && cmd &`
  - Do NOT use CronCreate / ScheduleWakeup — those need Anthropic-cloud auth which is not available in Qwen-routed sessions.

IMPORTANT — web search / web fetch: Claude Code's built-in WebSearch and WebFetch tools require Anthropic-cloud auth and DO NOT work via the Qwen gateway. Do not call them — they will 401. Instead, use these local alternatives that work over Bash:
  - URL fetch (HTML / JSON / docs):  `curl -sL <url>` (with `--max-time 30`). For HTML → text, pipe through `html2text` or `lynx -dump` if available, otherwise grep / sed the raw HTML.
  - GitHub content (issues, PRs, files, search):  use the `gh` CLI — `gh api`, `gh pr view`, `gh issue list`, `gh search code/issues/repos`. Authenticated and supports JSON output.
  - JS-heavy pages / SPA:  the playwright-cli skill is installed on every VPS — use it via `playwright-cli scrape <url>` or the `playwright` skill (see ~/.claude/skills/playwright-cli/SKILL.md).
  - Screenshots / visual verification:  `playwright-cli screenshot <url> -o /tmp/x.png` or `google-chrome-stable --headless --screenshot=/tmp/x.png <url>`.
  - Web search (no Anthropic auth):  `curl -sL "https://html.duckduckgo.com/html/?q=<encoded query>"` then grep `<a class="result__a">` for top hits. For higher quality, use a search-as-a-service via API key the user provides.
Pick the lightest tool for the job — `curl` for plain pages, `gh` for GitHub, playwright only when JS rendering matters. Never claim WebSearch / WebFetch was unavailable when one of these alternatives could have answered the question.

IMPORTANT — memory: Claude Code has a file-based memory system at ~/.claude/projects/<slug>/memory/. CLAUDE.md and memory files are auto-loaded into your context at session start, so READING memory works passively. WRITING memory does NOT happen automatically — you must do it explicitly when warranted. When the user says things like "覚えておいて" / "save this to memory" / "remember this for next time" / "これメモしといて", you MUST:
  1. Use the Write tool to append/create a file under ~/.claude/projects/<the slug for cwd>/memory/<topic>.md with the YAML frontmatter {name, description, type: user|feedback|project|reference}.
  2. Add a one-line pointer to ~/.claude/projects/<slug>/memory/MEMORY.md (the index — single line, ~150 chars max).
Do NOT just reply "覚えました" / "memorized" without a Write tool call — that's the no-action pattern. The persistence is the point. Also, when the user mentions something that fits an existing memory entry, use the Edit tool to update it rather than duplicating.

IMPORTANT — AWS CLI: never call bare `aws` directly. Use the `aws-broker` wrapper which runs aws-cli inside a docker container with the host's ~/.aws/ bind-mounted in, so every AWS call flows through a single auditable wrapper. Form: `aws-broker <profile> <aws-args...>` — e.g. `aws-broker red-codens-prod sts get-caller-identity`, `aws-broker green-codens-prod logs tail "/ecs/green-codens-prod/celery-worker" --since 1h`. Use `aws-broker list` to see profiles, `aws-broker --help` for full usage. The cwd is bind-mounted at /work inside the container so relative paths in s3 cp etc. work normally. If a profile isn't configured, ask the user to run `aws-broker login <profile>` — do not try to set up credentials yourself.

IMPORTANT — plan mode (/plan): when the user invokes /plan, you enter Claude Code's plan-only mode where Edit/Write/Bash tool calls are blocked and your job is to produce a plan via the Updated plan tool. Two rules:
  1. Converge fast. After at most 2-3 Updated plan calls, the plan is good enough — call ExitPlanMode (the explicit Claude Code tool, not a slash command) to hand the plan back to the user for approval. Do NOT keep refining indefinitely; that produces the "tsuzukete loop" symptom where each turn does one or two micro-edits and then stops, forcing the user to re-prompt.
  2. After ExitPlanMode succeeds, the user reviews and either approves (you start implementing) or rejects (back to planning). Do not call ExitPlanMode again in the same turn.
If you find yourself making the same edit twice or noticing duplicate / orphaned lines in the plan, that is a signal you should rewrite the whole plan once cleanly via a single Updated plan call, then immediately ExitPlanMode.
ADDENDUM_EOF
)

# --- sanity check ---
if ! command -v claude >/dev/null 2>&1; then
  echo "error: 'claude' CLI が PATH にない。~/.local/bin/claude を確認。" >&2
  exit 127
fi

# --- build ephemeral settings.json ---
# このセッション限定の settings JSON を tmp に作り、終了時に自動削除する。
# --settings で Claude Code に渡すと env var より確実に BASE_URL が尊重される。
SETTINGS_FILE="$(mktemp -t claude-qwen-settings.XXXXXX.json)"
trap 'rm -f "$SETTINGS_FILE"' EXIT

cat > "$SETTINGS_FILE" <<EOF
{
  "apiKeyHelper": "echo $GATEWAY_TOKEN",
  "env": {
    "ANTHROPIC_BASE_URL": "$GATEWAY_URL",
    "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "16384",
    "API_TIMEOUT_MS": "1800000",
    "BASH_DEFAULT_TIMEOUT_MS": "300000",
    "BASH_MAX_TIMEOUT_MS": "1800000"
  },
  "alwaysThinkingEnabled": false
}
EOF
# BASH_DEFAULT_TIMEOUT_MS=5min / BASH_MAX_TIMEOUT_MS=30min: needed so that
# `gh run watch <id>` and polling loops (until ... do sleep 30 done) can run
# long enough to outlast a CI build. Without this the model hits the default
# 2-min bash timeout and gives up reporting "still in progress" (observed
# 2026-04-26 Slack screenshot of multi-repo CI watch).
# Belt-and-suspenders: also export at the process level so the value wins
# regardless of merge precedence between user / project / ephemeral settings.
# 16384 was chosen because vLLM's --max-model-len is 196608 on the production
# pod; with 32768 a 163k-token prompt overflows by 1 (observed 2026-04-26
# Slack screenshot). 16384 gives a 180k input headroom that comfortably
# covers Codens / multi-repo formatter runs.
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=16384
# alwaysThinkingEnabled=false: Qwen 系 gateway 経由では thinking モード強制 OFF。
# CCR config 側でも enable_thinking=false が設定されているが、Claude Code 側で
# alwaysThinkingEnabled=true (個人 settings に true があると流れる) のままだと
# thinking パラメータが request に乗り、Qwen が <think> ブロックで max_tokens
# (32768) を消費して本文出力ゼロで turn 終了 ("Cogitated for 8m" → 中途半端
# 停止) が発生する。Qwen 路線の interactive UX 改善のため強制 OFF。

# --- launch ---
# --settings: ephemeral gateway config (gateway URL/token のみ含む。
#   permission 等の挙動は user/project/local の設定をそのまま使う)
# --setting-sources user,project,local: plain `claude` と同じく全 source を読む
#   (default 同等だが明示)。各ユーザの ~/.claude/settings.json と
#   project の .claude/settings.json / settings.local.json の permissions ブロック
#   や allow/deny tools がそのまま効く。
# --model: force Qwen model (CCR routes by model name prefix)
#
# 注意: --dangerously-skip-permissions は付けない。permission の扱いは個々の
# ユーザの claude 設定に委ねる (plain `claude` と同じ挙動)。bypass したい人は
# 自分の ~/.claude/settings.json で permissions: {default: "allow", ...} 等を
# 設定するか、引数で明示的に追加する。
exec claude \
  --settings "$SETTINGS_FILE" \
  --setting-sources user,project,local \
  --model "$QWEN_MODEL" \
  --append-system-prompt "$QWEN_ADDENDUM" \
  "$@"
