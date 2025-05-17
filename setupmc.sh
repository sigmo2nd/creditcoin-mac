#!/bin/bash
# setupmc.sh - Creditcoin 모니터링 클라이언트 기본 설정 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 현재 디렉토리 저장
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# 진행 상황 표시 함수
show_step() {
  echo -e "\n${BLUE}=== $1 ===${NC}"
}

# 성공 메시지 표시 함수
show_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

# 경고 메시지 표시 함수
show_warning() {
  echo -e "${YELLOW}! $1${NC}"
}

# 오류 메시지 표시 함수
show_error() {
  echo -e "${RED}✗ $1${NC}"
}

# Docker 환경 확인 (SSH 및 OrbStack 호환성)
check_docker_env() {
  show_step "Docker 환경 확인"
  
  # Docker 명령어 경로 확인 및 추가
  if ! command -v docker &>/dev/null; then
    show_warning "Docker 명령어를 찾을 수 없습니다. OrbStack에서 제공하는 Docker CLI를 PATH에 추가합니다."
    
    if [ -f "/Applications/OrbStack.app/Contents/MacOS/xbin/docker" ]; then
      export PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:$PATH"
    fi
    
    # 다시 확인
    if ! command -v docker &>/dev/null; then
      show_error "Docker CLI를 찾을 수 없습니다. OrbStack이 설치되어 있는지 확인하세요."
      exit 1
    fi
  else
    show_success "Docker CLI가 설치되어 있습니다."
  fi

  # SSH 세션 호환성 설정
  if [ -S "$HOME/.orbstack/run/docker.sock" ]; then
    export DOCKER_HOST="unix://$HOME/.orbstack/run/docker.sock"
    export DOCKER_CLI_NO_CREDENTIAL_STORE=1
    show_success "OrbStack Docker 소켓 설정 완료"
  fi
  
  # Docker 실행 상태 확인 및 시작 시도
  if ! docker info &> /dev/null; then
    show_warning "Docker 엔진(OrbStack)이 실행 중이 아닙니다. 시작을 시도합니다..."
    # OrbStack 시작 시도
    if command -v orb &> /dev/null; then
      orb start
      sleep 10 # 초기화 시간 부여
      
      # 다시 확인
      if ! docker info &> /dev/null; then
        show_error "Docker 엔진(OrbStack)을 시작할 수 없습니다."
        show_warning "OrbStack을 수동으로 실행한 후 다시 시도하세요."
        exit 1
      fi
    else
      show_error "Docker 엔진(OrbStack)이 실행 중이 아닙니다."
      show_warning "OrbStack을 실행한 후 다시 시도하세요."
      exit 1
    fi
  else
    show_success "Docker 엔진이 실행 중입니다."
  fi
}

# Docker Compose 확인
check_docker_compose() {
  show_step "Docker Compose 확인"
  
  # docker-compose.yml 파일 존재 확인
  if [ ! -f "${SCRIPT_DIR}/docker-compose.yml" ]; then
    show_error "docker-compose.yml 파일이 현재 디렉토리에 없습니다"
    show_warning "이 스크립트는 Creditcoin 노드가 설치된 디렉토리에서 실행되어야 합니다"
    exit 1
  fi
  
  # Docker Compose 명령어 사용 가능 여부 확인
  if docker compose version &>/dev/null; then
    show_success "Docker Compose 플러그인이 사용 가능합니다."
  elif command -v docker-compose &>/dev/null; then
    show_warning "Docker Compose 플러그인이 아닌 독립 실행형 docker-compose를 사용합니다."
    show_warning "가능하면 Docker Compose 플러그인으로 업그레이드하는 것이 좋습니다."
  else
    show_error "Docker Compose가 설치되어 있지 않습니다."
    show_warning "Docker와 Docker Compose를 설치한 후 다시 시도하세요."
    exit 1
  fi
}

# 기본 디렉토리 구조 생성
create_directory_structure() {
  show_step "기본 디렉토리 구조 생성"
  
  # mclient 디렉토리 생성
  mkdir -p "${SCRIPT_DIR}/mclient"
  mkdir -p "${SCRIPT_DIR}/mclient/certs"
  
  # mclient_org 디렉토리 생성 (소스 코드 저장용)
  mkdir -p "${SCRIPT_DIR}/mclient_org"
  
  show_success "기본 디렉토리 구조가 생성되었습니다."
}

