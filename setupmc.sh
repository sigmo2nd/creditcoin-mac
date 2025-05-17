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

# 기본 디렉토리 구조 생성
create_directory_structure() {
  show_step "기본 디렉토리 구조 생성"
  
  # mclient 디렉토리 생성
  mkdir -p ./mclient
  mkdir -p ./mclient/certs
  
  show_success "기본 디렉토리 구조가 생성되었습니다."
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
  show_warning "새 설정을 적용하려면 'source $SHELL_PROFILE' 명령을 실행하거나 새 터미널을 여세요."
}

# 메인 함수
main() {
  echo -e "${BLUE}=== Creditcoin 모니터링 클라이언트 기본 설정 스크립트 ===${NC}"
  
  # Docker 환경 확인
  check_docker_env
  
  # 기본 디렉토리 구조 생성
  create_directory_structure
  
  # 클라이언트 유틸리티 함수 생성
  create_client_utils
  
  echo -e "\n${GREEN}===================================================${NC}"
  echo -e "${GREEN}Creditcoin 모니터링 클라이언트 기본 설정이 완료되었습니다!${NC}"
  echo -e "${YELLOW}다음 단계로 addmc.sh를 실행하여 모니터링 클라이언트를 추가하세요.${NC}"
  echo -e "${GREEN}===================================================${NC}"
  
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
