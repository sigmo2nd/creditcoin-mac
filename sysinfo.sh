#!/bin/bash
# sysinfo.sh - Creditcoin 노드 시스템 모니터링 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 옵션 파싱
MONITOR_MODE=false
JSON_OUTPUT=false
INTERVAL=2  # 모니터링 모드 기본 갱신 간격(초)

# 도움말 표시 함수
show_help() {
  echo "사용법: sysinfo [옵션]"
  echo ""
  echo "옵션:"
  echo "  -m, --monitor [초]   모니터링 모드로 실행 (기본 간격: 2초)"
  echo "  -j, --json           JSON 형식으로 출력 (API/스크립트용)"
  echo "  -h, --help           이 도움말 표시"
  echo ""
  echo "예시:"
  echo "  sysinfo              현재 시스템 상태 한 번 표시"
  echo "  sysinfo -m           2초마다 업데이트되는 모니터링 모드"
  echo "  sysinfo -m 5         5초마다 업데이트되는 모니터링 모드"
  echo "  sysinfo -j           JSON 형식으로 출력 (API/스크립트용)"
}

# 인자 처리
while [ $# -gt 0 ]; do
  case "$1" in
    -m|--monitor)
      MONITOR_MODE=true
      if [[ "$2" =~ ^[0-9]+$ ]]; then
        INTERVAL="$2"
        shift
      fi
      ;;
    -j|--json)
      JSON_OUTPUT=true
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo -e "${RED}오류: 알 수 없는 옵션: $1${NC}"
      show_help
      exit 1
      ;;
  esac
  shift
done

# JSON 출력과 모니터링 모드 동시 사용 불가
if [ "$MONITOR_MODE" = true ] && [ "$JSON_OUTPUT" = true ]; then
  echo -e "${RED}오류: 모니터링 모드(-m)와 JSON 출력(-j)은 동시에 사용할 수 없습니다.${NC}"
  exit 1
fi

