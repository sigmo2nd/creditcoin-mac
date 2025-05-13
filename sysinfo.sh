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

# 터미널 제어 시퀀스 초기화
init_term_sequences() {
  # 커서 위치 이동 및 화면 제어
  CURSOR_HOME=$(tput cup 0 0)
  CLEAR_EOL=$(tput el)
  CLEAR_EOS=$(tput ed)
  CURSOR_INVISIBLE=$(tput civis)
  CURSOR_VISIBLE=$(tput cnorm)
  ALT_SCREEN=$(tput smcup)
  MAIN_SCREEN=$(tput rmcup)
  TERM_COLS=$(tput cols)
  TERM_LINES=$(tput lines)
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
  
  # 메모리 크기
  TOTAL_MEM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
  TOTAL_MEM_GB=$(printf "%.1f" "$(echo "scale=1;$TOTAL_MEM_BYTES/1024/1024/1024" | bc)")
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
  PAGES_WIRED=$(echo "$VM_STAT" | grep "Pages wired down" | awk '{print $4}' | sed 's/\.//')
  
  # 메모리 사용량 계산 (GB)
  MEM_FREE_GB=$(printf "%.1f" "$(echo "scale=1;$PAGES_FREE * $PAGE_SIZE / 1024 / 1024 / 1024" | bc)")
  MEM_USED_GB=$(printf "%.1f" "$(echo "scale=1;($TOTAL_MEM_GB - $MEM_FREE_GB)" | bc)")
  MEM_USAGE_PCT=$(printf "%.1f" "$(echo "scale=1;$MEM_USED_GB * 100 / $TOTAL_MEM_GB" | bc)")
  
  # 디스크 정보
  DISK_INFO=$(df -h / 2>/dev/null | grep -v "Filesystem" | head -1)
  DISK_TOTAL=$(echo "$DISK_INFO" | awk '{print $2}')
  DISK_USED=$(echo "$DISK_INFO" | awk '{print $3}')
  DISK_AVAIL=$(echo "$DISK_INFO" | awk '{print $4}')
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
      
      # CPU 총량 대비 사용률 계산
      cpu_total=$(printf "%.2f" "$(echo "scale=2;$cpu_clean / $TOTAL_CORES" | bc)")
      NODE_CPU_TOTAL+=("$cpu_total")
      
      # 총 CPU 사용량 합산
      TOTAL_CPU=$(printf "%.2f" "$(echo "scale=2;$TOTAL_CPU + $cpu_clean" | bc)")
      TOTAL_CPU_TOTAL=$(printf "%.2f" "$(echo "scale=2;$TOTAL_CPU_TOTAL + $cpu_total" | bc)")
      
      # 메모리 정보 처리
      NODE_MEM+=("$mem")
      NODE_MEM_PCT+=("$(echo "$mem_pct" | sed 's/%//')")
      
      # 메모리 GB 단위로 변환하여 합산
      mem_parts=($mem)
      mem_used=${mem_parts[0]}
      mem_used_num=$(echo "$mem_used" | sed 's/[A-Za-z]*//g')
      mem_used_unit=$(echo "$mem_used" | sed 's/[0-9.]*//g')
      
      if [[ "$mem_used_unit" == "GiB" ]]; then
        mem_gb=$mem_used_num
      elif [[ "$mem_used_unit" == "MiB" ]]; then
        mem_gb=$(printf "%.3f" "$(echo "scale=3;$mem_used_num / 1024" | bc)")
      else
        mem_gb=0
      fi
      
      TOTAL_MEM_NODES_GB=$(printf "%.3f" "$(echo "scale=3;$TOTAL_MEM_NODES_GB + $mem_gb" | bc)")
      
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
        rx_mb=$(printf "%.1f" "$(echo "scale=1;$rx_value / 1024" | bc)")
      elif [[ "$rx_unit" == "MB" ]]; then
        rx_mb=$rx_value
      elif [[ "$rx_unit" == "GB" ]]; then
        rx_mb=$(printf "%.1f" "$(echo "scale=1;$rx_value * 1024" | bc)")
      else
        rx_mb=0
      fi
      
      if [[ "$tx_unit" == "kB" ]]; then
        tx_mb=$(printf "%.1f" "$(echo "scale=1;$tx_value / 1024" | bc)")
      elif [[ "$tx_unit" == "MB" ]]; then
        tx_mb=$tx_value
      elif [[ "$tx_unit" == "GB" ]]; then
        tx_mb=$(printf "%.1f" "$(echo "scale=1;$tx_value * 1024" | bc)")
      else
        tx_mb=0
      fi
      
      # 총 네트워크 트래픽 합산
      TOTAL_NET_RX_MB=$(printf "%.1f" "$(echo "scale=1;$TOTAL_NET_RX_MB + $rx_mb" | bc)")
      TOTAL_NET_TX_MB=$(printf "%.1f" "$(echo "scale=1;$TOTAL_NET_TX_MB + $tx_mb" | bc)")
      
    done <<< "$DOCKER_STATS"
    
    # 총 노드 수
    NODE_COUNT=${#NODE_NAMES[@]}
    
    # 총 메모리 비율 계산
    NODE_MEM_PCT_TOTAL=$(printf "%.1f" "$(echo "scale=1;$TOTAL_MEM_NODES_GB * 100 / $TOTAL_MEM_GB" | bc)")
  else
    DOCKER_RUNNING=false
  fi
}

# 출력 문자열 생성 (버퍼링)
generate_output() {
  local buffer=""
  
  # 헤더 생성
  buffer+="${BLUE}CREDITCOIN NODE RESOURCE MONITOR                                  $(date +"%Y-%m-%d %H:%M:%S")${NC}\n\n"
  
  # Docker가 실행 중이 아닌 경우
  if [ "$DOCKER_RUNNING" != "true" ]; then
    buffer+="${RED}Docker가 실행 중이 아니거나 액세스할 수 없습니다.${NC}\n\n"
  else
    # 테이블 헤더
    buffer+=$(printf "%-10s %-8s %-10s %-13s %-8s %-15s\n" "NODE" "CPU%" "OF TOTAL%" "MEM USAGE" "MEM%" "NET RX/TX")
    
    # 노드별 데이터 출력
    for i in $(seq 0 $((NODE_COUNT-1))); do
      buffer+=$(printf "%-10s %-8s %-10s %-13s %-8s %-15s\n" \
        "${NODE_NAMES[$i]}" \
        "${NODE_CPU[$i]}%" \
        "${NODE_CPU_TOTAL[$i]}%" \
        "${NODE_MEM[$i]}" \
        "${NODE_MEM_PCT[$i]}%" \
        "${NODE_NET_RX[$i]}/${NODE_NET_TX[$i]}")
    done
    
    # 구분선
    buffer+=$(printf "%-10s %-8s %-10s %-13s %-8s %-15s\n" \
      "----------" "--------" "----------" "-------------" "--------" "---------------")
    
    # 합계 출력
    local formatted_mem=$(printf "%.1f GiB" "$TOTAL_MEM_NODES_GB")
    buffer+=$(printf "%-10s %-8s %-10s %-13s %-8s %-15s\n" \
      "TOTAL" \
      "${TOTAL_CPU}%" \
      "${TOTAL_CPU_TOTAL}%" \
      "$formatted_mem" \
      "${NODE_MEM_PCT_TOTAL}%" \
      "${TOTAL_NET_RX_MB}MB/${TOTAL_NET_TX_MB}MB")
  fi
  
  # 시스템 정보 출력
  buffer+="\n${BLUE}SYSTEM INFORMATION:${NC}\n"
  buffer+="${YELLOW}MODEL:${NC} $MODEL ($CHIP)\n"
  buffer+="${YELLOW}CPU CORES:${NC} $TOTAL_CORES (${PERF_CORES} Performance, ${EFF_CORES} Efficiency)\n"
  buffer+="${YELLOW}CPU USAGE:${NC} 사용자 ${USER_CPU}%, 시스템 ${SYS_CPU}%, 유휴 ${IDLE_CPU}%\n"
  buffer+="${YELLOW}MEMORY:${NC} ${TOTAL_MEM_GB} GB 총량 (사용: ${MEM_USED_GB} GB, ${MEM_USAGE_PCT}%)\n"
  buffer+="${YELLOW}DISK:${NC} ${DISK_USED}/${DISK_TOTAL} (${DISK_PERCENT}% 사용)\n"
  
  # 모니터링 모드 안내
  if [ "$MONITOR_MODE" = true ]; then
    buffer+="\n${BLUE}모니터링 모드 - Ctrl+C를 눌러 종료${NC}"
  fi
  
  echo -e "$buffer"
}

# JSON 형식 출력
output_json() {
  local json=""
  
  json+="{\n"
  json+="  \"timestamp\": \"$(date +"%Y-%m-%d %H:%M:%S")\",\n" 
  json+="  \"system\": {\n"
  json+="    \"model\": \"$MODEL\",\n"
  json+="    \"chip\": \"$CHIP\",\n"
  json+="    \"cores\": {\n"
  json+="      \"total\": $TOTAL_CORES,\n"
  json+="      \"performance\": $PERF_CORES,\n"
  json+="      \"efficiency\": $EFF_CORES\n"
  json+="    },\n"
  json+="    \"cpu_usage\": {\n"
  json+="      \"user\": $USER_CPU,\n"
  json+="      \"system\": $SYS_CPU,\n"
  json+="      \"idle\": $IDLE_CPU\n"
  json+="    },\n"
  json+="    \"memory\": {\n"
  json+="      \"total\": \"$TOTAL_MEM_GB GB\",\n"
  json+="      \"used\": \"$MEM_USED_GB GB\",\n"
  json+="      \"percent\": $MEM_USAGE_PCT\n"
  json+="    },\n"
  json+="    \"disk\": {\n"
  json+="      \"total\": \"$DISK_TOTAL\",\n"
  json+="      \"used\": \"$DISK_USED\",\n"
  json+="      \"available\": \"$DISK_AVAIL\",\n"
  json+="      \"percent\": $DISK_PERCENT\n"
  json+="    }\n"
  json+="  }"
  
  if [ "$DOCKER_RUNNING" = true ]; then
    json+=",\n  \"nodes\": [\n"
    for i in $(seq 0 $((NODE_COUNT-1))); do
      json+="    {\n"
      json+="      \"name\": \"${NODE_NAMES[$i]}\",\n"
      json+="      \"cpu\": ${NODE_CPU[$i]},\n"
      json+="      \"cpu_total\": ${NODE_CPU_TOTAL[$i]},\n"
      json+="      \"mem\": \"${NODE_MEM[$i]}\",\n"
      json+="      \"mem_pct\": ${NODE_MEM_PCT[$i]},\n"
      json+="      \"net_rx\": \"${NODE_NET_RX[$i]}\",\n"
      json+="      \"net_tx\": \"${NODE_NET_TX[$i]}\"\n"
      if [ $i -eq $((NODE_COUNT-1)) ]; then
        json+="    }\n"
      else
        json+="    },\n"
      fi
    done
    json+="  ],\n"
    json+="  \"totals\": {\n"
    json+="    \"cpu\": $TOTAL_CPU,\n"
    json+="    \"cpu_total\": $TOTAL_CPU_TOTAL,\n"
    json+="    \"mem\": \"$TOTAL_MEM_NODES_GB GB\",\n"
    json+="    \"mem_pct\": $NODE_MEM_PCT_TOTAL,\n"
    json+="    \"net_rx\": \"$TOTAL_NET_RX_MB MB\",\n"
    json+="    \"net_tx\": \"$TOTAL_NET_TX_MB MB\"\n"
    json+="  }\n"
  else
    json+=",\n  \"docker\": {\n"
    json+="    \"running\": false,\n"
    json+="    \"message\": \"Docker가 실행 중이 아니거나 액세스할 수 없습니다.\"\n"
    json+="  }\n"
  fi
  
  json+="}"
  
  echo -e "$json"
}

# 단일 실행 모드
single_output() {
  get_system_info
  get_dynamic_info
  
  if [ "$JSON_OUTPUT" = true ]; then
    output_json
  else
    generate_output
  fi
}

# 모니터링 모드
monitor_mode() {
  local interval=$1
  
  # 터미널 시퀀스 초기화
  init_term_sequences
  
  # 시스템 정보 수집 (한 번만)
  get_system_info
  
  # 터미널 설정 저장
  local old_tty_settings
  old_tty_settings=$(stty -g)
  
  # 대체 화면 버퍼 사용 및 커서 숨기기
  echo -en "$ALT_SCREEN$CURSOR_INVISIBLE"
  
  # Ctrl+C 핸들러 설정
  trap 'cleanup; exit 0' INT TERM
  
  # 모니터링 루프
  while true; do
    # 루프 시작 시간 기록
    local loop_start=$(date +%s.%N)
    
    # 데이터 수집
    get_dynamic_info
    
    # 버퍼에 출력 저장
    local output_buffer=""
    if [ "$JSON_OUTPUT" = true ]; then
      output_buffer=$(output_json)
    else
      output_buffer=$(generate_output)
    fi
    
    # 커서를 화면 상단으로 이동 후 버퍼 출력
    echo -en "$CURSOR_HOME"
    echo -e "$output_buffer"
    echo -en "$CLEAR_EOS"  # 남은 화면 지우기
    
    # 루프 실행 시간 계산
    local loop_time=$(echo "$(date +%s.%N) - $loop_start" | bc)
    
    # 남은 대기 시간 계산 (음수가 되지 않도록)
    local wait_time=$(echo "$interval - $loop_time" | bc)
    
    # 대기 시간이 양수인 경우에만 대기
    if (( $(echo "$wait_time > 0" | bc -l) )); then
      sleep $wait_time
    fi
  done
}

# 종료 시 정리 작업
cleanup() {
  echo
  echo "모니터링을 종료합니다."
  echo -en "$CURSOR_VISIBLE$MAIN_SCREEN"  # 커서 표시 및 메인 화면으로 복귀
}

# 메인 실행
if [ "$MONITOR_MODE" = true ]; then
  monitor_mode "$INTERVAL"
else
  single_output
fi