# 기본 소스 파일 복사 또는 생성
create_source_files() {
  show_step "기본 소스 파일 준비"
  
  # 필요한 파일 목록
  local files=(
    "main.py" 
    "docker_stats_client.py" 
    "websocket_client.py" 
    "requirements.txt"
  )
  
  # 파일이 현재 디렉토리에 있는지 확인하고 복사
  local source_found=false
  for file in "${files[@]}"; do
    if [ -f "${SCRIPT_DIR}/$file" ]; then
      show_success "$file 파일을 찾았습니다. mclient_org 디렉토리로 복사합니다."
      cp "${SCRIPT_DIR}/$file" "${SCRIPT_DIR}/mclient_org/"
      source_found=true
    fi
  done
  
  # 소스 파일이 없으면 샘플 requirements.txt 생성
  if [ "$source_found" = false ]; then
    show_warning "소스 파일을 찾을 수 없습니다. 기본 requirements.txt 파일을 생성합니다."
    
    cat > "${SCRIPT_DIR}/mclient_org/requirements.txt" << EOF
docker==6.1.2
websockets==11.0.3
pydantic==2.1.1
pydantic-settings==2.0.3
python-dotenv==1.0.0
psutil==5.9.5
EOF
    
    show_success "기본 requirements.txt 파일이 생성되었습니다."
    show_warning "모니터링 클라이언트 소스 파일(main.py, docker_stats_client.py 등)이 필요합니다."
  fi
}

# 호스트 시스템 정보 수집
collect_host_info() {
  show_step "호스트 시스템 정보 수집"
  
  # 호스트명 수집
  local hostname=$(hostname)
  local hostname_local=$(hostname -f 2>/dev/null || echo "$hostname.local")
  
  # macOS 고유 ID 수집 (하드웨어 UUID)
  local hw_uuid=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Hardware UUID" | awk -F': ' '{print $2}' | tr -d ' ' || echo "")
  
  # 시스템 모델 정보
  local model_name=""
  local processor_info=""
  
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS 시스템 모델 및 프로세서 정보
    model_name=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Model Name" | awk -F': ' '{print $2}' | xargs || echo "Unknown Mac")
    processor_info=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Chip" | awk -F': ' '{print $2}' | xargs || echo "")
    
    # Intel Mac의 경우 프로세서 정보가 'Processor'로 표시될 수 있음
    if [[ -z "$processor_info" ]]; then
      processor_info=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Processor" | awk -F': ' '{print $2}' | xargs || echo "Unknown Processor")
    fi
    
    # CPU 코어 정보
    local cpu_cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "0")
    local perf_cores=$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || echo "0")
    local eff_cores=$(sysctl -n hw.perflevel1.logicalcpu 2>/dev/null || echo "0")
    
    # 메모리 정보
    local memory_gb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo "0") / 1024 / 1024 / 1024 ))
    
    # 디스크 정보
    local disk_total=$(df -h / | awk 'NR==2 {print $2}')
    
    # 결과 출력
    show_success "호스트명: $hostname_local"
    show_success "모델명: $model_name"
    show_success "프로세서: $processor_info"
    show_success "CPU 코어: $cpu_cores 코어 (성능: $perf_cores, 효율: $eff_cores)"
    show_success "메모리: ${memory_gb}GB"
    show_success "디스크 용량: $disk_total"
    
    # 환경 변수 파일 생성
    create_env_file "$hostname_local" "$model_name" "$processor_info" "$cpu_cores" "$memory_gb" "$perf_cores" "$eff_cores"
  else
    show_error "이 스크립트는 현재 macOS만 지원합니다."
    create_env_file "$hostname" "Unknown" "Unknown" "1" "1" "0" "0"
  fi
}

