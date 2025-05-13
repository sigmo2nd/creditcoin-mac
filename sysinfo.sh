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
INTERVAL=0.5  # 모니터링 모드 기본 갱신 간격(초)

# 도움말 표시 함수
show_help() {
  echo "사용법: sysinfo [옵션]"
  echo ""
  echo "옵션:"
  echo "  -m, --monitor [초]   모니터링 모드로 실행 (기본 간격: 0.5초)"
  echo "  -j, --json           JSON 형식으로 출력 (API/스크립트용)"
  echo "  -h, --help           이 도움말 표시"
  echo ""
  echo "예시:"
  echo "  sysinfo              현재 시스템 상태 한 번 표시"
  echo "  sysinfo -m           0.5초마다 업데이트되는 모니터링 모드"
  echo "  sysinfo -m 5         5초마다 업데이트되는 모니터링 모드"
  echo "  sysinfo -j           JSON 형식으로 출력 (API/스크립트용)"
}

# 인자 처리
while [ $# -gt 0 ]; do
  case "$1" in
    -m|--monitor)
      MONITOR_MODE=true
      if [[ "$2" =~ ^[0-9.]+$ ]]; then
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

# 시스템 정보 수집
get_system_info() {
  # 모델 정보
  MODEL=$(sysctl hw.model 2>/dev/null | awk -F ": " '{print $2}' || echo "Unknown")
  
  # 칩 정보 (Apple Silicon인 경우)
  if [[ "$(uname -m)" == "arm64" ]]; then
    CHIP=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Chip" | awk -F ": " '{print $2}' || echo "Apple Silicon")
  else
    CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Intel")
  fi
  
  # 코어 정보
  TOTAL_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo "0")
  PERF_CORES=$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || echo "0")
  EFF_CORES=$(sysctl -n hw.perflevel1.logicalcpu 2>/dev/null || echo "0")
  
  # 코어 정보가 검색되지 않는 경우 (인텔 Mac)
  if [ "$PERF_CORES" = "0" ] && [ "$EFF_CORES" = "0" ]; then
    PERF_CORES=$TOTAL_CORES
    EFF_CORES=0
  fi
  
  # 메모리 크기
  TOTAL_MEM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
  TOTAL_MEM_GB=$(awk "BEGIN {printf \"%.1f\", $TOTAL_MEM_BYTES / 1024 / 1024 / 1024}")
}

# 단위 변환 함수 - GiB/MiB를 GB/MB로 통일
convert_to_decimal_unit() {
  local value=$1
  local binary_unit=$2
  local decimal_unit=$3
  
  # 예: 1 GiB = 1.074 GB, 1 MiB = 1.048576 MB
  local factor=0
  if [ "$binary_unit" = "GiB" ] && [ "$decimal_unit" = "GB" ]; then
    factor=1.074
  elif [ "$binary_unit" = "MiB" ] && [ "$decimal_unit" = "MB" ]; then
    factor=1.048576
  elif [ "$binary_unit" = "GiB" ] && [ "$decimal_unit" = "MB" ]; then
    factor=1099.511627776  # 1 GiB = 1099.511627776 MB
  else
    # 같은 단위거나 지원되지 않는 변환이면 그대로 반환
    echo "$value"
    return
  fi
  
  # 변환 수행
  local result=$(awk "BEGIN {printf \"%.2f\", $value * $factor}")
  echo "$result"
}

