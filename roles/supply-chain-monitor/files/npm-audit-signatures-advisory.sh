#!/usr/bin/env bash
# npm-audit-signatures-advisory.sh — Wrap `npm install` / `npm ci` to run
# `npm audit signatures` afterward and WARN (not block) on unsigned packages.
#
# Installed via the supply-chain-monitor ansible role into /etc/profile.d/
# so every shell on the VPS picks up the alias automatically.
#
# Why advisory not enforced: in 2026 npm signed-publication adoption is still
# spotty — enforcing rejection would block 30-40% of legit installs. A
# stderr warning + audit log entry is enough for security team to triage.

# Only define if npm is present (skip on non-Node hosts)
command -v npm >/dev/null 2>&1 || return 0

_codens_npm_audit() {
  # Skip when called inside npm itself (avoid infinite recursion via lifecycle)
  [ -n "${npm_lifecycle_event:-}" ] && return 0
  # Skip CI / scripted contexts
  [ -n "${CODENS_NPM_NO_AUDIT:-}" ] && return 0
  ( command npm audit signatures 2>&1 | grep -E "ERR|warn|missing" | head -20 ) >&2 || true
}

npm() {
  case "${1:-}" in
    install|i|ci|add|update|up)
      command npm "$@"
      local rc=$?
      _codens_npm_audit
      return $rc
      ;;
    *)
      command npm "$@"
      ;;
  esac
}
