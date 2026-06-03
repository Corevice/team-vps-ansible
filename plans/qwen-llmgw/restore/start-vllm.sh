#!/usr/bin/env bash
exec >>/workspace/logs/vllm.log 2>&1
export HF_HOME=/workspace/hf-cache
echo "=== $(date) starting vLLM ==="
exec vllm serve Qwen/Qwen3.6-27B-FP8 \
  --host 127.0.0.1 --port 8000 \
  --trust-remote-code --max-model-len 262144 \
  --served-model-name Qwen/Qwen3.6-27B-FP8 zai-org/GLM-4.7-Flash claude-sonnet-4-6 claude-opus-4-7 claude-haiku-4-5 claude-haiku-4-5-20251001 "vllm-qwen,Qwen/Qwen3.6-27B-FP8" \
  --generation-config vllm --reasoning-parser qwen3 \
  --enable-auto-tool-choice --tool-call-parser qwen3_xml \
  --gpu-memory-utilization 0.94 --enable-prefix-caching --enable-chunked-prefill \
  --max-num-seqs 16 --mamba-cache-dtype float16 --mamba-ssm-cache-dtype float16 \
  --speculative-config '{"method":"mtp","num_speculative_tokens":3}'
