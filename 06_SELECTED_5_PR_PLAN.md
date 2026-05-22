# 06_SELECTED_5_PR_PLAN.md — team-vps-ansible

## Selected PRs (in priority order)

### PR-1: Add GitHub Actions CI
**Rationale:** Zero CI is the most obvious gap. Even basic linting catches YAML syntax errors and Terraform formatting issues before they reach production.  
**Effort:** Medium | **Acceptance likelihood:** High  

**Branch:** `pr/add-ci`  
**Files to add:** `.github/workflows/ci.yml`  

**Plan:**
1. Create `.github/workflows/ci.yml`
2. Jobs: `ansible-lint` (scan all `.yml` in playbooks/ and roles/), `terraform-format` (run `terraform fmt -check` in each terraform subdir), `terraform-validate` (run `terraform validate` in each subdir)
3. Trigger on: push to `main`, PRs to `main`
4. Use official `ansible-lint` GitHub Action, hashicorp/setup-terraform
5. Open PR against `Corevice/team-vps-ansible:main`

---

### PR-2: Add missing playbook: `11-sshd-lockdown.yml`
**Rationale:** Explicitly referenced in `docs/network-security.md` as "実装時に対応予定" — the maintainer has already identified this as needed. Closes a real security gap (external SSH brute-force on port 22).  
**Effort:** Medium | **Acceptance likelihood:** High  

**Branch:** `pr/sshd-lockdown`  
**Files to add:** `playbooks/11-sshd-lockdown.yml`, `roles/sshd-lockdown/tasks/main.yml`, `roles/sshd-lockdown/handlers/main.yml`  

**Plan:**
1. Create `roles/sshd-lockdown/tasks/main.yml`:
   - Template `/etc/ssh/sshd_config` to set `ListenAddress 127.0.0.1`  
   - Validate sshd_config with `sshd -t` before reload  
   - Restart sshd via handler
2. Create `roles/sshd-lockdown/handlers/main.yml`: restart sshd
3. Create `playbooks/11-sshd-lockdown.yml` importing the role with tag `sshd-lockdown`
4. Update `docs/network-security.md` to remove the "実装時に対忚" callout and mark as implemented

---

### PR-3: Add `members.yml` schema validation
**Rationale:** The only input file (`members.yml`) has no validation. A clear validation failure message prevents 30 minutes of debug time when a new member is onboarded with a typo in a field name.  
**Effort:** Low | **Acceptance likelihood:** High  

**Branch:** `pr/members-schema-validation`  
**Files to modify:** `scripts/generate-inventory.py`  

**Plan:**
1. Add `import jsonschema` (or manual checks if no deps preferred)  
2. Define schema inline: required fields `slug`, `name`, `email`, `lifecycle_state`; enum for `lifecycle_state`  
3. Wrap `members_data = yamldecode(...)` in try/except with clear error message on `jsonschema.ValidationError`  
4. Also validate: `slug` matches `^[a-z0-9-]+$` (VPS hostname compatibility)  
5. Test by creating `members.yml.example` variant with bad data, confirm clean error

---

### PR-4: Add Python `requirements.txt` for scripts
**Rationale:** No dependency management for the Python scripts. Operator has to guess what's needed.  
**Effort:** Low | **Acceptance likelihood:** High  

**Branch:** `pr/python-deps`  
**Files to add:** `requirements.txt`  

**Plan:**
1. Create `requirements.txt` with `pyyaml` (only required dep for `generate-inventory.py`)  
2. Update `README.md` quick-start section to mention `pip install -r requirements.txt`  
3. Update `scripts/generate-inventory.py` shebang to use `python3` explicitly (not `python`)

---

### PR-5: Improve `docs/mobile-ssh-guide.md` with Termius + Blink examples
**Rationale:** Mobile SSH access is a stated goal of the project ("phone, tablet without VPN client") but the guide only covers OpenSSH CLI. Mobile-specific clients need explicit instructions.  
**Effort:** Low | **Acceptance likelihood:** High  

**Branch:** `pr/mobile-ssh-guide`  
**Files to modify:** `docs/mobile-ssh-guide.md`  

**Plan:**
1. Add Termius section: key import (PPK/PEM), host config, port forwarding UI walkthrough
2. Add Blink (CBL) section: key import, command-line port forward example (`blink ssh ...`)
3. Keep existing OpenSSH section; don't remove
4. Add ASCII flow diagram for tunnel path: device → Cloudflare → VPS
5. Update `docs/network-security.md` cross-reference if needed

---

## PR Ordering
1. **PR-1 (CI)** first — establishes quality gate for subsequent PRs
2. **PR-3 (Schema validation)** second — makes onboarding safer before adding new members
3. **PR-2 (sshd-lockdown)** third — security improvement, explicit maintainer intent
4. **PR-4 (requirements.txt)** fourth — low effort, clears dependency confusion
5. **PR-5 (mobile guide)** last — pure documentation, independent of other changes

## Conflict Risk
- **Very low.** This is a 2-commit repo with no active development. Fork is clean.
- Each PR touches distinct files; no overlapping changes.
- No CI currently exists, so no existing workflow to conflict with.

## Sync Strategy
- Fork is even with upstream (no divergent commits)
- Submit PRs sequentially from `main` branch
- If upstream advances between PRs: `git fetch upstream && git merge upstream/main` before targeting next PR