# 01_REPO_MAP.md — team-vps-ansible

## Tree
```
team-vps-ansible/
├── README.md
├── LICENSE (MIT)
├── ansible.cfg
├── site.yml                    # aggregate playbook (all phases, most tags)
├── members.yml.example         # template for per-team member data (gitignored)
├── .gitignore                  # excludes members.yml, inventory/, *.tfvars, .vault_pass, keys/, secrets/, dist/
│
├── playbooks/                  # numbered phase playbooks
│   ├── 00-bootstrap.yml
│   ├── 10-harden.yml
│   ├── 20-users.yml
│   ├── 30-dev-tools.yml
│   ├── 35-chrome-playwright.yml
│   ├── 40-cloudflare-tunnel.yml
│   ├── 42-warp-vip.yml
│   ├── 45-disk-quota.yml
│   ├── 50-code-server.yml
│   ├── 55-security-roundup.yml
│   ├── 57-supply-chain-monitor.yml
│   ├── 60-monitoring.yml
│   ├── 70-log-shipping.yml
│   ├── 80-metadata.yml
│   ├── 90-claude-config.yml
│   ├── 95-aws-broker.yml
│   ├── 96-purple-agent-qwen-env.yml
│   └── 99-smoke-test.yml
│
├── roles/                      # 18 ansible roles
│   ├── aws-broker/            # STS creds via Roles Anywhere (short-lived, no static keys)
│   ├── chrome-playwright/     # headless browser for automation
│   ├── claude-autoupdate/     # Anthropic Claude CLI auto-updater
│   ├── claude-config/         # per-user Claude config, hooks, scripts, skills
│   ├── cloudflare-tunnel/     # cloudflared install + token wiring (Zero Trust)
│   ├── code-server/           # browser VS Code on 127.0.0.1:8080, exposed via CF Tunnel
│   ├── common/                # base packages
│   ├── dev-tools/             # git, build-essentials, mise, common CLI
│   ├── disk-quota/            # per-user disk quotas
│   ├── docker-firewall/       # iptables DOCKER-USER chain (Layer 2 of 3-layer container lock)
│   ├── docker-limits/         # Docker daemon "ip": "127.0.0.1" conf (Layer 3 of container lock)
│   ├── harden/                # sysctl, unattended-upgrades, auditd base rules, fail2ban
│   ├── log-shipping/          # auditd → S3 via Roles Anywhere, hourly timer
│   ├── monitoring/            # node_exporter, postfix for outbound alerts
│   ├── purple-agent-qwen-env/ # (optional) self-hosted Qwen LLM agent service env
│   ├── supply-chain-monitor/ # auditd watches for npm/VS Code supply-chain attacks
│   └── warp-vip/              # bind 10.200.0.X/32 on lo for WARP private routing
│
├── terraform/
│   ├── aws/
│   │   ├── main.tf           # S3 log bucket, IAM, KMS
│   │   ├── iam.tf            # IAM roles
│   │   ├── kms.tf            # KMS keys
│   │   ├── roles_anywhere.tf # Trust anchor (step-ca root CA), profiles (S3 log writer)
│   │   ├── s3.tf             # S3 bucket for audit logs
│   │   ├── ses.tf            # SES email
│   │   ├── outputs.tf
│   │   └── variables.tf
│   ├── cloudflare/
│   │   ├── main.tf           # data sources for IdP auto-detection (Google, OTP)
│   │   ├── access.tf         # CF Access policies per member
│   │   ├── dns.tf            # DNS records per member
│   │   ├── tunnels.tf        # Cloudflare Tunnel ingress definitions
│   │   ├── qwen-gw-tunnel.tf # Qwen gateway tunnel
│   │   ├── outputs.tf
│   │   └── variables.tf
│   └── contabo/
│       ├── corevice/         # Contabo VPS provisioning + firewall (Corevice account)
│       └── portament/        # Contabo VPS provisioning + firewall (Portament account)
│           ├── main.tf
│           ├── firewall.tf
│           ├── outputs.tf
│           └── variables.tf
│
├── scripts/
│   ├── generate-inventory.py       # inventory/hosts.yml + host_vars from members.yml
│   ├── generate-welcome-kits.sh    # tgz with onboarding docs, SSH config, welcome letter
│   ├── generate-member-keys.sh      # per-member SSH ed25519 keypairs
│   ├── generate-mobile-ssh-supplements.sh
│   ├── pki-bootstrap.sh             # bootstrap step-ca client cert (one-time per VPS)
│   ├── aws-ses-smtp-password.py
│   ├── fetch-contabo-instance-ids.py
│   └── snapshot-weekly.sh
│
├── docs/
│   ├── mobile-ssh-guide.md
│   ├── network-security.md         # 3-layer defense-in-depth (Contabo FW + iptables + docker ip)
│   └── warp-dashboard-setup.md
│
└── files/                          # static file templates (mostly Jinja)
```

## Key Dependencies
- `members.yml` (gitignored, not present) — team member data consumed by `generate-inventory.py`
- Terraform state: local backend (Phase 1); S3 backend planned for Phase 2
- Terraform providers: cloudflare (~5.0), random (~3.6), hashicorp/aws (implied)

## Notable Design Decisions
1. **Zero static AWS keys on VPS**: STS creds issued per-call via Roles Anywhere; trust anchor = step-ca root CA
2. **3-layer container lock**: Contabo Cloud Firewall → iptables DOCKER-USER chain → docker daemon `"ip": "127.0.0.1"`
3. **Per-user isolation**: one VPS per developer, real Linux user (no shared ubuntu account), auditd tags every syscall with uid
4. **SSH access**: only via Cloudflare Tunnel (outbound-only `cloudflared`) + operator IP allowlist on port 22
5. **Two Contabo accounts**: `corevice/` and `portament/` terraform modules for multi-account billing