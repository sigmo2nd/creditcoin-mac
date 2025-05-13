#!/bin/bash
# sysinfo.sh - 최적화된 Creditcoin 노드 시스템 모니터링 스크립트

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

# 시스템 정보 캐싱 (한 번만 수집)
get_system_info() {
  # 모델 정보
  MODEL=$(sysctl hw.model 2>/dev/null | awk -F ": " '{print $2}' || echo "Unknown")
  
  # 칩 정보 (Apple Silicon인 경우)
  if [[ "$MODEL" == *"Mac"* ]]; then
    CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
  else
    # system_profiler는 실행 시간이 오래 걸리므로 Apple Silicon에만 사용
    CHIP=$(uname -p 2>/dev/null || echo "Unknown")
  fi
  
  # 코어 정보
  TOTAL_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo "0")
  PERF_CORES=$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || echo "0")
  EFF_CORES=$(sysctl -n hw.perflevel1.logicalcpu 2>/dev/null || echo "0")
  
  # 코어 정보가 검색되지 않는 경우 (인텔 Mac)
  if [ "$PERF_CORES" = "0" ] || [ "$EFF_CORES" = "0" ]; then
    PERF_CORES=$TOTAL_CORES
    EFF_CORES=0
  fi
  
  # 메모리 크기
  TOTAL_MEM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
  TOTAL_MEM_GB=$(awk "BEGIN {printf \"%.1f\", $TOTAL_MEM_BYTES / 1024 / 1024 / 1024}")
}

