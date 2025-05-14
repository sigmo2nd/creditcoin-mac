#!/bin/bash
# node_client.sh - 크레딧코인 노드 메트릭 클라이언트
# 중앙 서버로 메트릭 데이터를 전송합니다.

# 설정
CENTRAL_SERVER="http://중앙서버주소:3000"  # 중앙 서버 URL
API_TOKEN="your-secret-token"              # API 토큰 (인증용)
SERVER_ID="$(hostname | tr '.' '-')"       # 서버 식별자
INTERVAL=30                                # 전송 간격 (초)
TEMP_DIR="/tmp/creditcoin_metrics"         # 임시 데이터 저장 위치
METRICS_FILE="$TEMP_DIR/metrics.json"      # 메트릭 데이터 파일

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 사용법 표시
usage() {
  echo "사용법: $0 [옵션]"
  echo "옵션:"
  echo "  -s, --server URL     중앙 서버 URL (기본값: $CENTRAL_SERVER)"
  echo "  -t, --token 토큰     API 토큰 (기본값: $API_TOKEN)"
  echo "  -i, --interval 초    전송 간격 (기본값: $INTERVAL초)"
  echo "  -h, --help           이 도움말 표시"
}

# 인자 처리
while [ $# -gt 0 ]; do
  case "$1" in
    -s|--server)
      CENTRAL_SERVER="$2"
      shift 2
      ;;
    -t|--token)
      API_TOKEN="$2"
      shift 2
      ;;
    -i|--interval)
      INTERVAL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "알 수 없는 옵션: $1"
      usage
      exit 1
      ;;
  esac
done

# 임시 디렉토리 생성
mkdir -p "$TEMP_DIR"

# 시작 메시지
echo -e "${BLUE}크레딧코인 노드 메트릭 클라이언트 시작${NC}"
echo -e "${YELLOW}중앙 서버: $CENTRAL_SERVER${NC}"
echo -e "${YELLOW}서버 ID: $SERVER_ID${NC}"
echo -e "${YELLOW}전송 간격: ${INTERVAL}초${NC}"

