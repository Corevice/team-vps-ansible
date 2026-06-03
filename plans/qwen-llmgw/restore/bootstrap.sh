#!/usr/bin/env bash
# Self-healing bootstrap for the Qwen gateway. Idempotent.
export HF_HOME=/workspace/hf-cache
mkdir -p /workspace/logs
echo "=== $(date) bootstrap start ===" >> /workspace/logs/bootstrap.log

# 1) vLLM (install if container disk was reset)
if ! command -v vllm >/dev/null 2>&1; then
  echo "installing vllm==0.19.0..." >> /workspace/logs/bootstrap.log
  pip install --no-input "vllm==0.19.0" >> /workspace/logs/pip-install.log 2>&1
fi
if ! pgrep -f "vllm serve" >/dev/null 2>&1; then
  setsid /workspace/qwen-restore/start-vllm.sh </dev/null >>/workspace/logs/vllm.log 2>&1 &
  echo "vLLM launched" >> /workspace/logs/bootstrap.log
fi

# 2) nginx-qwen (:4000)
if ! ss -tlnp 2>/dev/null | grep -q ':4000'; then
  nginx -c /workspace/qwen-restore/nginx-qwen.conf && echo "nginx-qwen started" >> /workspace/logs/bootstrap.log
fi

# 3) cloudflared
if ! pgrep -f "cloudflared.*tunnel run" >/dev/null 2>&1; then
  if ! command -v cloudflared >/dev/null 2>&1; then
    curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
  fi
  setsid /workspace/qwen-restore/start-cf.sh </dev/null >>/workspace/logs/cloudflared.log 2>&1 &
  echo "cloudflared launched" >> /workspace/logs/bootstrap.log
fi
echo "=== bootstrap done ===" >> /workspace/logs/bootstrap.log
