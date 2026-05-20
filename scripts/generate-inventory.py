#!/usr/bin/env python3
"""members.yml + keys/ から inventory/hosts.yml と host_vars/*.yml を生成"""
import sys
import yaml
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class InlineString(str):
    """強制的に single-line 出力させるための marker"""


def _inline_str_repr(dumper, data):
    # ssh pubkey 等は single line (folded scalar にしない)
    return dumper.represent_scalar("tag:yaml.org,2002:str", str(data), style='"')


yaml.add_representer(InlineString, _inline_str_repr)


def read_pubkey(slug: str) -> str:
    p = ROOT / "keys" / f"{slug}.pub"
    if p.exists():
        return p.read_text().strip()
    return f"TODO_RUN_GENERATE_MEMBER_KEYS_FOR_{slug.upper()}"


def read_operator_pubkey(operator: dict) -> str:
    val = operator.get("ssh_pubkey", "TODO")
    if val.startswith("@file:"):
        path = ROOT / val[len("@file:"):]
        return path.read_text().strip()
    return val


def main() -> int:
    members_file = ROOT / "members.yml"
    if not members_file.exists():
        print("ERROR: members.yml not found.", file=sys.stderr)
        return 1

    data = yaml.safe_load(members_file.read_text())
    members = {
        k: v for k, v in sorted(data["members"].items())
        if v.get("lifecycle_state") == "active"
    }
    common = data["common"]
    operator = data["operator"]
    operator_pub = read_operator_pubkey(operator)

    warp_prefix = common.get("warp_network_prefix")

    hosts = {}
    for slug, m in members.items():
        host = {
            "ansible_host": m.get("public_ipv4", "TODO"),
            "owner": slug,
            "owner_email": m["owner_email"],
            "owner_ssh_pubkey": InlineString(read_pubkey(slug)),
            "contabo_instance_id": m.get("contabo_instance_id", "TODO"),
        }
        if "vps_id" in m:
            host["vps_id"] = m["vps_id"]
            if warp_prefix:
                host["warp_virtual_ip"] = f"{warp_prefix}.{m['vps_id']}"
        hosts[f"vps-{slug}"] = host

    hosts_yml = {
        "all": {
            "vars": {
                "ansible_user": "ansible",
                "ansible_python_interpreter": "/usr/bin/python3",
                "domain": common["domain"],
            },
            "children": {"vps": {"hosts": hosts}},
        }
    }

    (ROOT / "inventory" / "hosts.yml").write_text(
        yaml.dump(hosts_yml, sort_keys=False, default_flow_style=False, width=4096)
    )
    print(f"wrote inventory/hosts.yml ({len(members)} hosts, alphabetical)")

    hv_dir = ROOT / "inventory" / "host_vars"
    hv_dir.mkdir(exist_ok=True)
    for slug, m in members.items():
        hv = {
            "owner": slug,
            "owner_email": m["owner_email"],
            "owner_ssh_pubkey": InlineString(read_pubkey(slug)),
            "operator_ssh_pubkey": InlineString(operator_pub),
            "operator_management_ip": operator.get("management_ip", "TODO"),
            "timezone": m.get("timezone", "Asia/Tokyo"),
        }
        if "vps_id" in m:
            hv["vps_id"] = m["vps_id"]
            if warp_prefix:
                hv["warp_virtual_ip"] = f"{warp_prefix}.{m['vps_id']}"
        (hv_dir / f"vps-{slug}.yml").write_text(
            yaml.dump(hv, sort_keys=False, default_flow_style=False, width=4096)
        )
    print(f"wrote {len(members)} host_vars files")

    unresolved = []
    for slug, m in members.items():
        if read_pubkey(slug).startswith("TODO_"):
            unresolved.append(f"  - {slug}: missing keys/{slug}.pub")
        if m.get("public_ipv4", "TODO") == "TODO":
            unresolved.append(f"  - {slug}: missing public_ipv4")
        if m.get("contabo_instance_id", "TODO") == "TODO":
            unresolved.append(f"  - {slug}: missing contabo_instance_id")

    if operator_pub.startswith("TODO_"):
        unresolved.append("  - operator: missing ssh_pubkey")
    if operator.get("management_ip", "TODO") == "TODO":
        unresolved.append("  - operator: missing management_ip")
    if common.get("domain", "").startswith("TODO"):
        unresolved.append("  - common: missing domain")
    if str(common.get("cloudflare_account_id", "")).startswith("TODO"):
        unresolved.append("  - common: missing cloudflare_account_id")

    if unresolved:
        print("\n=== Unresolved TODOs ===")
        for u in unresolved:
            print(u)
    else:
        print("\nAll inputs resolved.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