# 동적 시스템 정보 수집
get_dynamic_info() {
  # CPU 사용률 (top 명령을 한 번만 실행)
  TOP_INFO=$(top -l 1 -n 0)
  CPU_LINE=$(echo "$TOP_INFO" | grep -E "^CPU")
  USER_CPU=$(echo "$CPU_LINE" | awk '{print $3}' | sed 's/%//')
  SYS_CPU=$(echo "$CPU_LINE" | awk '{print $5}' | sed 's/%//')
  IDLE_CPU=$(echo "$CPU_LINE" | awk '{print $7}' | sed 's/%//')
  
  # VM 상태 정보 (메모리 사용량)
  VM_STAT=$(vm_stat)
  PAGE_SIZE=$(echo "$VM_STAT" | grep "page size" | awk '{print $8}')
  PAGES_FREE=$(echo "$VM_STAT" | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
  PAGES_ACTIVE=$(echo "$VM_STAT" | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
  PAGES_INACTIVE=$(echo "$VM_STAT" | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
  PAGES_SPECULATIVE=$(echo "$VM_STAT" | grep "Pages speculative" | awk '{print $3}' | sed 's/\.//')
  PAGES_WIRED=$(echo "$VM_STAT" | grep "Pages wired" | awk '{print $3}' | sed 's/\.//')
  
  # 메모리 사용량 계산 (GB)
  WIRED_MEMORY_GB=$(awk "BEGIN {printf \"%.1f\", $PAGES_WIRED * $PAGE_SIZE / 1024 / 1024 / 1024}")
  ACTIVE_MEMORY_GB=$(awk "BEGIN {printf \"%.1f\", $PAGES_ACTIVE * $PAGE_SIZE / 1024 / 1024 / 1024}")
  INACTIVE_MEMORY_GB=$(awk "BEGIN {printf \"%.1f\", $PAGES_INACTIVE * $PAGE_SIZE / 1024 / 1024 / 1024}")
  FREE_MEMORY_GB=$(awk "BEGIN {printf \"%.1f\", $PAGES_FREE * $PAGE_SIZE / 1024 / 1024 / 1024}")
  USED_MEMORY_GB=$(awk "BEGIN {printf \"%.1f\", ($PAGES_WIRED + $PAGES_ACTIVE + $PAGES_INACTIVE) * $PAGE_SIZE / 1024 / 1024 / 1024}")
  
  # 메모리 사용률 계산
  MEM_USAGE_PCT=$(awk "BEGIN {printf \"%.1f\", $USED_MEMORY_GB * 100 / $TOTAL_MEM_GB}")
  
  # 디스크 정보
  DISK_INFO=$(df -h / 2>/dev/null | grep -v "Filesystem" | head -1)
  DISK_TOTAL=$(echo "$DISK_INFO" | awk '{print $2}' | sed 's/Gi/GB/g')
  DISK_USED=$(echo "$DISK_INFO" | awk '{print $3}' | sed 's/Gi/GB/g')
  DISK_AVAIL=$(echo "$DISK_INFO" | awk '{print $4}' | sed 's/Gi/GB/g')
  DISK_PERCENT=$(echo "$DISK_INFO" | awk '{print $5}' | sed 's/%//')
  
  # Docker 정보
  if command -v docker &> /dev/null && docker info &> /dev/null; then
    DOCKER_RUNNING=true
    
    # Docker 컨테이너 정보 수집
    DOCKER_STATS=$(docker stats --no-stream --format "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}" 2>/dev/null | grep -E "node|3node")
    
    # 정보 저장용 배열
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
    TOTAL_MEM_GB=0
    TOTAL_NET_RX_MB=0
    TOTAL_NET_TX_MB=0
    
    # 컨테이너별 정보 파싱
    while IFS=$'\t' read -r name cpu mem mem_pct net; do
      # 배열에 이름 추가
      NODE_NAMES+=("$name")
      
      # CPU 정보 처리
      cpu_clean=$(echo "$cpu" | sed 's/%//')
      NODE_CPU+=("$cpu_clean")
      
      # CPU 총량 대비 사용률 계산
      cpu_total=$(awk "BEGIN {printf \"%.2f\", $cpu_clean / $TOTAL_CORES}")
      NODE_CPU_TOTAL+=("$cpu_total")
      
      # 총 CPU 사용량 합산
      TOTAL_CPU=$(awk "BEGIN {printf \"%.2f\", $TOTAL_CPU + $cpu_clean}")
      TOTAL_CPU_TOTAL=$(awk "BEGIN {printf \"%.2f\", $TOTAL_CPU_TOTAL + $cpu_total}")
      
      # 메모리 정보 처리 - GiB를 GB로 변환
      # 메모리 문자열 분리 (예: "4.854GiB / 58.81GiB")
      mem_used=$(echo "$mem" | awk '{print $1}')
      mem_used_num=$(echo "$mem_used" | sed 's/[A-Za-z]*//')
      mem_used_unit=$(echo "$mem_used" | sed 's/[0-9.]*//')
      
      # GiB를 GB로 변환
      if [[ "$mem_used_unit" == "GiB" ]]; then
        mem_used_gb=$(convert_to_decimal_unit "$mem_used_num" "GiB" "GB")
        mem_display="${mem_used_gb}GB"
      elif [[ "$mem_used_unit" == "MiB" ]]; then
        mem_used_mb=$(convert_to_decimal_unit "$mem_used_num" "MiB" "MB")
        mem_display="${mem_used_mb}MB"
      else
        mem_display="$mem_used"
      fi
      
      NODE_MEM+=("$mem_display")
      NODE_MEM_PCT+=("$(echo "$mem_pct" | sed 's/%//')")
      
      # 메모리 GB 단위로 변환하여 합산
      if [[ "$mem_used_unit" == "GiB" ]]; then
        # GiB를 GB로 변환
        mem_used_gb=$(convert_to_decimal_unit "$mem_used_num" "GiB" "GB")
        TOTAL_MEM_GB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_MEM_GB + $mem_used_gb}")
      elif [[ "$mem_used_unit" == "MiB" ]]; then
        # MiB를 GB로 변환
        mem_used_gb=$(awk "BEGIN {printf \"%.2f\", $mem_used_num / 1024 * 1.048576}")
        TOTAL_MEM_GB=$(awk "BEGIN {printf \"%.2f\", $TOTAL_MEM_GB + $mem_used_gb}")
      fi
      
      # 네트워크 정보 처리 - 모든 단위를 통일
      network=$(echo "$net" | tr '/' ' ')
      rx=$(echo "$network" | awk '{print $1}')
      tx=$(echo "$network" | awk '{print $2}')
      
      # 이미 단위가 포함된 경우
      NODE_NET_RX+=("$rx")
      NODE_NET_TX+=("$tx")
      
      # 네트워크 MB 단위로 통일해서 합산
      rx_value=$(echo "$rx" | sed 's/[^0-9.]//g')
      rx_unit=$(echo "$rx" | sed 's/[0-9.]//g')
      
      tx_value=$(echo "$tx" | sed 's/[^0-9.]//g')
      tx_unit=$(echo "$tx" | sed 's/[0-9.]//g')
      
      # 단위별로 MB로 변환
      case "$rx_unit" in
        "kB") rx_mb=$(awk "BEGIN {printf \"%.1f\", $rx_value / 1024}") ;;
        "MB") rx_mb=$rx_value ;;
        "GB") rx_mb=$(awk "BEGIN {printf \"%.1f\", $rx_value * 1024}") ;;
        *) rx_mb=0 ;;
      esac
      
      case "$tx_unit" in
        "kB") tx_mb=$(awk "BEGIN {printf \"%.1f\", $tx_value / 1024}") ;;
        "MB") tx_mb=$tx_value ;;
        "GB") tx_mb=$(awk "BEGIN {printf \"%.1f\", $tx_value * 1024}") ;;
        *) tx_mb=0 ;;
      esac
      
      # 총 네트워크 트래픽 합산
      TOTAL_NET_RX_MB=$(awk "BEGIN {printf \"%.1f\", $TOTAL_NET_RX_MB + $rx_mb}")
      TOTAL_NET_TX_MB=$(awk "BEGIN {printf \"%.1f\", $TOTAL_NET_TX_MB + $tx_mb}")
      
    done <<< "$DOCKER_STATS"
    
    # 총 노드 수
    NODE_COUNT=${#NODE_NAMES[@]}
    
    # 총 메모리 비율 계산
    NODE_MEM_PCT_TOTAL=$(awk "BEGIN {printf \"%.1f\", $TOTAL_MEM_GB * 100 / $TOTAL_MEM_GB}")
  else
    DOCKER_RUNNING=false
  fi
}

