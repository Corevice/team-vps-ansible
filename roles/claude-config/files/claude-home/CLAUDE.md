# Codens VPS — Shared Claude Code Memory

You are running on a **dedicated dev VPS** managed by the Codens team.
This file is global memory shared across all 21 team VPS. Read it carefully.

## Environment

- **OS**: Ubuntu 24.04 LTS, ext4 root filesystem
- **Provider**: Contabo VPS (typically 6 vCPU / 16 GB RAM / 400 GB SSD)
- **Hostname**: `vmiNNNNNNN` (Contabo-assigned, ignore for naming)
- **You are**: the VPS owner (a Linux user matching your slug — e.g. `gabri`)

## Tools already installed (do not reinstall)

| Tool | Where | Notes |
|------|-------|-------|
| `git` / `gh` (GitHub CLI) | system | Run `gh auth login` once if not already authed |
| `docker` / `docker compose` | system | Your user is in `docker` group, no sudo needed |
| `mise` | `~/.local/bin/mise` | Activated in interactive bash/zsh via `.bashrc`/`.zshrc` |
| Node.js LTS, Python 3.12, Go | via `mise` | `mise list` to see versions |
| `claude` (Claude Code CLI) | `~/.local/bin/claude` | This is what you're running in |
| `claude-qwen` / `claude-glm` (aliases) | `~/.claude/scripts/claude-qwen.sh` | Shared self-hosted backend (Qwen3.6-27B-FP8; GLM-4.7-Flash試験 2026-04-26 → Qwen にロールバック)。RunPod H100 NVL, FP8, 192k ctx. Anthropic 課金なし、雑用 or 障害時冗長向け。Both aliases run the same script and resolve to the same gateway. |
| `codex` (OpenAI Codex CLI) | mise node prefix | `@openai/codex` npm package, run `codex auth login` once |
| `playwright-cli` v0.1.8+ | mise node prefix | See `~/.claude/skills/playwright-cli/SKILL.md` |
| Google Chrome (headless) | `/usr/bin/google-chrome-stable` | For playwright-cli + general scraping |
| `rg` (ripgrep), `fd`, `bat`, `eza`, `jq`, `direnv`, `htop`, `btop`, `tmux`, `mosh`, `zsh`, `starship` | system | Modern CLI, prefer over `grep`/`find`/`cat`/`ls`/etc. |

**Token-saving rule**: Don't run `apt install` / `npm install -g` / `pip install` for tools above — they're already there.

## sudo rules

- Passwordless `sudo` is enabled for the owner
- **Do NOT modify**:
  - `/etc/ssh/sshd_config` (lockout risk)
  - `ufw` rules (`ufw allow|deny|...`)
  - `/etc/fstab` (boot risk)
  - `cloudflared` service (`systemctl stop cloudflared` breaks all access)
- If a task requires editing those, **stop and tell the user to ask ops**.

## Network access patterns

- **Inbound**: Only Cloudflare Tunnel (no public ports). External clients reach this VPS via:
  - `https://vps-<owner>.vps.example.com` — HTTPS / code-server (CF Access OTP)
  - `cloudflared access ssh ssh-<owner>.vps.example.com` — SSH via cloudflared on PC
  - `10.200.0.<vps_id>` (port 22) — SSH from Cloudflare **WARP** clients (mobile SSH apps)
- **Outbound**: Unrestricted. `apt`, `npm`, `pip`, `gh`, etc. all work.
- **Cloud Firewall** (Contabo) is managed by ops; don't try to change it from inside the VPS.
- Don't touch `/etc/systemd/system/codens-warp-vip.service` or remove the `10.200.0.*/32` address on `lo` — it's what makes mobile SSH reach this host.

## Disk

- `/home/<owner>` is your workspace (300 GB soft / 350 GB hard quota — enforced)
- Don't fill it. Run `df -h /home` and `du -sh ~/* | sort -h | tail -20` to find big things
- `/tmp` is for ephemeral data — gets cleaned periodically
- `/var/lib/docker` is shared (system-managed) — `docker system prune -af` if disk pressured

