#!/usr/bin/env bash
# pre-warm-qwen-gateway.sh: cron-driven warmup for the self-hosted RunPod
# gateway. Fires once a day shortly after the gateway pod's morning cron-start
# (8:50 JST per qwen-llmgw schedule). Sends a single short request so the
# vLLM process gets its KV/prefix caches warm before the first user
# interaction; this avoids the ~3-5s TTFT spike on the first request after a
# cold pod start.
#
# Failure-tolerant: if the pod isn't up yet, the request just times out and we
# log the error. No retry loop — the first real user request handles cold
# start naturally.

set -u

GATEWAY_URL="${CLAUDE_QWEN_GATEWAY_URL:-https://qwen-gw.corevice-vps.com}"
GATEWAY_TOKEN="${CLAUDE_QWEN_GATEWAY_TOKEN:-REPLACE_WITH_YOUR_QWEN_GATEWAY_TOKEN}"
MODEL="${CLAUDE_QWEN_MODEL:-vllm-qwen,Qwen/Qwen3.6-27B-FP8}"

ts="$(date -Is)"
out=$(curl -sf -m 60 -X POST "${GATEWAY_URL}/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${GATEWAY_TOKEN}" \
  -H "anthropic-version: 2023-06-01" \
  -d "{\"model\":\"${MODEL}\",\"max_tokens\":20,\"messages\":[{\"role\":\"user\",\"content\":\"PING\"}]}" 2>&1)
rc=$?

stop_reason=$(printf '%s' "$out" | jq -r '.stop_reason // "?"' 2>/dev/null || echo "?")
echo "[${ts}] qwen gateway warmup rc=${rc} stop_reason=${stop_reason}"
exit 0
