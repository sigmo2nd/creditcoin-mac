#!/bin/bash
echo "크레딧코인 파이썬 모니터 시작"

# 설정 정보 출력
echo "=== 설정 정보 ==="
echo "- CREDITCOIN_DIR: ${M_CREDITCOIN_DIR:-$(pwd)}"
echo "- NODE_NAMES: ${M_NODE_NAMES:-node,3node}"
echo "- MONITOR_INTERVAL: ${M_MONITOR_INTERVAL:-5}초"
echo "- WS_MODE: ${M_WS_MODE:-auto}"
if [ ! -z "${M_WS_SERVER_URL}" ]; then
  echo "- WS_SERVER_URL: ${M_WS_SERVER_URL}"
fi
echo "- SERVER_ID: ${M_SERVER_ID:-server1}"

# 추가 인자 구성
ARGS=""
if [ ! -z "${M_SERVER_ID}" ]; then
  ARGS="$ARGS --server-id ${M_SERVER_ID}"
fi

if [ ! -z "${M_NODE_NAMES}" ]; then
  ARGS="$ARGS --nodes ${M_NODE_NAMES}"
fi

if [ ! -z "${M_MONITOR_INTERVAL}" ]; then
  ARGS="$ARGS --interval ${M_MONITOR_INTERVAL}"
fi

if [ ! -z "${M_WS_MODE}" ]; then
  ARGS="$ARGS --ws-mode ${M_WS_MODE}"
fi

if [ ! -z "${M_WS_SERVER_URL}" ]; then
  ARGS="$ARGS --ws-url ${M_WS_SERVER_URL}"
fi

# 모니터링 실행
echo "크레딧코인 모니터링을 시작합니다..."
python3 main.py $ARGS