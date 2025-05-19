#!/bin/bash
echo "== Creditcoin 모니터링 클라이언트 =="
echo "서버 ID: ${SERVER_ID}"
echo "모니터링 노드: ${NODE_NAMES}"
echo "모니터링 간격: ${MONITOR_INTERVAL}초"
echo "WebSocket 모드: ${WS_MODE}"
if [ "${WS_SERVER_HOST}" != "" ]; then echo "WebSocket 호스트: ${WS_SERVER_HOST}"; fi
if [ "${WS_SERVER_URL}" != "" ]; then echo "WebSocket URL: ${WS_SERVER_URL}"; fi
echo "시작 중..."
export PROCFS_PATH=/host/proc
python /app/main.py "$@"