# 환경 변수 파일 생성
create_env_file() {
  local hostname="$1"
  local model_name="$2"
  local processor="$3"
  local cpu_cores="$4"
  local memory_gb="$5"
  local perf_cores="$6"
  local eff_cores="$7"
  local env_file="${SCRIPT_DIR}/mclient/.env"
  
  show_step "환경 변수 파일 생성 (.env)"
  
  # 기존 .env 백업 (있는 경우)
  if [ -f "$env_file" ]; then
    cp "$env_file" "${env_file}.bak.$(date +%Y%m%d%H%M%S)"
    show_success ".env 파일 백업 완료"
  fi
  
  # 서버 ID 및 노드 이름 지정에 대한 안내
  show_warning "모니터링 클라이언트 식별을 위한 설정을 입력합니다."
  
  # 서버 ID 기본값 (호스트명)
  local default_server_id="${hostname%%.*}"
  read -p "서버 ID (기본값: $default_server_id): " server_id
  server_id=${server_id:-$default_server_id}
  
  # 노드 이름 기본값
  local default_node_names="node,3node"
  read -p "모니터링할 노드 이름 쉼표로 구분 (기본값: $default_node_names): " node_names
  node_names=${node_names:-$default_node_names}
  
  # Docker 정보 환경변수 사용 여부
  read -p "Docker 정보를 수집하시겠습니까? (Y/n): " use_docker
  if [[ "$use_docker" =~ ^([nN][oO]|[nN])$ ]]; then
    no_docker="true"
  else
    no_docker="false"
  fi
  
  # 로컬 모드 기본 설정
  read -p "로컬 모드로 실행하시겠습니까? (Y/n): " local_mode
  if [[ ! "$local_mode" =~ ^([nN][oO]|[nN])$ ]]; then
    is_local_mode="true"
  else
    is_local_mode="false"
  fi
  
  # 모니터링 간격 설정
  read -p "모니터링 간격(초) (기본값: 5): " monitor_interval
  monitor_interval=${monitor_interval:-5}
  
  # .env 파일 생성
  cat > "$env_file" << EOT
# Creditcoin 모니터링 클라이언트 환경설정
# 생성일: $(date)

# 클라이언트 식별자 설정
SERVER_ID="${server_id}"
NODE_NAMES="${node_names}"
MONITOR_INTERVAL=${monitor_interval}

# 호스트 시스템 정보
HOST_SYSTEM_NAME="${hostname}"
HOST_MODEL="${model_name}"
HOST_PROCESSOR="${processor}"
HOST_CPU_CORES=${cpu_cores}
HOST_CPU_PERF_CORES=${perf_cores}
HOST_CPU_EFF_CORES=${eff_cores}
HOST_MEMORY_GB=${memory_gb}

# 실행 모드 설정 
LOCAL_MODE=${is_local_mode}
NO_DOCKER=${no_docker}
DEBUG_MODE=false

# WebSocket 서버 설정 (로컬 모드가 아닌 경우만 사용)
WS_MODE="auto"
WS_SERVER_HOST="192.168.0.24"
WS_PORT_WS=8080
WS_PORT_WSS=8443
NO_SSL_VERIFY=false
EOT

  show_success ".env 파일 생성 완료: $env_file"
}

# 클라이언트 유틸리티 함수 생성
create_client_utils() {
  show_step "클라이언트 유틸리티 함수 생성"
  
  # 셸 프로필 파일 결정
  if [[ "$SHELL" == *"zsh"* ]]; then
    SHELL_PROFILE="$HOME/.zshrc"
  else
    SHELL_PROFILE="$HOME/.bash_profile"
  fi
  
  # 마커 문자열 설정
  local marker="# === Creditcoin Monitor Client Utils ==="
  local endmarker="# === End Creditcoin Monitor Client Utils ==="
  
  # 이미 추가되었는지 확인
  if grep -q "$marker" "$SHELL_PROFILE" 2>/dev/null; then
    show_warning "이미 $SHELL_PROFILE에 모니터링 클라이언트 설정이 추가되어 있습니다."
    
    # 기존 설정 백업
    cp "$SHELL_PROFILE" "${SHELL_PROFILE}.bak.$(date +%Y%m%d%H%M%S)"
    show_success "$SHELL_PROFILE 백업 파일이 생성되었습니다."
    
    # 기존 설정 블록 제거
    sed -i.tmp "/$marker/,/$endmarker/d" "$SHELL_PROFILE"
    rm -f "${SHELL_PROFILE}.tmp"
    
    show_success "기존 모니터링 클라이언트 설정이 제거되었습니다."
  fi
  
  # 프로필 파일에 추가
  cat >> "$SHELL_PROFILE" << EOT
$marker
# Creditcoin 모니터링 클라이언트 설정
MCLIENT_DIR="$SCRIPT_DIR/mclient"

# 모니터링 클라이언트 유틸리티 함수
function mclient-start() {
  echo -e "${BLUE}모니터링 클라이언트 시작 중...${NC}"
  docker compose -p creditcoin3 up -d mclient
}

function mclient-stop() {
  echo -e "${BLUE}모니터링 클라이언트 중지 중...${NC}"
  docker compose -p creditcoin3 stop mclient
}

function mclient-restart() {
  echo -e "${BLUE}모니터링 클라이언트 재시작 중...${NC}"
  docker compose -p creditcoin3 restart mclient
}

function mclient-logs() {
  echo -e "${BLUE}모니터링 클라이언트 로그 표시 중...${NC}"
  docker compose -p creditcoin3 logs -f mclient
}

function mclient-status() {
  echo -e "${BLUE}모니터링 클라이언트 상태 확인 중...${NC}"
  if docker ps | grep -q mclient; then
    echo -e "${GREEN}모니터링 클라이언트가 실행 중입니다.${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep mclient
  else
    echo -e "${RED}모니터링 클라이언트가 실행 중이 아닙니다.${NC}"
  fi
}

function mclient-local() {
  echo -e "${BLUE}모니터링 클라이언트 로컬 실행 중...${NC}"
  cd "$MCLIENT_DIR" && python3 main.py --local
}

# 짧은 형태의 명령어 추가
alias mcstart="mclient-start"
alias mcstop="mclient-stop"
alias mcrestart="mclient-restart"
alias mclogs="mclient-logs"
alias mcstatus="mclient-status"
alias mclocal="mclient-local"
$endmarker
EOT

  show_success "모니터링 클라이언트 유틸리티 함수가 $SHELL_PROFILE에 추가되었습니다."
}