# 메트릭 수집 함수
collect_metrics() {
  echo "시스템 메트릭 수집 중..." >&2
  
  # sysinfo.sh가 있으면 그대로 사용
  if command -v sysinfo.sh &> /dev/null; then
    sysinfo.sh -j > "$METRICS_FILE"
    return
  fi
  
  # sysinfo.sh가 없으면 주요 메트릭만 수집
  timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  
  # 시스템 정보
  model=$(sysctl hw.model 2>/dev/null | awk -F ": " '{print $2}' || echo "Unknown")
  
  # CPU 정보
  cpu_info=$(top -l 1 -n 0 | grep -E "^CPU")
  user_cpu=$(echo "$cpu_info" | awk '{print $3}' | sed 's/%//')
  sys_cpu=$(echo "$cpu_info" | awk '{print $5}' | sed 's/%//')
  idle_cpu=$(echo "$cpu_info" | awk '{print $7}' | sed 's/%//')
  
  # 디스크 정보
  disk_info=$(df -h / | grep -v "Filesystem" | head -1)
  disk_total=$(echo "$disk_info" | awk '{print $2}')
  disk_used=$(echo "$disk_info" | awk '{print $3}')
  disk_avail=$(echo "$disk_info" | awk '{print $4}')
  disk_percent=$(echo "$disk_info" | awk '{print $5}' | sed 's/%//')
  
  # Docker 노드 정보 수집
  if command -v docker &> /dev/null && docker info &> /dev/null; then
    docker_stats=$(docker stats --no-stream --format "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}" 2>/dev/null | grep -E "node|3node")
    
    # JSON 형식으로 출력
    echo "{" > "$METRICS_FILE"
    echo "  \"timestamp\": \"$timestamp\"," >> "$METRICS_FILE"
    echo "  \"server_id\": \"$SERVER_ID\"," >> "$METRICS_FILE"
    echo "  \"system\": {" >> "$METRICS_FILE"
    echo "    \"model\": \"$model\"," >> "$METRICS_FILE"
    echo "    \"cpu_usage\": {" >> "$METRICS_FILE"
    echo "      \"user\": $user_cpu," >> "$METRICS_FILE"
    echo "      \"system\": $sys_cpu," >> "$METRICS_FILE"
    echo "      \"idle\": $idle_cpu" >> "$METRICS_FILE"
    echo "    }," >> "$METRICS_FILE"
    echo "    \"disk\": {" >> "$METRICS_FILE"
    echo "      \"total\": \"$disk_total\"," >> "$METRICS_FILE"
    echo "      \"used\": \"$disk_used\"," >> "$METRICS_FILE"
    echo "      \"available\": \"$disk_avail\"," >> "$METRICS_FILE"
    echo "      \"percent\": $disk_percent" >> "$METRICS_FILE"
    echo "    }" >> "$METRICS_FILE"
    echo "  }," >> "$METRICS_FILE"
    
    # 노드 정보 추가
    echo "  \"nodes\": [" >> "$METRICS_FILE"
    
    # 노드 처리
    node_count=0
    while IFS=$'\t' read -r name cpu mem mem_pct net; do
      if [ $node_count -gt 0 ]; then
        echo "    }," >> "$METRICS_FILE"
      fi
      
      # CPU 정보 처리
      cpu_clean=$(echo "$cpu" | sed 's/%//')
      
      # 네트워크 정보 처리
      net_parts=(${net//\// })
      rx=${net_parts[0]}
      tx=${net_parts[1]}
      
      echo "    {" >> "$METRICS_FILE"
      echo "      \"name\": \"$name\"," >> "$METRICS_FILE"
      echo "      \"cpu\": $cpu_clean," >> "$METRICS_FILE"
      echo "      \"mem\": \"$mem\"," >> "$METRICS_FILE"
      echo "      \"mem_pct\": $(echo "$mem_pct" | sed 's/%//')," >> "$METRICS_FILE"
      echo "      \"net_rx\": \"$rx\"," >> "$METRICS_FILE"
      echo "      \"net_tx\": \"$tx\"" >> "$METRICS_FILE"
      
      node_count=$((node_count + 1))
    done <<< "$docker_stats"
    
    if [ $node_count -gt 0 ]; then
      echo "    }" >> "$METRICS_FILE"
    fi
    
    echo "  ]" >> "$METRICS_FILE"
    echo "}" >> "$METRICS_FILE"
  else
    # Docker가 없는 경우
    echo "{" > "$METRICS_FILE"
    echo "  \"timestamp\": \"$timestamp\"," >> "$METRICS_FILE"
    echo "  \"server_id\": \"$SERVER_ID\"," >> "$METRICS_FILE"
    echo "  \"system\": {" >> "$METRICS_FILE"
    echo "    \"model\": \"$model\"," >> "$METRICS_FILE"
    echo "    \"cpu_usage\": {" >> "$METRICS_FILE"
    echo "      \"user\": $user_cpu," >> "$METRICS_FILE"
    echo "      \"system\": $sys_cpu," >> "$METRICS_FILE"
    echo "      \"idle\": $idle_cpu" >> "$METRICS_FILE"
    echo "    }," >> "$METRICS_FILE"
    echo "    \"disk\": {" >> "$METRICS_FILE"
    echo "      \"total\": \"$disk_total\"," >> "$METRICS_FILE"
    echo "      \"used\": \"$disk_used\"," >> "$METRICS_FILE"
    echo "      \"available\": \"$disk_avail\"," >> "$METRICS_FILE"
    echo "      \"percent\": $disk_percent" >> "$METRICS_FILE"
    echo "    }" >> "$METRICS_FILE"
    echo "  }," >> "$METRICS_FILE"
    echo "  \"docker\": {" >> "$METRICS_FILE"
    echo "    \"running\": false," >> "$METRICS_FILE"
    echo "    \"message\": \"Docker가 실행 중이 아니거나 액세스할 수 없습니다.\"" >> "$METRICS_FILE"
    echo "  }" >> "$METRICS_FILE"
    echo "}" >> "$METRICS_FILE"
  fi
  
  echo "메트릭 수집 완료" >&2
}

# 중앙 서버로 데이터 전송
send_metrics() {
  if [ ! -f "$METRICS_FILE" ]; then
    echo -e "${RED}오류: 메트릭 파일을 찾을 수 없습니다.${NC}"
    return 1
  fi
  
  echo -e "${BLUE}중앙 서버로 데이터 전송 중...${NC}"
  
  # curl을 사용해 데이터 전송
  RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d @"$METRICS_FILE" \
    "$CENTRAL_SERVER/api/metrics")
  
  # 응답 확인
  if [[ "$RESPONSE" == *"success"* ]]; then
    echo -e "${GREEN}데이터 전송 성공${NC}"
    return 0
  else
    echo -e "${RED}데이터 전송 실패: $RESPONSE${NC}"
    return 1
  fi
}

# 오류 로깅
log_error() {
  local message="$1"
  local log_file="$TEMP_DIR/error.log"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $message" >> "$log_file"
  echo -e "${RED}오류: $message${NC}" >&2
}

# 재시도 함수
retry_with_backoff() {
  local max_attempts=5
  local timeout=1
  local attempt=1
  local exit_code=0

  while [[ $attempt -le $max_attempts ]]; do
    "$@"
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
      break
    fi

    echo -e "${YELLOW}시도 $attempt/$max_attempts 실패. ${timeout}초 후 재시도...${NC}" >&2
    sleep $timeout
    
    # 백오프 시간 증가 (지수 백오프)
    timeout=$((timeout * 2))
    attempt=$((attempt + 1))
  done

  if [[ $exit_code -ne 0 ]]; then
    log_error "최대 재시도 횟수 초과. 작업 실패."
  fi

  return $exit_code
}

# 메인 루프
main_loop() {
  while true; do
    # 메트릭 수집
    if ! collect_metrics; then
      log_error "메트릭 수집 실패"
    fi
    
    # 중앙 서버로 전송 (재시도 로직 포함)
    retry_with_backoff send_metrics
    
    # 다음 실행까지 대기
    sleep $INTERVAL
  done
}

# 종료 시 정리
cleanup() {
  echo -e "${YELLOW}클라이언트 종료 중...${NC}"
  # 필요한 정리 작업 수행
  exit 0
}

# 시그널 핸들러 등록
trap cleanup SIGINT SIGTERM

# 메인 루프 시작
main_loop