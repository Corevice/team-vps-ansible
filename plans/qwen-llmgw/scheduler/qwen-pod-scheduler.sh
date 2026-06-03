#!/usr/bin/env bash
# qwen-pod-scheduler.sh — Qwen gateway pod を平日 9-21 JST だけ動かす。
#
# 希少 GPU(RTX PRO 6000 Blackwell)は stop/start だと host 固定で再起動に失敗しうるため、
# **create / terminate 方式**を採る:
#   up   : pod を毎朝【新規作成】(空きホストに割当 → host固定問題を回避) → restore 配置 → bootstrap
#   down : 名前 ${POD_NAME} の pod を【terminate】(state 不要、名前で特定)
#
# ⚠️ terminate は volume も破棄するため、毎朝モデル(~29GB)を再DLする(数分の追加起動)。
#    回避したい場合は network volume にモデルキャッシュを常設する(README 参照)。
#
# 必要 env:
#   RUNPOD_API_KEY            (必須)
#   SSH_KEY_FILE              (up: pod へ SSH する秘密鍵)
#   CF_TUNNEL_TOKEN           (up: cloudflared connector token = tunnel b2910379)
#   POD_NAME (default qwen-gateway), GPU_TYPES, RESTORE_DIR (default: ../restore)
set -euo pipefail

POD_NAME="${POD_NAME:-qwen-gateway}"
API="https://rest.runpod.io/v1/pods"
auth=(-H "Authorization: Bearer ${RUNPOD_API_KEY:?RUNPOD_API_KEY を設定}")
ACTION="${1:?usage: qwen-pod-scheduler.sh up|down}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESTORE_DIR="${RESTORE_DIR:-$HERE/../restore}"
IMAGE="runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04"
# 候補 GPU は up 時に RunPod から動的列挙(RTX PRO 6000 系統 ≥90GB を全部)。失敗時の fallback ↓
FALLBACK_GPUS='["NVIDIA RTX PRO 6000 Blackwell Server Edition","NVIDIA RTX PRO 6000 Blackwell Workstation Edition","NVIDIA RTX PRO 6000 Blackwell Max-Q Workstation Edition"]'
# 空きを拾う cloud の優先順。SECURE のみにしたいなら env CLOUD_TYPES="SECURE"。
CLOUD_TYPES="${CLOUD_TYPES:-SECURE COMMUNITY}"
jget(){ python3 -c "import sys,json;d=json.load(sys.stdin);print($1)" 2>/dev/null; }

