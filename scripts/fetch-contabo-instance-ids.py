#!/usr/bin/env python3
"""Fetch Contabo instance IDs via Contabo API and auto-fill the
contabo_instance_id and contabo_account fields in members.yml.

Multi-account: supports listing instances across multiple Contabo
accounts (e.g. one parent account that owns multiple sub-accounts).

Credentials live in ~/.contabo-accounts.yaml (chmod 0600, gitignored).
Schema:

    accounts:
      account-a:
        client_id: INT-XXXXXXXX
        client_secret: <secret>
        user: ops@example.com
        password: <password>
      account-b:
        client_id: INT-YYYYYYYY
        client_secret: <secret>
        user: ops@example.com
        password: <password>
"""
import json
import subprocess
import sys
import yaml
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MEMBERS_FILE = ROOT / "members.yml"
ACCOUNTS_FILE = Path.home() / ".contabo-accounts.yaml"


def fetch_account(account_name: str, creds: dict) -> list[dict]:
    """cntb の --oauth2-* flag 直接指定で認証 (config file に依存しない)"""
    try:
        result = subprocess.run(
            [
                "cntb", "get", "instances",
                "--oauth2-clientid", creds["client_id"],
                "--oauth2-client-secret", creds["client_secret"],
                "--oauth2-user", creds["user"],
                "--oauth2-password", creds["password"],
                "--output", "json", "--size", "100",
            ],
            capture_output=True, text=True, check=True,
        )
    except FileNotFoundError:
        print("FATAL: cntb CLI not found", file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"FATAL: cntb failed for account {account_name}: {e.stderr}", file=sys.stderr)
        sys.exit(1)

    return json.loads(result.stdout)


def extract_ipv4(inst: dict) -> str | None:
    ip_config = inst.get("ipConfig", {})
    v4 = ip_config.get("v4")
    if v4:
        if isinstance(v4, dict):
            return v4.get("ip")
        if isinstance(v4, list) and v4:
            return v4[0].get("ip")
    return inst.get("ipv4")


def main() -> int:
    if not ACCOUNTS_FILE.exists():
        print(f"ERROR: {ACCOUNTS_FILE} not found. See docstring for format.", file=sys.stderr)
        return 1
    if ACCOUNTS_FILE.stat().st_mode & 0o077:
        print(f"WARN: {ACCOUNTS_FILE} permissions too open, chmod 600 recommended", file=sys.stderr)

    if not MEMBERS_FILE.exists():
        print(f"ERROR: {MEMBERS_FILE} not found", file=sys.stderr)
        return 1

    accounts = yaml.safe_load(ACCOUNTS_FILE.read_text())["accounts"]

    # ip → (account_name, instance_id) map
    ip_to_info: dict[str, tuple[str, str]] = {}
    for acc_name, creds in accounts.items():
        print(f"Fetching from account: {acc_name} ({creds['user']})...")
        instances = fetch_account(acc_name, creds)
        for inst in instances:
            ip = extract_ipv4(inst)
            if ip:
                instance_id = str(inst.get("instanceId") or inst.get("id"))
                if ip in ip_to_info:
                    print(f"  WARN: IP {ip} appears in multiple accounts (keeping first)")
                    continue
                ip_to_info[ip] = (acc_name, instance_id)
        print(f"  → {len(instances)} instances")

    print(f"\nTotal unique IPs across accounts: {len(ip_to_info)}\n")

    original_text = MEMBERS_FILE.read_text()
    data = yaml.safe_load(original_text)

    updates: list[tuple[str, str, str, str]] = []  # (slug, ip, account, instance_id)
    missing: list[tuple[str, str]] = []

    for slug, m in data["members"].items():
        if m.get("lifecycle_state") != "active":
            continue
        ip = m.get("public_ipv4")
        if not ip or ip == "TODO":
            missing.append((slug, "public_ipv4 not set"))
            continue
        info = ip_to_info.get(ip)
        if not info:
            missing.append((slug, f"no instance with ip={ip} in any account"))
            continue
        account, iid = info
        updates.append((slug, ip, account, iid))

    print(f"Matched: {len(updates)}")
    for slug, ip, account, iid in updates:
        print(f"  {slug:20s} {ip:16s} [{account:10s}] → {iid}")

    if missing:
        print(f"\nUnmatched: {len(missing)}")
        for slug, reason in missing:
            print(f"  {slug}: {reason}")

    if not updates:
        return 0

    # textual substitution for members.yml (preserve comments)
    import re
    new_text = original_text
    for slug, ip, account, iid in updates:
        # contabo_instance_id: TODO を置換
        iid_pattern = rf"(  {re.escape(slug)}:\n(?:    [^\n]*\n)*?    contabo_instance_id: )TODO"
        new_text, n1 = re.subn(iid_pattern, rf"\g<1>{iid}", new_text, count=1)

        # contabo_account フィールドが未定義なら contabo_instance_id 行の直後に挿入
        # 既存なら上書き
        acc_pattern_existing = rf"(  {re.escape(slug)}:\n(?:    [^\n]*\n)*?    contabo_account: )\w+"
        if re.search(acc_pattern_existing, new_text):
            new_text = re.sub(acc_pattern_existing, rf"\g<1>{account}", new_text, count=1)
        else:
            # contabo_instance_id 行の直後に insert
            iid_line_pattern = rf"(  {re.escape(slug)}:\n(?:    [^\n]*\n)*?    contabo_instance_id: {re.escape(iid)}\n)"
            new_text = re.sub(
                iid_line_pattern,
                rf"\g<1>    contabo_account: {account}\n",
                new_text, count=1
            )

    MEMBERS_FILE.write_text(new_text)
    print(f"\nWrote {MEMBERS_FILE}")
    print("Next: python3 scripts/generate-inventory.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
