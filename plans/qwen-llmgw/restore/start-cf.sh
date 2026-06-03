#!/usr/bin/env bash
exec >>/workspace/logs/cloudflared.log 2>&1
exec cloudflared --no-autoupdate tunnel run --token "$(cat /workspace/qwen-restore/cf.token)"