case "$ACTION" in
  down)
    ids=$(curl -s "${auth[@]}" "$API" | python3 -c "
import sys,json
for p in json.load(sys.stdin):
    if p.get('name')=='$POD_NAME': print(p['id'])" 2>/dev/null)
    [ -z "$ids" ] && { echo "no pod named $POD_NAME (already down)"; exit 0; }
    for id in $ids; do
      curl -s -X DELETE "${auth[@]}" "$API/$id" >/dev/null && echo "✓ terminated $id"
    done
    ;;

  up)
    : "${SSH_KEY_FILE:?SSH_KEY_FILE を設定}"; : "${CF_TUNNEL_TOKEN:?CF_TUNNEL_TOKEN を設定}"
    WINDOW_MIN="${CREATE_RETRY_MINUTES:-60}"
    # 既存があれば二重作成しない
    existing=$(curl -s "${auth[@]}" "$API" | python3 -c "
import sys,json
for p in json.load(sys.stdin):
    if p.get('name')=='$POD_NAME': print(p['id']); break" 2>/dev/null)
    if [ -n "$existing" ]; then echo "pod $POD_NAME already exists ($existing); reusing"; PID="$existing"; else
      # RTX PRO 6000 系統(≥90GB; MIG 24/48GB は 27B+256K に不足なので除外)を動的列挙
      GPU_TYPES_JSON=$(curl -s "https://api.runpod.io/graphql?api_key=${RUNPOD_API_KEY}" -H "Content-Type: application/json" \
        -d '{"query":"query{gpuTypes{id memoryInGb}}"}' | python3 -c "
import sys,json
try:
  g=json.load(sys.stdin).get('data',{}).get('gpuTypes',[]) or []
  ids=[x['id'] for x in g if 'RTX PRO 6000' in (x.get('id') or '') and (x.get('memoryInGb') or 0)>=90]
  print(json.dumps(ids) if ids else '')
except Exception: print('')" 2>/dev/null)
      [ -z "$GPU_TYPES_JSON" ] && GPU_TYPES_JSON="$FALLBACK_GPUS"
      echo "GPU candidates (RTX PRO 6000 ≥90GB): $GPU_TYPES_JSON"
      echo "creating pod (retry up to ${WINDOW_MIN}min; cloud order: $CLOUD_TYPES)..."
      PID=""
      for i in $(seq 1 $(( WINDOW_MIN * 2 ))); do
        for CT in $CLOUD_TYPES; do
          body=$(CT="$CT" GPUS="$GPU_TYPES_JSON" KEYF="$SSH_KEY_FILE.pub" python3 -c "import json,os;print(json.dumps({'name':'$POD_NAME','imageName':'$IMAGE','gpuTypeIds':json.loads(os.environ['GPUS']),'gpuCount':1,'cloudType':os.environ['CT'],'containerDiskInGb':60,'volumeInGb':200,'volumeMountPath':'/workspace','ports':['4000/http','22/tcp'],'env':{'PUBLIC_KEY':open(os.environ['KEYF']).read().strip(),'JUPYTER_PASSWORD':'disabled'}}))")
          resp=$(curl -s -X POST "${auth[@]}" -H "Content-Type: application/json" -d "$body" "$API")
          PID=$(echo "$resp" | jget "d.get('id','')")
          [ -n "$PID" ] && { echo "created $PID (attempt $i, cloud=$CT)"; break 2; }
        done
        sleep 30   # 全候補×cloud で no-instances → wait & retry
      done
      [ -n "$PID" ] || { echo "::error::could not create pod within ${WINDOW_MIN}min (no RTX PRO 6000 capacity in any cloud)"; exit 1; }
    fi

    echo "waiting RUNNING + SSH endpoint..."
    IP=""; PORT=""
    for i in $(seq 1 60); do
      j=$(curl -s "${auth[@]}" "$API/$PID")
      st=$(echo "$j"|jget "d.get('desiredStatus')"); IP=$(echo "$j"|jget "d.get('publicIp') or ''"); PORT=$(echo "$j"|jget "(d.get('portMappings') or {}).get('22') or ''")
      [ "$st" = "RUNNING" ] && [ -n "$IP" ] && [ -n "$PORT" ] && break
      sleep 10
    done
    [ -n "$IP" ] && [ -n "$PORT" ] || { echo "::error::no SSH endpoint"; exit 1; }
    SOPT="-i $SSH_KEY_FILE -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o IdentitiesOnly=yes"
    for i in $(seq 1 40); do ssh $SOPT -p "$PORT" root@"$IP" 'echo ok' >/dev/null 2>&1 && break; sleep 10; done

    echo "pushing restore scripts + cf token..."
    ssh $SOPT -p "$PORT" root@"$IP" 'mkdir -p /workspace/qwen-restore /workspace/logs'
    # ★ scp はポート指定が -P (大文字)。-p(小文字)は ssh 用なので混同しないこと。
    scp $SOPT -P "$PORT" "$RESTORE_DIR"/bootstrap.sh "$RESTORE_DIR"/start-vllm.sh "$RESTORE_DIR"/start-cf.sh "$RESTORE_DIR"/nginx-qwen.conf root@"$IP":/workspace/qwen-restore/
    scp $SOPT -P "$PORT" "$RESTORE_DIR"/post_start.sh root@"$IP":/post_start.sh
    printf '%s' "$CF_TUNNEL_TOKEN" | ssh $SOPT -p "$PORT" root@"$IP" 'cat > /workspace/qwen-restore/cf.token && chmod 600 /workspace/qwen-restore/cf.token'
    ssh $SOPT -p "$PORT" root@"$IP" 'chmod +x /workspace/qwen-restore/*.sh /post_start.sh'

    echo "running bootstrap (pip install vLLM + model DL + start)..."
    ssh $SOPT -p "$PORT" root@"$IP" 'bash /workspace/qwen-restore/bootstrap.sh'
    echo "✓ $POD_NAME up ($PID @ $IP:$PORT). gateway ready in a few minutes (model download+load)."
    ;;

  *) echo "unknown action: $ACTION (use up|down)"; exit 2 ;;
esac
