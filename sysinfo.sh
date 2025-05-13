#!/bin/bash
# sysinfo.sh - 최적화된 Creditcoin 노드 시스템 모니터링 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 터미널 제어 시퀀스
CLEAR_EOL=$'\033[K'  # 현재 커서 위치부터 줄 끝까지 지우기

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

# 소수점 두 자리로 포맷팅 함수
format_decimal() {
  local num=$1
  local decimals=${2:-2}
  printf "%.${decimals}f" "$num"
}

# 바이트 단위 변환 함수 (MB/GB 자동 변환)
format_bytes() {
  local bytes=$1
  if (( $(echo "$bytes > 1024" | bc -l) )); then
    local gb=$(echo "scale=2; $bytes / 1024" | bc)
    echo "${gb}GB"
  else
    echo "${bytes}MB"
  fi
}

# 스토리지 크기 단위 변환 및 표준화 함수
format_storage_size() {
  local size="$1"
  
  # 숫자 부분과 단위 부분 분리
  local num=$(echo "$size" | sed 's/[^0-9.]//g')
  local unit=$(echo "$size" | sed 's/[0-9.]//g')
  
  # 단위에 따른 변환
  case "$unit" in
    Ki|KiB|KB|K|kb) echo "${num}KB" ;;
    Mi|MiB|MB|M|mb) echo "${num}MB" ;;
    Gi|GiB|GB|G|gb) echo "${num}GB" ;;
    Ti|TiB|TB|T|tb) echo "${num}TB" ;;
    Pi|PiB|PB|P|pb) echo "${num}PB" ;;
    *) echo "${num}${unit}" ;;  # 알 수 없는 단위는 그대로 반환
  esac
}

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
  
  # 시스템 메모리 크기
  TOTAL_MEM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
  TOTAL_MEM_GB=$(format_decimal "$(echo "scale=2; $TOTAL_MEM_BYTES / 1024 / 1024 / 1024" | bc)")
  
  # Docker 정보를 가져오고 Docker에서 사용 가능한 메모리 계산
  if command -v docker &> /dev/null && docker info &> /dev/null; then
    # Docker 정보 가져오기
    DOCKER_INFO=$(docker info --format "{{.MemTotal}}" 2>/dev/null)
    if [ -n "$DOCKER_INFO" ]; then
      # Docker 메모리 계산 (바이트에서 GB로 변환)
      DOCKER_MEM_TOTAL=$(format_decimal "$(echo "scale=2; $DOCKER_INFO / 1024 / 1024 / 1024" | bc)")
      # Docker 메모리가 유효한 값이면 사용
      if (( $(echo "$DOCKER_MEM_TOTAL > 0" | bc -l) )); then
        TOTAL_MEM_GB=$DOCKER_MEM_TOTAL
      fi
    fi
  fi
}