# 데이터 수집 함수
collect_data() {
  # 시스템 정보 수집
  MODEL=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Model Name" | awk -F ": " '{print $2}' || echo "Unknown")
  CHIP=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Chip" | awk -F ": " '{print $2}' || echo "Unknown")
  
  # 성능/효율 코어 확인
  PERF_CORES=$(sysctl hw.perflevel0.logicalcpu 2>/dev/null | awk '{print $2}' || echo "0")
  EFF_CORES=$(sysctl hw.perflevel1.logicalcpu 2>/dev/null | awk '{print $2}' || echo "0")
  TOTAL_CORES=$(sysctl hw.ncpu 2>/dev/null | awk '{print $2}' || echo "0")
  
  # 시스템 메모리
  TOTAL_MEM_BYTES=$(sysctl hw.memsize 2>/dev/null | awk '{print $2}' || echo "0")
  TOTAL_MEM_GB=$(echo "scale=1; $TOTAL_MEM_BYTES / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "0")
  
  # CPU 사용량
  CPU_USAGE=$(top -l 1 | grep -E "^CPU" | grep -o "[0-9\.]+%")
  USER_CPU=$(echo "$CPU_USAGE" | awk 'NR==1{print $1}' | sed 's/%//')
  SYS_CPU=$(echo "$CPU_USAGE" | awk 'NR==2{print $1}' | sed 's/%//')
  IDLE_CPU=$(echo "$CPU_USAGE" | awk 'NR==3{print $1}' | sed 's/%//')
  
  # 대체 방법 (위 방법이 실패한 경우)
  if [ -z "$USER_CPU" ] || [ -z "$SYS_CPU" ] || [ -z "$IDLE_CPU" ]; then
    CPU_LINE=$(top -l 1 | grep -E "^CPU")
    USER_CPU=$(echo "$CPU_LINE" | grep -o "[0-9\.]+% user" | sed 's/% user//')
    SYS_CPU=$(echo "$CPU_LINE" | grep -o "[0-9\.]+% sys" | sed 's/% sys//')
    IDLE_CPU=$(echo "$CPU_LINE" | grep -o "[0-9\.]+% idle" | sed 's/% idle//')
  fi
  
  # 디스크 정보
  DISK_INFO=$(df -h / 2>/dev/null | tail -1)
  DISK_TOTAL=$(echo "$DISK_INFO" | awk '{print $2}')
  DISK_USED=$(echo "$DISK_INFO" | awk '{print $3}')
  DISK_AVAIL=$(echo "$DISK_INFO" | awk '{print $4}')
  DISK_PERCENT=$(echo "$DISK_INFO" | awk '{print $5}' | sed 's/%//')
  
  # Docker 정보 수집
  if command -v docker &> /dev/null; then
    # Docker 실행 확인
    if ! docker info &> /dev/null; then
      DOCKER_RUNNING=false
    else
      DOCKER_RUNNING=true
      DOCKER_STATS=$(docker stats --no-stream 2>/dev/null)
      
      # Docker 컨테이너 정보 추출
      NODES_DATA=""
      TOTAL_CPU=0
      TOTAL_CPU_TOTAL=0
      TOTAL_MEM_MIB=0
      TOTAL_NET_RX=0
      TOTAL_NET_TX=0
      
      # 노드 컨테이너 목록 가져오기
      NODES=$(echo "$DOCKER_STATS" | grep -E "3node|node" | awk '{print $2}')
      
      # 각 노드별 정보 수집
      for NODE in $NODES; do
        NODE_LINE=$(echo "$DOCKER_STATS" | grep "$NODE")
        
        # CPU 정보
        NODE_CPU=$(echo "$NODE_LINE" | awk '{print $3}' | sed 's/%//')
        NODE_CPU_TOTAL=$(echo "scale=2; $NODE_CPU / $TOTAL_CORES" | bc 2>/dev/null || echo "0")
        TOTAL_CPU=$(echo "scale=2; $TOTAL_CPU + $NODE_CPU" | bc 2>/dev/null || echo "0")
        TOTAL_CPU_TOTAL=$(echo "scale=2; $TOTAL_CPU_TOTAL + $NODE_CPU_TOTAL" | bc 2>/dev/null || echo "0")
        
        # 메모리 정보
        NODE_MEM=$(echo "$NODE_LINE" | awk '{print $4}')
        NODE_MEM_PCT=$(echo "$NODE_LINE" | awk '{print $6}' | sed 's/%//')
        NODE_MEM_MIB=$(echo "$NODE_MEM" | grep -o "[0-9\.]\+" || echo "0")
        TOTAL_MEM_MIB=$(echo "scale=1; $TOTAL_MEM_MIB + $NODE_MEM_MIB" | bc 2>/dev/null || echo "0")
        
        # 네트워크 정보
        NODE_NET_RX=$(echo "$NODE_LINE" | awk '{print $7}')
        NODE_NET_TX=$(echo "$NODE_LINE" | awk '{print $9}')
        NODE_NET_RX_MB=$(echo "$NODE_NET_RX" | grep -o "[0-9\.]\+" || echo "0")
        NODE_NET_TX_MB=$(echo "$NODE_NET_TX" | grep -o "[0-9\.]\+" || echo "0")
        
        # 컨테이너별 정보 저장
        if [ -z "$NODES_DATA" ]; then
          NODES_DATA="{\"name\":\"$NODE\",\"cpu\":$NODE_CPU,\"cpu_total\":$NODE_CPU_TOTAL,\"mem\":\"$NODE_MEM\",\"mem_pct\":$NODE_MEM_PCT,\"net_rx\":\"$NODE_NET_RX\",\"net_tx\":\"$NODE_NET_TX\"}"
        else
          NODES_DATA="$NODES_DATA,{\"name\":\"$NODE\",\"cpu\":$NODE_CPU,\"cpu_total\":$NODE_CPU_TOTAL,\"mem\":\"$NODE_MEM\",\"mem_pct\":$NODE_MEM_PCT,\"net_rx\":\"$NODE_NET_RX\",\"net_tx\":\"$NODE_NET_TX\"}"
        fi
        
        # 네트워크 총합 계산
        if [[ "$NODE_NET_RX" == *"MB"* ]]; then
          TOTAL_NET_RX=$(echo "scale=1; $TOTAL_NET_RX + $NODE_NET_RX_MB" | bc 2>/dev/null || echo "0")
        elif [[ "$NODE_NET_RX" == *"kB"* ]]; then
          NET_RX_MB=$(echo "scale=3; $NODE_NET_RX_MB / 1024" | bc 2>/dev/null || echo "0")
          TOTAL_NET_RX=$(echo "scale=1; $TOTAL_NET_RX + $NET_RX_MB" | bc 2>/dev/null || echo "0")
        fi
        
        if [[ "$NODE_NET_TX" == *"MB"* ]]; then
          TOTAL_NET_TX=$(echo "scale=1; $TOTAL_NET_TX + $NODE_NET_TX_MB" | bc 2>/dev/null || echo "0")
        elif [[ "$NODE_NET_TX" == *"kB"* ]]; then
          NET_TX_MB=$(echo "scale=3; $NODE_NET_TX_MB / 1024" | bc 2>/dev/null || echo "0")
          TOTAL_NET_TX=$(echo "scale=1; $TOTAL_NET_TX + $NET_TX_MB" | bc 2>/dev/null || echo "0")
        fi
      done
      
      # 메모리 GiB 계산
      TOTAL_MEM_GIB=$(echo "scale=1; $TOTAL_MEM_MIB / 1024" | bc 2>/dev/null || echo "0")
      MEM_PCT=$(echo "scale=1; 100 * $TOTAL_MEM_MIB / (1024 * $TOTAL_MEM_GB)" | bc 2>/dev/null || echo "0")
    fi
  else
    DOCKER_RUNNING=false
  fi
  
  # 데이터 구성
  if [ "$JSON_OUTPUT" = true ]; then
    # JSON 형식 출력
    echo "{"
    echo "  \"timestamp\": \"$(date +"%Y-%m-%d %H:%M:%S")\"," 
    echo "  \"system\": {"
    echo "    \"model\": \"$MODEL\","
    echo "    \"chip\": \"$CHIP\","
    echo "    \"cores\": {"
    echo "      \"total\": $TOTAL_CORES,"
    echo "      \"performance\": $PERF_CORES,"
    echo "      \"efficiency\": $EFF_CORES"
    echo "    },"
    echo "    \"cpu_usage\": {"
    echo "      \"user\": $USER_CPU,"
    echo "      \"system\": $SYS_CPU,"
    echo "      \"idle\": $IDLE_CPU"
    echo "    },"
    echo "    \"memory\": \"$TOTAL_MEM_GB GiB\","
    echo "    \"disk\": {"
    echo "      \"total\": \"$DISK_TOTAL\","
    echo "      \"used\": \"$DISK_USED\","
    echo "      \"available\": \"$DISK_AVAIL\","
    echo "      \"percent\": $DISK_PERCENT"
    echo "    }"
    echo "  },"
    
    if [ "$DOCKER_RUNNING" = true ]; then
      echo "  \"nodes\": [$NODES_DATA],"
      echo "  \"totals\": {"
      echo "    \"cpu\": $TOTAL_CPU,"
      echo "    \"cpu_total\": $TOTAL_CPU_TOTAL,"
      echo "    \"mem\": \"$TOTAL_MEM_GIB GiB\","
      echo "    \"mem_pct\": $MEM_PCT,"
      echo "    \"net_rx\": \"$TOTAL_NET_RX MB\","
      echo "    \"net_tx\": \"$TOTAL_NET_TX MB\""
      echo "  }"
    else
      echo "  \"docker\": {"
      echo "    \"running\": false,"
      echo "    \"message\": \"Docker가 실행 중이 아니거나 액세스할 수 없습니다.\""
      echo "  }"
    fi
    
    echo "}"
  else
    # 일반 텍스트 형식 출력 (데이터를 분리된 형태로 반환)
    local DATA=""
    DATA+="TIMESTAMP:$(date +"%Y-%m-%d %H:%M:%S")\n"
    DATA+="MODEL:$MODEL\n"
    DATA+="CHIP:$CHIP\n"
    DATA+="TOTAL_CORES:$TOTAL_CORES\n"
    DATA+="PERF_CORES:$PERF_CORES\n"
    DATA+="EFF_CORES:$EFF_CORES\n"
    DATA+="USER_CPU:$USER_CPU\n"
    DATA+="SYS_CPU:$SYS_CPU\n"
    DATA+="IDLE_CPU:$IDLE_CPU\n"
    DATA+="TOTAL_MEM_GB:$TOTAL_MEM_GB\n"
    DATA+="DISK_TOTAL:$DISK_TOTAL\n"
    DATA+="DISK_USED:$DISK_USED\n"
    DATA+="DISK_AVAIL:$DISK_AVAIL\n"
    DATA+="DISK_PERCENT:$DISK_PERCENT\n"
    
    if [ "$DOCKER_RUNNING" = true ]; then
      DATA+="DOCKER_RUNNING:true\n"
      DATA+="TOTAL_CPU:$TOTAL_CPU\n"
      DATA+="TOTAL_CPU_TOTAL:$TOTAL_CPU_TOTAL\n"
      DATA+="TOTAL_MEM_GIB:$TOTAL_MEM_GIB\n"
      DATA+="MEM_PCT:$MEM_PCT\n"
      DATA+="TOTAL_NET_RX:$TOTAL_NET_RX\n"
      DATA+="TOTAL_NET_TX:$TOTAL_NET_TX\n"
      
      # 노드 데이터 추가
      for NODE in $NODES; do
        NODE_LINE=$(echo "$DOCKER_STATS" | grep "$NODE")
        NODE_CPU=$(echo "$NODE_LINE" | awk '{print $3}' | sed 's/%//')
        NODE_CPU_TOTAL=$(echo "scale=2; $NODE_CPU / $TOTAL_CORES" | bc 2>/dev/null || echo "0")
        NODE_MEM=$(echo "$NODE_LINE" | awk '{print $4}')
        NODE_MEM_PCT=$(echo "$NODE_LINE" | awk '{print $6}' | sed 's/%//')
        NODE_NET_RX=$(echo "$NODE_LINE" | awk '{print $7}')
        NODE_NET_TX=$(echo "$NODE_LINE" | awk '{print $9}')
        
        DATA+="NODE_NAME:$NODE\n"
        DATA+="NODE_CPU:$NODE_CPU\n"
        DATA+="NODE_CPU_TOTAL:$NODE_CPU_TOTAL\n"
        DATA+="NODE_MEM:$NODE_MEM\n"
        DATA+="NODE_MEM_PCT:$NODE_MEM_PCT\n"
        DATA+="NODE_NET_RX:$NODE_NET_RX\n"
        DATA+="NODE_NET_TX:$NODE_NET_TX\n"
      done
    else
      DATA+="DOCKER_RUNNING:false\n"
    fi
    
    echo -e "$DATA"
  fi
}

# 출력 형식화 함수
format_output() {
  local DATA="$1"
  
  # 변수 파싱
  local TIMESTAMP=$(echo "$DATA" | grep "^TIMESTAMP:" | cut -d':' -f2-)
  local MODEL=$(echo "$DATA" | grep "^MODEL:" | cut -d':' -f2-)
  local CHIP=$(echo "$DATA" | grep "^CHIP:" | cut -d':' -f2-)
  local TOTAL_CORES=$(echo "$DATA" | grep "^TOTAL_CORES:" | cut -d':' -f2-)
  local PERF_CORES=$(echo "$DATA" | grep "^PERF_CORES:" | cut -d':' -f2-)
  local EFF_CORES=$(echo "$DATA" | grep "^EFF_CORES:" | cut -d':' -f2-)
  local USER_CPU=$(echo "$DATA" | grep "^USER_CPU:" | cut -d':' -f2-)
  local SYS_CPU=$(echo "$DATA" | grep "^SYS_CPU:" | cut -d':' -f2-)
  local IDLE_CPU=$(echo "$DATA" | grep "^IDLE_CPU:" | cut -d':' -f2-)
  local TOTAL_MEM_GB=$(echo "$DATA" | grep "^TOTAL_MEM_GB:" | cut -d':' -f2-)
  local DISK_TOTAL=$(echo "$DATA" | grep "^DISK_TOTAL:" | cut -d':' -f2-)
  local DISK_USED=$(echo "$DATA" | grep "^DISK_USED:" | cut -d':' -f2-)
  local DISK_AVAIL=$(echo "$DATA" | grep "^DISK_AVAIL:" | cut -d':' -f2-)
  local DISK_PERCENT=$(echo "$DATA" | grep "^DISK_PERCENT:" | cut -d':' -f2-)
  local DOCKER_RUNNING=$(echo "$DATA" | grep "^DOCKER_RUNNING:" | cut -d':' -f2-)
  
  # Docker 관련 정보
  local TOTAL_CPU=$(echo "$DATA" | grep "^TOTAL_CPU:" | cut -d':' -f2-)
  local TOTAL_CPU_TOTAL=$(echo "$DATA" | grep "^TOTAL_CPU_TOTAL:" | cut -d':' -f2-)
  local TOTAL_MEM_GIB=$(echo "$DATA" | grep "^TOTAL_MEM_GIB:" | cut -d':' -f2-)
  local MEM_PCT=$(echo "$DATA" | grep "^MEM_PCT:" | cut -d':' -f2-)
  local TOTAL_NET_RX=$(echo "$DATA" | grep "^TOTAL_NET_RX:" | cut -d':' -f2-)
  local TOTAL_NET_TX=$(echo "$DATA" | grep "^TOTAL_NET_TX:" | cut -d':' -f2-)
  
  # 출력 헤더
  echo -e "${BLUE}CREDITCOIN NODE RESOURCE MONITOR                                  ${TIMESTAMP}${NC}"
  echo ""
  
  # Docker가 실행 중이 아닌 경우
  if [ "$DOCKER_RUNNING" != "true" ]; then
    echo -e "${RED}Docker가 실행 중이 아니거나 액세스할 수 없습니다.${NC}"
    echo ""
    
    # 시스템 정보만 표시
    echo -e "${BLUE}SYSTEM INFORMATION:${NC}"
    echo -e "- ${YELLOW}MODEL:${NC} $MODEL ($CHIP)"
    echo -e "- ${YELLOW}CPU CORES:${NC} $TOTAL_CORES (${PERF_CORES} Performance, ${EFF_CORES} Efficiency)"
    echo -e "- ${YELLOW}CPU USAGE:${NC} 사용자 ${USER_CPU}%, 시스템 ${SYS_CPU}%, 유휴 ${IDLE_CPU}%"
    echo -e "- ${YELLOW}MEMORY:${NC} ${TOTAL_MEM_GB} GiB 총량"
    echo -e "- ${YELLOW}DISK:${NC} ${DISK_USED}/${DISK_TOTAL} (${DISK_PERCENT}% 사용)"
    return
  fi
  
  # 헤더 출력
  printf "%-10s %-8s %-10s %-13s %-8s %-15s\n" "NODE" "CPU%" "OF TOTAL%" "MEM USAGE" "MEM%" "NET RX/TX"
  
  # 노드 데이터 추출
  local NODE_COUNT=$(echo "$DATA" | grep "^NODE_NAME:" | wc -l)
  
  for i in $(seq 1 $NODE_COUNT); do
    local NODE_LINES=$(echo "$DATA" | grep -A6 "^NODE_NAME:" | grep -m$i -A6 "NODE_NAME:" | tail -7)
    local NODE_NAME=$(echo "$NODE_LINES" | grep "^NODE_NAME:" | cut -d':' -f2-)
    local NODE_CPU=$(echo "$NODE_LINES" | grep "^NODE_CPU:" | cut -d':' -f2-)
    local NODE_CPU_TOTAL=$(echo "$NODE_LINES" | grep "^NODE_CPU_TOTAL:" | cut -d':' -f2-)
    local NODE_MEM=$(echo "$NODE_LINES" | grep "^NODE_MEM:" | cut -d':' -f2-)
    local NODE_MEM_PCT=$(echo "$NODE_LINES" | grep "^NODE_MEM_PCT:" | cut -d':' -f2-)
    local NODE_NET_RX=$(echo "$NODE_LINES" | grep "^NODE_NET_RX:" | cut -d':' -f2-)
    local NODE_NET_TX=$(echo "$NODE_LINES" | grep "^NODE_NET_TX:" | cut -d':' -f2-)
    
    printf "%-10s %-8s %-10s %-13s %-8s %-15s\n" "$NODE_NAME" "$NODE_CPU%" "$NODE_CPU_TOTAL%" "$NODE_MEM" "$NODE_MEM_PCT%" "${NODE_NET_RX}/${NODE_NET_TX}"
  done
  
  # 구분선
  printf "%-10s %-8s %-10s %-13s %-8s %-15s\n" "----------" "--------" "----------" "-------------" "--------" "---------------"
  
  # 총계 출력
  printf "%-10s %-8s %-10s %-13s %-8s %-15s\n" "TOTAL" "$TOTAL_CPU%" "$TOTAL_CPU_TOTAL%" "$TOTAL_MEM_GIB GiB" "${MEM_PCT}%" "${TOTAL_NET_RX}MB/${TOTAL_NET_TX}MB"
  
  # 시스템 정보 출력
  echo ""
  echo -e "${BLUE}SYSTEM INFORMATION:${NC}"
  echo -e "- ${YELLOW}MODEL:${NC} $MODEL ($CHIP)"
  echo -e "- ${YELLOW}CPU CORES:${NC} $TOTAL_CORES (${PERF_CORES} Performance, ${EFF_CORES} Efficiency)"
  echo -e "- ${YELLOW}CPU USAGE:${NC} 사용자 ${USER_CPU}%, 시스템 ${SYS_CPU}%, 유휠 ${IDLE_CPU}%"
  echo -e "- ${YELLOW}MEMORY:${NC} ${TOTAL_MEM_GB} GiB 총량"
  echo -e "- ${YELLOW}DISK:${NC} ${DISK_USED}/${DISK_TOTAL} (${DISK_PERCENT}% 사용)"
}

# 단일 출력 모드
single_output() {
  local DATA=$(collect_data)
  
  if [ "$JSON_OUTPUT" = true ]; then
    echo "$DATA"
  else
    format_output "$DATA"
  fi
}

# 모니터링 모드
monitor_mode() {
  local INTERVAL=$1
  
  # 터미널 설정 백업
  local old_tty_settings
  old_tty_settings=$(stty -g)
  
  # 화면 지우기
  clear
  
  # 화면 고정을 위한 설정
  echo -e "${BLUE}모니터링 모드 (${INTERVAL}초마다 갱신) - 종료하려면 Ctrl+C를 누르세요${NC}"
  
  # Ctrl+C 시그널 핸들러 설정
  trap 'echo; echo "모니터링을 종료합니다."; stty $old_tty_settings; exit 0' INT
  
  # 커서 숨기기
  echo -en "\033[?25l"
  
  # 무한 루프 (Ctrl+C로 종료 가능)
  while true; do
    # 커서를 화면 상단으로 이동 (깜빡임 방지)
    echo -en "\033[H"
    
    # 내용 출력 (화면 지우기 없이)
    local DATA=$(collect_data)
    
    if [ "$JSON_OUTPUT" = true ]; then
      echo "$DATA"
    else
      echo -e "${BLUE}CREDITCOIN NODE RESOURCE MONITOR                                  $(date +"%Y-%m-%d %H:%M:%S")${NC}\n"
      format_output "$DATA"
      
      # 맨 아래에 안내 메시지
      rows=$(tput lines)
      cols=$(tput cols)
      
      # 커서를 마지막 줄로 이동
      echo -en "\033[${rows};0H"
      echo -e "${BLUE}모니터링 모드 (${INTERVAL}초마다 갱신) - 종료하려면 Ctrl+C를 누르세요${NC}"
    fi
    
    # 대기
    sleep "$INTERVAL"
  done
  
  # 정상 종료되지 않은 경우를 대비한 리셋
  stty $old_tty_settings
  echo -en "\033[?25h" # 커서 표시
}

# 메인 함수
main() {
  # 실행 모드에 따라 분기
  if [ "$MONITOR_MODE" = true ]; then
    monitor_mode "$INTERVAL"
  else
    single_output
  fi
}

# 스크립트 실행
main