# 05_PR_CANDIDATES.md — team-vps-ansible

## Candidate List

### [PR-1] Add GitHub Actions CI: ansible-lint + terraform validate
**File(s):** `.github/workflows/ci.yml` (new)  
**Severity:** Low / DevEx  
**Effort:** Medium  

**Why:** No CI exists. A basic workflow validating playbook syntax and Terraform would catch errors before manual runs.  
**What:**
- `ansible-lint` on all `.yml` files  
- `terraform fmt -check` + `terraform validate` on each terraform module  
- Run on PRs to `main`

---

### [PR-2] Add missing playbook: `11-sshd-lockdown.yml`
**File(s):** `playbooks/11-sshd-lockdown.yml`, `roles/sshd-lockdown/` (new)  
**Severity:** Medium / Security  
**Effort:** Medium  

**Why:** `docs/network-security.md` explicitly calls out `11-sshd-lockdown.yml` as "実装時に対応予定" (to be implemented). It would:  
- bind sshd to `127.0.0.1:22`  
- close port 22 from external NIC via Cloud Firewall (Layer 1)  
- defeat external SSH brute-force entirely (only CF Tunnel SSH would work)  

**What:**
- New role `sshd-lockdown` with tasks to configure `sshd_config ListenAddress 127.0.0.1`  
- New playbook `11-sshd-lockdown.yml` imported after `10-harden.yml`  
- Update `network-security.md` to reflect implementation

---

### [PR-3] Add Molecule test scaffold for core roles
**File(s):** `molecule/default/molecule.yml`, `molecule/default/playbook.yml`, roles tests (new)  
**Severity:** Low / Quality  
**Effort:** Medium  

**Why:** No automated tests. Molecule is the standard test framework for Ansible roles. A minimal scaffold covering the `common` or `harden` role would establish a testing pattern.  
**What:**
- `molecule/default/` scenario for one representative role (e.g. `common`)  
- `molecule.yaml` root config  
- GitHub Actions job to run `molecule test`

---

### [PR-4] Terraform: migrate to S3 backend with DynamoDB lock
**File(s):** `terraform/aws/main.tf`, `terraform/cloudflare/main.tf`, `terraform/contabo/corevice/main.tf` (update)  
**Severity:** Medium / Ops  
**Effort:** Low  

**Why:** `docs/network-security.md` comments in `main.tf` say "Phase 2: switch to S3 backend". The S3 bucket and DynamoDB table for tfstate locking are already defined in `terraform/aws/s3.tf`. This is low-effort consolidation.  
**What:**
- Add `terraform { backend "s3" { ... } }` blocks to all three module `main.tf` files  
- Configure bucket key paths per environment (aws/cloudflare/contabo)  
- Add DynamoDB table for state locking

---

### [PR-5] Add `members.yml` schema validation to `generate-inventory.py`
**File(s):** `scripts/generate-inventory.py` (update)  
**Severity:** Low / Robustness  
**Effort:** Low  

**Why:** `members.yml` is the input for everything. If a field is missing or misnamed, inventory generation fails with an opaque Python traceback. Adding schema validation (e.g. with `jsonschema` or manual checks) would give clear error messages.  
**What:**
- Validate required fields: `members[].slug`, `members[].name`, `members[].email`, `members[].lifecycle_state`  
- Validate `lifecycle_state` enum: `active`, `inactive`, `deprovisioned`  
- Emit human-friendly errors on validation failure

---

### [PR-6] Add cloudflared watchdog / auto-restart on cloudflare-tunnel role
**File(s):** `roles/cloudflare-tunnel/` (update)  
**Severity:** Low / Reliability  
**Effort:** Medium  

**Why:** If `cloudflared` process dies, the VPS becomes unreachable via Cloudflare Tunnel. No watchdog/restart logic exists in the role.  
**What:**
- Add systemd `Restart=always` to the cloudflared unit  
- Add `RestartSec=5` and `WatchdogSec=60` health check  
- Document failure modes in `docs/network-security.md`

---

### [PR-7] Improve `docs/mobile-ssh-guide.md` with more client examples
**File(s):** `docs/mobile-ssh-guide.md` (update)  
**Severity:** Low / Documentation  
**Effort:** Low  

**Why:** The guide covers OpenSSH but mobile users on Termius (iOS/Android) and Blink (iOS) need specific config examples.  
**What:**
- Add Termius config (key import, port forwarding UI)  
- Add Blink shell command examples  
- Add screenshots (or ASCII diagrams) for the tunnel setup flow

---

### [PR-8] Add Python `requirements.txt` / `pyproject.toml` for scripts
**File(s):** `requirements.txt` (new), `scripts/` (update)  
**Severity:** Low / DevEx  
**Effort:** Low  

**Why:** Scripts (`generate-inventory.py`, `aws-ses-smtp-password.py`) have no dependency declaration. The README lists `ansible`, `terraform`, `gh`, `aws` as operator tools but not Python library deps.  
**What:**
- Add `requirements.txt` with `pyyaml` (for members.yml parsing) and any other deps  
- Add `pyproject.toml` for the whole repo

---

## Assessment
| # | Category | Confidence | Upstream Likely to Accept? |
|---|---|---|---|
| 1 | CI/Testing | High | Yes — ansible-lint/validate is standard |
| 2 | Security | High | Yes — explicitly referenced as planned |
| 3 | Testing | Medium | Yes if simple, might want molecule removed if complex |
| 4 | Ops | High | Yes — already planned in comments |
| 5 | Robustness | Medium | Yes — reduces operator friction |
| 6 | Reliability | Medium | Yes — improves availability |
| 7 | Docs | High | Yes — low effort, clear value |
| 8 | DevEx | Medium | Yes — solves a real missing piece |

**Note:** This is a brand-new private-use repo (0 stars, 0 issues, 2 commits). Upstream maintainer is the sole contributor. PR acceptance depends entirely on whether they respond. The fork has no additional commits so no sync conflicts are expected.