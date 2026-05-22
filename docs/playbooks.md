# Playbook Reference

This document describes each playbook phase in the `playbooks/` directory and how to run them.

## Overview

Playbooks are numbered in deployment order. Run them sequentially for fresh provisioning, or individually for targeted updates.

```bash
# Run all playbooks in order
for p in playbooks/*.yml; do
  ansible-playbook "$p" --limit vps-<name>
done

# Run a specific playbook
ansible-playbook playbooks/10-harden.yml --limit vps-<name>
```

## Playbook Phases

### 00-bootstrap.yml
Initial server setup. Installs base packages, sets hostname, configures DNS resolvers.
- **When**: First provisioning only
- **Tags**: `bootstrap`

### 10-harden.yml
Security hardening: sysctl tweaks, unattended-upgrades, auditd rules, fail2ban.
- **When**: After bootstrap, before users
- **Tags**: `harden`

### 20-users.yml
Creates per-developer Linux user, sudoers config, SSH authorized_keys.
- **When**: After harden
- **Tags**: `users`

### 30-dev-tools.yml
Installs git, build-essentials, mise (Node.js/Ruby/Python version manager).
- **When**: After users
- **Tags**: `dev-tools`

### 35-chrome-playwright.yml
Headless Chrome and Playwright for browser automation.
- **When**: After dev-tools
- **Tags**: `chrome`

### 40-cloudflare-tunnel.yml
Installs and configures cloudflared for Zero Trust tunnel access.
- **When**: After dev-tools
- **Tags**: `tunnel`

### 42-warp-vip.yml
Binds 10.200.0.X/32 on loopback for WARP private network fabric.
- **When**: After tunnel
- **Tags**: `warp`

### 45-disk-quota.yml
Per-user disk quotas to prevent one user from filling the VPS disk.
- **When**: After users
- **Tags**: `quota`

### 50-code-server.yml
Browser-based VS Code (code-server) on 127.0.0.1:8080, exposed via Cloudflare Tunnel.
- **When**: After tunnel
- **Tags**: `code-server`

### 55-security-roundup.yml
Additional security: docker-firewall, docker-limits, extra fail2ban rules.
- **When**: After code-server
- **Tags**: `security`

### 57-supply-chain-monitor.yml
auditd watches for npm/VS Code extension installs to detect supply-chain attacks.
- **When**: After dev-tools
- **Tags**: `supply-chain`

### 60-monitoring.yml
node_exporter metrics, postfix for outbound alert emails.
- **When**: After security-roundup
- **Tags**: `monitoring`

### 70-log-shipping.yml
auditd → S3 via AWS IAM Roles Anywhere (no static keys on host).
- **When**: After monitoring
- **Tags**: `logging`

### 80-metadata.yml
Host facts collection for ops dashboard.
- **When**: Last
- **Tags**: `metadata`

### 90-claude-config.yml
Per-user Claude CLI config, hooks, and scripts.
- **When**: After users
- **Tags**: `claude`

### 95-aws-broker.yml
Wrapper script that issues short-lived STS credentials via Roles Anywhere.
- **When**: After log-shipping
- **Tags**: `aws`

### 96-purple-agent-qwen-env.yml
(Optional) self-hosted Qwen LLM agent service environment.
- **When**: Optional, after aws-broker
- **Tags**: `qwen`

### 99-smoke-test.yml
Post-provisioning validation: network, services, SSH, tunnel connectivity.
- **When**: Always last
- **Tags**: `smoke`

## Running by Tag

```bash
# Apply only hardening
ansible-playbook site.yml --limit vps-<name> --tags harden

# Re-run only users playbook (e.g., after adding a team member)
ansible-playbook playbooks/20-users.yml --limit vps-<name>
```

## Limiting to Specific Hosts

```bash
# Single host
ansible-playbook site.yml --limit vps-alice

# Multiple hosts
ansible-playbook site.yml --limit vps-alice,vps-bob

# By group
ansible-playbook site.yml --limit tag_Name_VPS:&production
```