# JSON 형식 출력
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
  echo "    \"memory\": {"
  echo "      \"total\": \"$TOTAL_MEM_GB GB\","
  echo "      \"used\": \"$USED_MEMORY_GB GB\","
  echo "      \"percent\": $MEM_USAGE_PCT,"
  echo "      \"active\": \"$ACTIVE_MEMORY_GB GB\","
  echo "      \"wired\": \"$WIRED_MEMORY_GB GB\","
  echo "      \"free\": \"$FREE_MEMORY_GB GB\""
  echo "    },"
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
    echo "    \"mem\": \"$TOTAL_MEM_GB GB\","
    echo "    \"mem_pct\": $NODE_MEM_PCT_TOTAL,"
    echo "    \"net_rx\": \"$TOTAL_NET_RX_MB MB\","
    echo "    \"net_tx\": \"$TOTAL_NET_TX_MB MB\""
    echo "  }"
  else
    echo "  \"docker\": {"
    echo "    \"running\": false,"
    echo "    \"message\": \"Docker가 실행 중이 아니거나 액세스할 수 없습니다.\""
    echo "  }"
  fi
  
  echo "}"
}

# 일반 텍스트 출력
output_text() {
  # 헤더 출력
  echo -e "${BLUE}CREDITCOIN NODE RESOURCE MONITOR                                  $(date +"%Y-%m-%d %H:%M:%S")${NC}"
  echo ""
  
  # Docker가 실행 중이 아닌 경우
  if [ "$DOCKER_RUNNING" != "true" ]; then
    echo -e "${RED}Docker가 실행 중이 아니거나 액세스할 수 없습니다.${NC}"
    echo ""
  else
    # 테이블 헤더
    printf "%-10s %-8s %-10s %-13s %-8s %-15s\n" "NODE" "CPU%" "OF TOTAL%" "MEM USAGE" "MEM%" "NET RX/TX"
    
    # 노드별 데이터 출력
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
    
    # 합계 출력
    printf "%-10s %-8s %-10s %-13s %-8s %-15s\n" \
      "TOTAL" \
      "${TOTAL_CPU}%" \
      "${TOTAL_CPU_TOTAL}%" \
      "${TOTAL_MEM_GB} GB" \
      "${NODE_MEM_PCT_TOTAL}%" \
      "${TOTAL_NET_RX_MB}MB/${TOTAL_NET_TX_MB}MB"
  fi
  
  # 시스템 정보 출력 - 고정 길이로 출력하여 글자 겹침 방지
  echo ""
  echo -e "${BLUE}SYSTEM INFORMATION:${NC}"
  echo -e "- ${YELLOW}MODEL:${NC} $MODEL ($CHIP)"
  echo -e "- ${YELLOW}CPU CORES:${NC} $TOTAL_CORES (${PERF_CORES} Performance, ${EFF_CORES} Efficiency)"
  printf "- ${YELLOW}CPU USAGE:${NC} 사용자 %-5s%% 시스템 %-5s%% 유휴 %-5s%%\n" "$USER_CPU" "$SYS_CPU" "$IDLE_CPU"
  printf "- ${YELLOW}MEMORY:${NC} ${TOTAL_MEM_GB} GB 총량 (사용: ${USED_MEMORY_GB} GB, ${MEM_USAGE_PCT}%%)\n"
  echo -e "- ${YELLOW}DISK:${NC} ${DISK_USED}/${DISK_TOTAL} (${DISK_PERCENT}% 사용)"
}