# 동적 시스템 정보 수집
get_dynamic_info() {
  # CPU 사용률 (top 명령을 한 번만 실행)
  TOP_INFO=$(top -l 1 -n 0)
  CPU_LINE=$(echo "$TOP_INFO" | grep -E "^CPU")
  USER_CPU=$(echo "$CPU_LINE" | awk '{print $3}' | sed 's/%//')
  SYS_CPU=$(echo "$CPU_LINE" | awk '{print $5}' | sed 's/%//')
  IDLE_CPU=$(echo "$CPU_LINE" | awk '{print $7}' | sed 's/%//')
  
  # 메모리 정보
  VM_STAT=$(vm_stat)
  PAGE_SIZE=$(echo "$VM_STAT" | grep "page size" | awk '{print $8}')
  PAGES_FREE=$(echo "$VM_STAT" | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
  PAGES_ACTIVE=$(echo "$VM_STAT" | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
  PAGES_INACTIVE=$(echo "$VM_STAT" | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
  PAGES_WIRED=$(echo "$VM_STAT" | grep "Pages wired down" | awk '{print $4}' | sed 's/\.//')
  
  # 메모리 사용량 계산 (GB)
  WIRED_MEMORY_GB=$(format_decimal "$(echo "scale=3; $PAGES_WIRED * $PAGE_SIZE / 1024 / 1024 / 1024" | bc)")
  ACTIVE_MEMORY_GB=$(format_decimal "$(echo "scale=3; $PAGES_ACTIVE * $PAGE_SIZE / 1024 / 1024 / 1024" | bc)")
  INACTIVE_MEMORY_GB=$(format_decimal "$(echo "scale=3; $PAGES_INACTIVE * $PAGE_SIZE / 1024 / 1024 / 1024" | bc)")
  FREE_MEMORY_GB=$(format_decimal "$(echo "scale=3; $PAGES_FREE * $PAGE_SIZE / 1024 / 1024 / 1024" | bc)")
  USED_MEMORY_GB=$(format_decimal "$(echo "scale=3; $WIRED_MEMORY_GB + $ACTIVE_MEMORY_GB + $INACTIVE_MEMORY_GB" | bc)")
  
  # 메모리 사용률 계산
  MEM_USAGE_PCT=$(format_decimal "$(echo "scale=2; $USED_MEMORY_GB * 100 / $TOTAL_MEM_GB" | bc)")
  
  # 디스크 정보
  DISK_INFO=$(df -h / 2>/dev/null | grep -v "Filesystem" | head -1)
  DISK_TOTAL=$(echo "$DISK_INFO" | awk '{print $2}')
  DISK_USED=$(echo "$DISK_INFO" | awk '{print $3}')
  DISK_AVAIL=$(echo "$DISK_INFO" | awk '{print $4}')
  DISK_PERCENT=$(echo "$DISK_INFO" | awk '{print $5}' | sed 's/%//')
  
  # 디스크 단위 표준화
  DISK_TOTAL_FORMATTED=$(format_storage_size "$DISK_TOTAL")
  DISK_USED_FORMATTED=$(format_storage_size "$DISK_USED")
  DISK_AVAIL_FORMATTED=$(format_storage_size "$DISK_AVAIL")
  
  # 디스크 사용률 소수점 두 자리로 포맷팅
  DISK_PERCENT_FORMATTED=$(format_decimal "$DISK_PERCENT")
  
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
    TOTAL_MEM_NODES_GB=0
    TOTAL_NET_RX_MB=0
    TOTAL_NET_TX_MB=0
    
    # 컨테이너별 정보 파싱
    while IFS=$'\t' read -r name cpu mem mem_pct net; do
      # 배열에 이름 추가
      NODE_NAMES+=("$name")
      
      # CPU 정보 처리
      cpu_clean=$(echo "$cpu" | sed 's/%//')
      NODE_CPU+=("$cpu_clean")
      
      # CPU 총량 대비 사용률 계산 (두 자리 소수점으로 포맷팅)
      cpu_total=$(format_decimal "$(echo "scale=4; $cpu_clean / $TOTAL_CORES" | bc)")
      NODE_CPU_TOTAL+=("$cpu_total")
      
      # 총 CPU 사용량 합산
      TOTAL_CPU=$(format_decimal "$(echo "scale=4; $TOTAL_CPU + $cpu_clean" | bc)")
      TOTAL_CPU_TOTAL=$(format_decimal "$(echo "scale=4; $TOTAL_CPU_TOTAL + $cpu_total" | bc)")
      
      # 메모리 정보 처리
      # 형식: "4.909GiB / 58.81GiB"
      mem_parts=(${mem//\// })
      mem_used=${mem_parts[0]}
      mem_limit=${mem_parts[2]}
      
      # 숫자와 단위 분리
      mem_used_num=$(echo "$mem_used" | sed 's/[A-Za-z]*//g')
      mem_used_unit=$(echo "$mem_used" | sed 's/[0-9.]*//g')
      
      # 메모리 값이 있는지 확인
      if [ -n "$mem_limit" ]; then
        mem_limit_num=$(echo "$mem_limit" | sed 's/[A-Za-z]*//g')
        mem_limit_unit=$(echo "$mem_limit" | sed 's/[0-9.]*//g')
      else
        # 제한값이 없으면, Docker에서 사용 가능한 메모리로 대체
        mem_limit_num=$TOTAL_MEM_GB
        mem_limit_unit="GB"
      fi
      
      # 단위 변환 (GiB -> GB)
      if [[ "$mem_used_unit" == "GiB" ]]; then
        mem_used_gb=$(format_decimal "$(echo "scale=3; $mem_used_num" | bc)")
      elif [[ "$mem_used_unit" == "MiB" ]]; then
        mem_used_gb=$(format_decimal "$(echo "scale=3; $mem_used_num / 1024" | bc)")
      else
        mem_used_gb="0.00"
      fi
      
      if [[ "$mem_limit_unit" == "GiB" ]]; then
        mem_limit_gb=$(format_decimal "$(echo "scale=2; $mem_limit_num" | bc)")
      elif [[ "$mem_limit_unit" == "MiB" ]]; then
        mem_limit_gb=$(format_decimal "$(echo "scale=2; $mem_limit_num / 1024" | bc)")
      else
        mem_limit_gb=$mem_limit_num  # 이미 GB 단위
      fi
      
      # 포맷팅된 메모리 문자열 생성 (GB로 통일)
      formatted_mem="${mem_used_gb}GB / ${mem_limit_gb}GB"
      NODE_MEM+=("$formatted_mem")
      
      # 메모리 퍼센트 저장 (% 기호 제거)
      NODE_MEM_PCT+=("$(echo "$mem_pct" | sed 's/%//')")
      
      # 총 메모리 합산 (GB 단위로 통일)
      TOTAL_MEM_NODES_GB=$(format_decimal "$(echo "scale=3; $TOTAL_MEM_NODES_GB + $mem_used_gb" | bc)")
      
      # 네트워크 정보 처리
      net_parts=(${net//\// })
      rx=${net_parts[0]}
      tx=${net_parts[1]}
      
      NODE_NET_RX+=("$rx")
      NODE_NET_TX+=("$tx")
      
      # 네트워크 MB 단위로 통일해서 합산
      rx_value=$(echo "$rx" | sed 's/[^0-9.]//g')
      rx_unit=$(echo "$rx" | sed 's/[0-9.]//g')
      
      tx_value=$(echo "$tx" | sed 's/[^0-9.]//g')
      tx_unit=$(echo "$tx" | sed 's/[0-9.]//g')
      
      # 단위별로 MB로 변환
      if [[ "$rx_unit" == "kB" ]]; then
        rx_mb=$(format_decimal "$(echo "scale=2; $rx_value / 1024" | bc)")
      elif [[ "$rx_unit" == "MB" ]]; then
        rx_mb=$rx_value
      elif [[ "$rx_unit" == "GB" ]]; then
        rx_mb=$(format_decimal "$(echo "scale=2; $rx_value * 1024" | bc)")
      else
        rx_mb=0
      fi
      
      if [[ "$tx_unit" == "kB" ]]; then
        tx_mb=$(format_decimal "$(echo "scale=2; $tx_value / 1024" | bc)")
      elif [[ "$tx_unit" == "MB" ]]; then
        tx_mb=$tx_value
      elif [[ "$tx_unit" == "GB" ]]; then
        tx_mb=$(format_decimal "$(echo "scale=2; $tx_value * 1024" | bc)")
      else
        tx_mb=0
      fi
      
      # 총 네트워크 트래픽 합산
      TOTAL_NET_RX_MB=$(format_decimal "$(echo "scale=2; $TOTAL_NET_RX_MB + $rx_mb" | bc)")
      TOTAL_NET_TX_MB=$(format_decimal "$(echo "scale=2; $TOTAL_NET_TX_MB + $tx_mb" | bc)")
      
    done <<< "$DOCKER_STATS"
    
    # 총 노드 수
    NODE_COUNT=${#NODE_NAMES[@]}
    
    # 총 메모리 사용량의 퍼센티지 계산 (평균이 아닌 총 시스템 메모리 대비 비율)
    NODE_MEM_PCT_TOTAL=$(format_decimal "$(echo "scale=2; $TOTAL_MEM_NODES_GB * 100 / $TOTAL_MEM_GB" | bc)")
    
    # 네트워크 트래픽 단위 변환 (MB -> GB)
    TOTAL_NET_RX_FORMATTED=$(format_bytes $TOTAL_NET_RX_MB)
    TOTAL_NET_TX_FORMATTED=$(format_bytes $TOTAL_NET_TX_MB)
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
  echo "      \"percent\": $MEM_USAGE_PCT"
  echo "    },"
  echo "    \"disk\": {"
  echo "      \"total\": \"$DISK_TOTAL_FORMATTED\","
  echo "      \"used\": \"$DISK_USED_FORMATTED\","
  echo "      \"available\": \"$DISK_AVAIL_FORMATTED\","
  echo "      \"percent\": $DISK_PERCENT_FORMATTED"
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
    echo "    \"mem\": \"$TOTAL_MEM_NODES_GB GB\","
    echo "    \"mem_pct\": $NODE_MEM_PCT_TOTAL,"
    echo "    \"net_rx\": \"$TOTAL_NET_RX_FORMATTED\","
    echo "    \"net_tx\": \"$TOTAL_NET_TX_FORMATTED\""
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
  printf "${BLUE}CREDITCOIN NODE RESOURCE MONITOR                                  $(date +"%Y-%m-%d %H:%M:%S")${NC}%s\n" "$CLEAR_EOL"
  printf "%s\n" "$CLEAR_EOL"
  
  # Docker가 실행 중이 아닌 경우
  if [ "$DOCKER_RUNNING" != "true" ]; then
    printf "${RED}Docker가 실행 중이 아니거나 액세스할 수 없습니다.${NC}%s\n" "$CLEAR_EOL"
    printf "%s\n" "$CLEAR_EOL"
  else
    # 테이블 헤더
    printf "%-10s %-8s %-10s %-21s %-8s %-15s%s\n" "NODE" "CPU%" "OF TOTAL%" "MEM USAGE" "MEM%" "NET RX/TX" "$CLEAR_EOL"
    
    # 노드별 데이터 출력
    for i in $(seq 0 $((NODE_COUNT-1))); do
      printf "%-10s %-8s %-10s %-21s %-8s %-15s%s\n" \
        "${NODE_NAMES[$i]}" \
        "${NODE_CPU[$i]}%" \
        "${NODE_CPU_TOTAL[$i]}%" \
        "${NODE_MEM[$i]}" \
        "${NODE_MEM_PCT[$i]}%" \
        "${NODE_NET_RX[$i]}/${NODE_NET_TX[$i]}" \
        "$CLEAR_EOL"
    done
    
    # 구분선
    printf "%-10s %-8s %-10s %-21s %-8s %-15s%s\n" \
      "----------" "--------" "----------" "---------------------" "--------" "---------------" "$CLEAR_EOL"
    
    # 합계 출력
    printf "%-10s %-8s %-10s %-21s %-8s %-15s%s\n" \
      "TOTAL" \
      "${TOTAL_CPU}%" \
      "${TOTAL_CPU_TOTAL}%" \
      "${TOTAL_MEM_NODES_GB} GB" \
      "${NODE_MEM_PCT_TOTAL}%" \
      "${TOTAL_NET_RX_FORMATTED}/${TOTAL_NET_TX_FORMATTED}" \
      "$CLEAR_EOL"
  fi
  
  # 시스템 정보 출력
  printf "%s\n" "$CLEAR_EOL"
  printf "${BLUE}SYSTEM INFORMATION:${NC}%s\n" "$CLEAR_EOL"
  printf "${YELLOW}MODEL:${NC} %s (%s)%s\n" "$MODEL" "$CHIP" "$CLEAR_EOL"
  printf "${YELLOW}CPU CORES:${NC} %s (%s Performance, %s Efficiency)%s\n" "$TOTAL_CORES" "$PERF_CORES" "$EFF_CORES" "$CLEAR_EOL"
  printf "${YELLOW}CPU USAGE:${NC} 사용자 %s%%, 시스템 %s%%, 유휴 %s%%%s\n" "$USER_CPU" "$SYS_CPU" "$IDLE_CPU" "$CLEAR_EOL"
  printf "${YELLOW}MEMORY:${NC} %s GB 총량 (사용: %s GB, %s%%)%s\n" "$TOTAL_MEM_GB" "$USED_MEMORY_GB" "$MEM_USAGE_PCT" "$CLEAR_EOL"
  printf "${YELLOW}DISK:${NC} %s/%s (사용: %s%%, 남음: %s)%s\n" "$DISK_USED_FORMATTED" "$DISK_TOTAL_FORMATTED" "$DISK_PERCENT_FORMATTED" "$DISK_AVAIL_FORMATTED" "$CLEAR_EOL"
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
  
  # 화면 지우기 (처음 한 번만)
  clear
  
  # Ctrl+C 핸들러 설정
  trap 'echo; echo "모니터링을 종료합니다."; stty $old_tty_settings; echo -en "\033[?25h"; exit 0' INT TERM
  
  # 커서 숨기기
  echo -en "\033[?25l"
  
  # 모니터링 루프
  while true; do
    # 루프 시작 시간 기록
    local loop_start=$(date +%s.%N)
    
    # 커서를 화면 상단으로 이동 (화면 지우기 없이)
    echo -en "\033[H"
    
    # 데이터 수집
    get_dynamic_info
    
    # 출력
    if [ "$JSON_OUTPUT" = true ]; then
      output_json
    else
      output_text
      printf "\n${BLUE}모니터링 모드 - Ctrl+C를 눌러 종료${NC}%s\n" "$CLEAR_EOL"
    fi
    
    # 화면 끝까지 지우기
    echo -en "\033[J"
    
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