## Auth & secrets

- `gh auth login` for GitHub access — use SSH or token, ops recommends SSH
- **Never paste credentials in code** (we have a pre-commit hook scanning for them, but don't rely on it)
- For repository access, prefer GitHub deploy keys or `gh` over personal tokens
- API keys for external services (OpenAI, Anthropic, etc.) — use `direnv` (`.envrc`) per project, never commit

### AWS CLI — use `aws-broker`, not `aws` directly

All AWS CLI calls **must** go through the `aws-broker` wrapper. It runs aws-cli inside a docker container with the host's `~/.aws/` bind-mounted, so config / credentials / SSO cache stay in one place but every invocation flows through a single auditable path. (The boundary is convention-enforced via this rule — not physical isolation — but it keeps the door open to swap the storage layer for a sealed volume or short-lived STS later without breaking anyone's muscle memory.)

```bash
# ✅ Correct — profile name first, then aws args
aws-broker red-codens-prod sts get-caller-identity
aws-broker red-codens-prod s3 ls s3://my-bucket
aws-broker green-codens-prod logs tail "/ecs/green-codens-prod/celery-worker" --since 1h

# ❌ Don't do this — defeats the purpose of the wrapper
aws --profile red-codens-prod sts get-caller-identity
aws sts get-caller-identity
```

Helper subcommands:
- `aws-broker list` — show configured profiles
- `aws-broker login <profile>` — SSO device-code login for a profile
- `aws-broker --help` — full usage

The current working directory is bind-mounted into the container at `/work`, so relative paths work for `aws s3 cp ./file ...`. **Never** call the bare `aws` binary; if you need a profile that isn't configured, ask the user to run `aws-broker login <profile>` themselves.

## Common workflows (use these idioms, save tokens)

```bash
# Find files (use fd, not find)
fd <pattern>

# Search code (use rg, not grep -r)
rg 'pattern' [path]

# View files (use bat for syntax highlight)
bat <file>

# List dir (use eza)
eza -la [path]

# Inspect JSON (jq is everywhere)
cat foo.json | jq '.'

# Run a one-off command in a Node.js version
mise exec node@22 -- node script.js

# Run docker-compose (note: it's `docker compose`, not `docker-compose`)
docker compose up -d
```

## Skills available locally

Look at `~/.claude/skills/` for skills shipped to all VPS. To use a skill, just describe the task naturally — Claude triggers them based on the description in their YAML frontmatter.

Currently shipped:
- **playwright-cli** — browser automation, scraping, screenshots, codegen
- **code-nav** — fast code navigation (rg / fd / ast-grep) instead of `Read`-ing huge files
- **escalate-to-claude** — **[Qwen-backed sessions only]** delegate hard subtasks to upstream Claude (Sonnet/Opus). The script refuses to run when `ANTHROPIC_BASE_URL` is unset, so it's a no-op in regular `claude` sessions

## Output style (token discipline)

- **Code first, prose second.** Show the diff/command/file the user asked for; explain only what's non-obvious.
- **No throat-clearing.** Skip "Sure, I'll help with that", "Let me", "I'll start by", "Here's what I did".
- **No recap of the user's question.** They know what they asked.
- **No section headers** for short answers. Save them for multi-step plans.
- **Tables and lists > paragraphs** when the content is enumerable.
- **End-of-turn summary**: ≤ 2 sentences. What changed, what's next.
- For long Bash output, **trust the output-truncate hook** — don't try to summarize on top of it.
- Match response length to the question — a one-line question deserves a one-line answer.

## When in doubt

- Bug in this VPS / can't access something → tell user to Slack ops
- Need a new tool installed → tell user to request it (we update the Ansible role and re-deploy to all VPS)
- Need a new skill → suggest the user ask ops to add it to `roles/claude-config/files/claude-home/skills/`