# 단일 실행 모드
single_output() {
  get_system_info
  get_dynamic_info
  
  if [ "$JSON_OUTPUT" = true ]; then
    output_json
  else
    output_text
  fi
}

# 모니터링 모드
monitor_mode() {
  local interval=$1
  
  # 시스템 정보 수집 (한 번만)
  get_system_info
  
  # 터미널 설정 저장
  local old_tty_settings
  old_tty_settings=$(stty -g)
  
  # 화면 지우기
  clear
  
  # Ctrl+C 핸들러 설정
  trap 'echo; echo "모니터링을 종료합니다."; stty $old_tty_settings; echo -en "\033[?25h"; exit 0' INT TERM
  
  # 커서 숨기기
  echo -en "\033[?25l"
  
  # 모니터링 루프
  while true; do
    # 루프 시작 시간 기록
    local loop_start=$(date +%s.%N)
    
    # 커서를 화면 상단으로 이동
    echo -en "\033[H"
    
    # 데이터 수집
    get_dynamic_info
    
    # 출력
    if [ "$JSON_OUTPUT" = true ]; then
      output_json
    else
      output_text
      echo -e "\n${BLUE}모니터링 모드 - Ctrl+C를 눌러 종료${NC}"
    fi
    
    # 루프 실행 시간 계산
    local loop_time=$(echo "$(date +%s.%N) - $loop_start" | bc)
    
    # 남은 대기 시간 계산 (음수가 되지 않도록)
    local wait_time=$(echo "$interval - $loop_time" | bc)
    
    # 대기 시간이 양수인 경우에만 대기
    if (( $(echo "$wait_time > 0" | bc -l) )); then
      sleep $wait_time
    fi
  done
  
  # 터미널 설정 복원
  stty $old_tty_settings
  echo -en "\033[?25h"
}

# 메인 실행
if [ "$MONITOR_MODE" = true ]; then
  monitor_mode "$INTERVAL"
else
  single_output
fi