# 동적 시스템 정보 수집 (매 갱신마다)
get_dynamic_info() {
  # CPU 사용률 (top 명령을 한 번만 실행)
  TOP_INFO=$(top -l 1 -n 0)
  CPU_LINE=$(echo "$TOP_INFO" | grep -E "^CPU")
  USER_CPU=$(echo "$CPU_LINE" | awk '{gsub(/%/, "", $3); print $3}')
  SYS_CPU=$(echo "$CPU_LINE" | awk '{gsub(/%/, "", $5); print $5}')
  IDLE_CPU=$(echo "$CPU_LINE" | awk '{gsub(/%/, "", $7); print $7}')
  
  # 디스크 정보
  DISK_INFO=$(df -h / 2>/dev/null | grep -v "Filesystem" | head -1)
  DISK_TOTAL=$(echo "$DISK_INFO" | awk '{print $2}')
  DISK_USED=$(echo "$DISK_INFO" | awk '{print $3}')
  DISK_AVAIL=$(echo "$DISK_INFO" | awk '{print $4}')
  DISK_PERCENT=$(echo "$DISK_INFO" | awk '{gsub(/%/, "", $5); print $5}')
  
  # Docker 정보 (간소화된 형식)
  if command -v docker &> /dev/null && docker info &> /dev/null; then
    DOCKER_RUNNING=true
    
    # 효율적인 Docker stats 형식 (필요한 정보만 가져옴)
    DOCKER_STATS=$(docker stats --no-stream --format "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}" 2>/dev/null | grep -E "node|3node")
    
    # 빠른 파싱을 위해 노드 정보 배열 생성
    NODE_NAMES=()
    NODE_CPU=()
    NODE_CPU_TOTAL=()
    NODE_MEM=()
    NODE_MEM_PCT=()
    NODE_NET_RX=()
    NODE_NET_TX=()
    
    # 총계 초기화
    TOTAL_CPU=0
    TOTAL_CPU_TOTAL=0
    TOTAL_MEM_MIB=0
    TOTAL_MEM_GIB=0
    TOTAL_NET_RX=0
    TOTAL_NET_TX=0
    
    # 행 단위로 파싱
    while IFS=$'\t' read -r name cpu mem mem_pct net; do
      # 이름 저장
      NODE_NAMES+=("$name")
      
      # CPU 정보 파싱
      cpu_value=${cpu/\%/}
      NODE_CPU+=("$cpu_value")
      cpu_total=$(awk "BEGIN {printf \"%.2f\", $cpu_value / $TOTAL_CORES}")
      NODE_CPU_TOTAL+=("$cpu_total")
      TOTAL_CPU=$(awk "BEGIN {printf \"%.2f\", $TOTAL_CPU + $cpu_value}")
      TOTAL_CPU_TOTAL=$(awk "BEGIN {printf \"%.2f\", $TOTAL_CPU_TOTAL + $cpu_total}")
      
      # 메모리 정보 파싱
      mem_value=$(echo "$mem" | awk '{split($1,a,"iB"); gsub(/[^0-9.]/, "", a[1]); print a[1]}')
      mem_unit=$(echo "$mem" | awk '{split($1,a,"iB"); print a[2]}')
      NODE_MEM+=("$mem_value$mem_unit")
      
      # MiB로 변환하여 합산
      if [[ "$mem_unit" == "G" ]]; then
        mem_mib=$(awk "BEGIN {printf \"%.1f\", $mem_value * 1024}")
      else
        mem_mib=$mem_value
      fi
      TOTAL_MEM_MIB=$(awk "BEGIN {printf \"%.1f\", $TOTAL_MEM_MIB + $mem_mib}")
      
      # 메모리 퍼센트
      NODE_MEM_PCT+=("${mem_pct/\%/}")
      
      # 네트워크 정보 파싱
      rx_tx=(${net//\// })
      rx=${rx_tx[0]}
      tx=${rx_tx[1]}
      
      # 단위 처리
      rx_value=$(echo "$rx" | awk '{gsub(/[^0-9.]/, "", $0); print $0}')
      rx_unit=$(echo "$rx" | awk '{gsub(/[0-9.]/, "", $0); print $0}')
      
      tx_value=$(echo "$tx" | awk '{gsub(/[^0-9.]/, "", $0); print $0}')
      tx_unit=$(echo "$tx" | awk '{gsub(/[0-9.]/, "", $0); print $0}')
      
      # MB로 변환
      if [[ "$rx_unit" == "kB" ]]; then
        rx_mb=$(awk "BEGIN {printf \"%.1f\", $rx_value / 1024}")
      elif [[ "$rx_unit" == "MB" ]]; then
        rx_mb=$rx_value
      elif [[ "$rx_unit" == "GB" ]]; then
        rx_mb=$(awk "BEGIN {printf \"%.1f\", $rx_value * 1024}")
      else
        rx_mb="0"
      fi
      
      if [[ "$tx_unit" == "kB" ]]; then
        tx_mb=$(awk "BEGIN {printf \"%.1f\", $tx_value / 1024}")
      elif [[ "$tx_unit" == "MB" ]]; then
        tx_mb=$tx_value
      elif [[ "$tx_unit" == "GB" ]]; then
        tx_mb=$(awk "BEGIN {printf \"%.1f\", $tx_value * 1024}")
      else
        tx_mb="0"
      fi
      
      NODE_NET_RX+=("$rx")
      NODE_NET_TX+=("$tx")
      
      TOTAL_NET_RX=$(awk "BEGIN {printf \"%.1f\", $TOTAL_NET_RX + $rx_mb}")
      TOTAL_NET_TX=$(awk "BEGIN {printf \"%.1f\", $TOTAL_NET_TX + $tx_mb}")
      
    done <<< "$DOCKER_STATS"
    
    # 총 노드 수 저장
    NODE_COUNT=${#NODE_NAMES[@]}
    
    # 메모리 합계를 GiB로 변환
    TOTAL_MEM_GIB=$(awk "BEGIN {printf \"%.1f\", $TOTAL_MEM_MIB / 1024}")
    
    # 시스템 메모리 대비 사용률
    MEM_PCT=$(awk "BEGIN {printf \"%.1f\", $TOTAL_MEM_MIB * 100 / ($TOTAL_MEM_GB * 1024)}")
  else
    DOCKER_RUNNING=false
  fi
}

# JSON 형식으로 출력
output_json() {
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
    echo "  \"nodes\": ["
    for i in $(seq 0 $((NODE_COUNT-1))); do
      echo "    {"
      echo "      \"name\": \"${NODE_NAMES[$i]}\","
      echo "      \"cpu\": ${NODE_CPU[$i]},"
      echo "      \"cpu_total\": ${NODE_CPU_TOTAL[$i]},"
      echo "      \"mem\": \"${NODE_MEM[$i]}\","
      echo "      \"mem_pct\": ${NODE_MEM_PCT[$i]},"
      echo "      \"net_rx\": \"${NODE_NET_RX[$i]}\","
      echo "      \"net_tx\": \"${NODE_NET_TX[$i]}\""
      if [ $i -eq $((NODE_COUNT-1)) ]; then
        echo "    }"
      else
        echo "    },"
      fi
    done
    echo "  ],"
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
}

# 텍스트 형식으로 출력
output_text() {
  # 출력 헤더
  echo -e "${BLUE}CREDITCOIN NODE RESOURCE MONITOR                                  $(date +"%Y-%m-%d %H:%M:%S")${NC}"
  echo ""
  
  # Docker가 실행 중이 아닌 경우
  if [ "$DOCKER_RUNNING" != "true" ]; then
    echo -e "${RED}Docker가 실행 중이 아니거나 액세스할 수 없습니다.${NC}"
    echo ""
  else
    # 헤더 출력
    printf "%-10s %-8s %-10s %-13s %-8s %-15s\n" "NODE" "CPU%" "OF TOTAL%" "MEM USAGE" "MEM%" "NET RX/TX"
    
    # 노드 데이터 출력
    for i in $(seq 0 $((NODE_COUNT-1))); do
      printf "%-10s %-8s %-10s %-13s %-8s %-15s\n" \
        "${NODE_NAMES[$i]}" \
        "${NODE_CPU[$i]}%" \
        "${NODE_CPU_TOTAL[$i]}%" \
        "${NODE_MEM[$i]}" \
        "${NODE_MEM_PCT[$i]}%" \
        "${NODE_NET_RX[$i]}/${NODE_NET_TX[$i]}"
    done
    
    # 구분선
    printf "%-10s %-8s %-10s %-13s %-8s %-15s\n" \
      "----------" "--------" "----------" "-------------" "--------" "---------------"
    
    # 총계 출력
    printf "%-10s %-8s %-10s %-13s %-8s %-15s\n" \
      "TOTAL" \
      "$TOTAL_CPU%" \
      "$TOTAL_CPU_TOTAL%" \
      "$TOTAL_MEM_GIB GiB" \
      "$MEM_PCT%" \
      "${TOTAL_NET_RX}MB/${TOTAL_NET_TX}MB"
  fi
  
  # 시스템 정보 출력
  echo ""
  echo -e "${BLUE}SYSTEM INFORMATION:${NC}"
  echo -e "- ${YELLOW}MODEL:${NC} $MODEL ($CHIP)"
  echo -e "- ${YELLOW}CPU CORES:${NC} $TOTAL_CORES (${PERF_CORES} Performance, ${EFF_CORES} Efficiency)"
  echo -e "- ${YELLOW}CPU USAGE:${NC} 사용자 ${USER_CPU}%, 시스템 ${SYS_CPU}%, 유휴 ${IDLE_CPU}%"
  echo -e "- ${YELLOW}MEMORY:${NC} ${TOTAL_MEM_GB} GiB 총량"
  echo -e "- ${YELLOW}DISK:${NC} ${DISK_USED}/${DISK_TOTAL} (${DISK_PERCENT}% 사용)"
}

# 단일 출력 모드
single_output() {
  # 시스템 정보 수집 (한 번만 실행)
  get_system_info
  
  # 동적 정보 수집
  get_dynamic_info
  
  # 출력 형식에 따라 표시
  if [ "$JSON_OUTPUT" = true ]; then
    output_json
  else
    output_text
  fi
}

# 모니터링 모드 (dstats 스타일)
monitor_mode() {
  local INTERVAL=$1
  
  # 시스템 정보 수집 (한 번만)
  get_system_info
  
  # 터미널 설정 백업
  local old_tty_settings
  old_tty_settings=$(stty -g)
  
  # 화면 지우기
  clear
  
  # Ctrl+C 시그널 핸들러 설정
  trap 'echo; echo "모니터링을 종료합니다."; stty $old_tty_settings; echo -en "\033[?25h"; exit 0' INT TERM
  
  # 커서 숨기기
  echo -en "\033[?25l"
  
  # dstats 스타일로 커서 위치를 고정해서 업데이트
  while true; do
    # 커서를 화면 상단으로 이동 (깜빡임 방지)
    echo -en "\033[H"
    
    # 동적 정보 수집
    get_dynamic_info
    
    # 출력 (화면 지우기 없이)
    if [ "$JSON_OUTPUT" = true ]; then
      output_json
    else
      output_text
      # 모니터링 메시지는 마지막에 한 번만 표시
      echo ""
      echo -e "${BLUE}모니터링 모드 (${INTERVAL}초마다 갱신) - 종료하려면 Ctrl+C를 누르세요${NC}"
    fi
    
    # 대기
    sleep "$INTERVAL"
  done
  
  # 정상 종료되지 않은 경우를 대비한 리셋
  stty $old_tty_settings
  echo -en "\033[?25h" # 커서 표시
}

# 메인 실행 코드
if [ "$MONITOR_MODE" = true ]; then
  monitor_mode "$INTERVAL"
else
  single_output
fi