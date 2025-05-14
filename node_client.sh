#!/bin/bash
# secure_node_client.sh - HTTPS 지원 크레딧코인 노드 메트릭 클라이언트

# 설정
CENTRAL_SERVER="https://서버IP:3000"  # HTTPS URL로 변경
API_TOKEN="j8fKq2p5X7zL9tR3v6yA"      # API 토큰
SERVER_ID="$(hostname | tr '.' '-')"  # 서버 식별자
INTERVAL=30                           # 전송 간격 (초)
TEMP_DIR="/tmp/creditcoin_metrics"    # 임시 데이터 저장 위치
METRICS_FILE="$TEMP_DIR/metrics.json" # 메트릭 데이터 파일
LOG_FILE="$TEMP_DIR/client.log"       # 로그 파일

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

# 로그 함수
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $2$1${NC}" >&2
}

# 정리 함수
cleanup() {
  log "프로세스 종료 중..." "$YELLOW"
  exit 0
}

# 시그널 핸들러 설정
trap cleanup SIGINT SIGTERM

# 이미 실행 중인 인스턴스 확인
SCRIPT_NAME=$(basename "$0")
if pgrep -f "$SCRIPT_NAME" | grep -v "$$" > /dev/null; then
  log "경고: 이미 다른 인스턴스가 실행 중입니다. 기존 프로세스를 종료합니다." "$YELLOW"
  pkill -f "$SCRIPT_NAME"
  sleep 1
fi

# 시작 메시지
log "크레딧코인 노드 메트릭 클라이언트 시작" "$BLUE"
log "중앙 서버: $CENTRAL_SERVER" "$YELLOW"
log "서버 ID: $SERVER_ID" "$YELLOW"
log "전송 간격: ${INTERVAL}초" "$YELLOW"

# 메트릭 수집 함수
collect_metrics() {
  log "시스템 메트릭 수집 중..." "$BLUE"
  
  # sysinfo.sh가 있으면 그대로 사용
  if command -v sysinfo.sh &> /dev/null; then
    sysinfo.sh -j > "$METRICS_FILE"
    return
  fi
  
  # ... (기존 메트릭 수집 코드)
  
  log "메트릭 수집 완료" "$GREEN"
}

# 중앙 서버로 데이터 전송
send_metrics() {
  if [ ! -f "$METRICS_FILE" ]; then
    log "오류: 메트릭 파일을 찾을 수 없습니다." "$RED"
    return 1
  fi
  
  log "중앙 서버로 데이터 전송 중..." "$BLUE"
  
  # HTTPS 지원 추가 (-k 옵션으로 인증서 검증 무시)
  RESPONSE=$(curl -s -k -m 10 -X POST \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d @"$METRICS_FILE" \
    "$CENTRAL_SERVER/api/metrics")
  
  # 응답 확인
  if [[ "$RESPONSE" == *"success"* ]]; then
    log "데이터 전송 성공" "$GREEN"
    return 0
  else
    log "데이터 전송 실패: $RESPONSE" "$RED"
    return 1
  fi
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

    log "시도 $attempt/$max_attempts 실패. ${timeout}초 후 재시도..." "$YELLOW"
    sleep $timeout
    
    # 백오프 시간 증가 (지수 백오프)
    timeout=$((timeout * 2))
    attempt=$((attempt + 1))
  done

  if [[ $exit_code -ne 0 ]]; then
    log "최대 재시도 횟수 초과. 작업 실패." "$RED"
  fi

  return $exit_code
}

# 메인 루프
while true; do
  # 메트릭 수집
  collect_metrics
  
  # 중앙 서버로 전송 (재시도 로직 포함)
  retry_with_backoff send_metrics
  
  # 다음 실행까지 대기
  sleep $INTERVAL
done