# Docker Compose 설정 수정
update_docker_compose() {
  show_step "Docker Compose 설정 업데이트"
  
  # docker-compose.yml 파일 경로
  local compose_file="${SCRIPT_DIR}/docker-compose.yml"
  
  # mclient 서비스가 있는지 확인
  if grep -q "mclient:" "$compose_file"; then
    show_warning "docker-compose.yml에 이미 mclient 서비스가 있습니다."
  else
    show_warning "docker-compose.yml에 mclient 서비스 추가 중..."
    
    # 임시 파일로 복사 후 수정
    cp "$compose_file" "${compose_file}.bak.$(date +%Y%m%d%H%M%S)"
    show_success "docker-compose.yml 백업 완료"
    
    # 파일 마지막에 mclient 서비스 추가
    cat >> "$compose_file" << EOT

  mclient:
    build:
      context: ./mclient
      dockerfile: Dockerfile
    env_file:
      - ./mclient/.env
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped
EOT
    
    show_success "docker-compose.yml에 mclient 서비스가 추가되었습니다."
  fi
  
  # Dockerfile 생성
  local dockerfile="${SCRIPT_DIR}/mclient/Dockerfile"
  
  if [ -f "$dockerfile" ]; then
    show_warning "Dockerfile이 이미 존재합니다."
  else
    show_warning "Dockerfile 생성 중..."
    
    cat > "$dockerfile" << EOT
FROM python:3.9-slim

WORKDIR /app

# 의존성 설치
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 소스 코드 복사
COPY . .

# 실행 명령어
CMD ["python", "main.py"]
EOT
    
    show_success "Dockerfile이 생성되었습니다."
  fi
}

# 메인 함수
main() {
  echo -e "${BLUE}=== Creditcoin 모니터링 클라이언트 기본 설정 스크립트 ===${NC}"
  
  # Docker 환경 확인
  check_docker_env
  
  # Docker Compose 확인
  check_docker_compose
  
  # 기본 디렉토리 구조 생성
  create_directory_structure
  
  # 기본 소스 파일 생성
  create_source_files
  
  # 호스트 시스템 정보 수집 및 .env 파일 생성
  collect_host_info
  
  # 클라이언트 유틸리티 함수 생성
  create_client_utils
  
  # Docker Compose 설정 업데이트
  update_docker_compose
  
  echo -e "\n${GREEN}===================================================${NC}"
  echo -e "${GREEN}Creditcoin 모니터링 클라이언트 기본 설정이 완료되었습니다!${NC}"
  echo -e "${GREEN}===================================================${NC}"
  
  echo -e "\n${YELLOW}변경 사항을 적용하려면 다음 명령어를 실행하세요:${NC}"
  echo -e "${BLUE}source $SHELL_PROFILE${NC}"
  
  echo -e "\n${YELLOW}사용 가능한 명령어:${NC}"
  echo -e "${GREEN}mcstart${NC}     - 모니터링 클라이언트 시작"
  echo -e "${GREEN}mcstop${NC}      - 모니터링 클라이언트 중지"
  echo -e "${GREEN}mcrestart${NC}   - 모니터링 클라이언트 재시작"
  echo -e "${GREEN}mclogs${NC}      - 모니터링 클라이언트 로그 표시"
  echo -e "${GREEN}mcstatus${NC}    - 모니터링 클라이언트 상태 확인"
  echo -e "${GREEN}mclocal${NC}     - 로컬 모드로 모니터링 클라이언트 실행"
}

# 스크립트 실행
main