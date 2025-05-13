#!/bin/bash
# setup.sh - Creditcoin Docker 유틸리티 설정 스크립트 (macOS용)

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

# 환경 확인
check_environment() {
  show_step "시스템 환경 확인"
  
  # macOS 확인
  if [[ "$(uname)" != "Darwin" ]]; then
    show_error "이 스크립트는 macOS 전용입니다."
    exit 1
  fi
  
  # 아키텍처 확인
  ARCH=$(uname -m)
  if [[ "$ARCH" == "arm64" ]]; then
    show_success "감지된 아키텍처: $ARCH (Apple Silicon)"
  elif [[ "$ARCH" == "x86_64" ]]; then
    show_success "감지된 아키텍처: $ARCH (Intel Mac)"
  else
    show_error "지원되지 않는 아키텍처입니다: $ARCH"
    exit 1
  fi
  
  # macOS 버전 확인
  OS_VERSION=$(sw_vers -productVersion)
  show_success "감지된 macOS 버전: $OS_VERSION"
  
  # 쉘 확인
  if [[ "$SHELL" == *"zsh"* ]]; then
    show_success "기본 쉘: zsh"
    SHELL_PROFILE="$HOME/.zshrc"
  else
    show_success "기본 쉘: bash 또는 기타"
    SHELL_PROFILE="$HOME/.bash_profile"
  fi
  
  # Xcode 명령줄 도구 확인
  if ! xcode-select -p &> /dev/null; then
    show_warning "Xcode 명령줄 도구가 설치되어 있지 않습니다. 설치를 시작합니다..."
    xcode-select --install
    show_warning "Xcode 명령줄 도구 설치 창이 나타납니다."
    show_warning "설치를 완료하면 엔터를 눌러 계속하세요..."
    read -p ""
  else
    show_success "Xcode 명령줄 도구가 설치되어 있습니다."
  fi
}

# 전원 관리 설정 최적화
optimize_power_settings() {
  show_step "전원 관리 설정 최적화"
  
  # 현재 설정 확인
  show_warning "현재 전원 관리 설정:"
  pmset -g
  
  # 최적화 여부 물어보기
  read -p "블록체인 노드 운영에 최적화된 전원 설정을 적용하시겠습니까? (Y/n): " response
  if [[ ! "$response" =~ ^([nN][oO]|[nN])$ ]]; then
    show_warning "최적화된 전원 설정을 적용합니다..."
    
    # 전원 관리 설정 (즉시 적용)
    sudo pmset -a displaysleep 10  # 디스플레이만 10분 후 절전
    sudo pmset -a sleep 0          # 시스템 절전 비활성화
    sudo pmset -a disksleep 0      # 디스크 절전 비활성화
    sudo pmset -a standby 0        # 대기 모드 비활성화
    sudo pmset -a autopoweroff 0   # 자동 전원 끄기 비활성화
    sudo pmset -a powernap 0       # PowerNap 비활성화
    sudo pmset -a ttyskeepawake 1  # SSH 세션 활성화 시 깨어있음
    sudo pmset -a tcpkeepalive 1   # TCP 연결 유지
    sudo pmset -a networkoversleep 0  # 네트워크 연결 유지
    
    show_success "전원 관리 설정이 최적화되었습니다."
    show_warning "새 설정:"
    pmset -g
  else
    show_warning "전원 관리 설정 최적화를 건너뛰었습니다."
    show_warning "블록체인 노드를 24/7 운영하려면 전원 관리 설정 최적화를 권장합니다."
  fi
}

# 시간 서버 설정 확인 및 구성
check_time_server() {
  show_step "시스템 시간 서버 확인"
  
  # 현재 시간 서버 확인
  current_server=$(sudo systemsetup -getnetworktimeserver 2>/dev/null | awk -F ': ' '{print $2}')
  network_time_enabled=$(sudo systemsetup -getusingnetworktime 2>/dev/null | grep -q "On" && echo "yes" || echo "no")
  
  if [[ "$current_server" == "(null)" || "$current_server" == "" ]]; then
    show_warning "⚠️ 경고: 시간 서버가 설정되어 있지 않습니다!"
    show_warning "블록체인 노드 운영에는 정확한 시간 동기화가 필수적입니다."
    
    read -p "자동으로 시간 서버를 설정하시겠습니까? (Y/n): " response
    if [[ ! "$response" =~ ^([nN][oO]|[nN])$ ]]; then
      sudo systemsetup -setnetworktimeserver time.apple.com
      sudo systemsetup -setusingnetworktime on
      
      show_warning "시간 서비스 재시작 중..."
      sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.timed.plist 2>/dev/null
      sleep 5
      sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.timed.plist
      
      show_warning "시간 강제 동기화 중..."
      sudo sntp -sS time.apple.com
      
      show_success "시간 서버가 time.apple.com(자동 지역 감지)으로 설정되었습니다."
    else
      show_warning "시간 서버를 설정하지 않았습니다. 블록체인 노드 운영에 문제가 발생할 수 있습니다."
    fi
  elif [[ "$network_time_enabled" != "yes" ]]; then
    show_warning "⚠️ 경고: 네트워크 시간 동기화가 비활성화되어 있습니다!"
    read -p "네트워크 시간 동기화를 활성화하시겠습니까? (Y/n): " response
    if [[ ! "$response" =~ ^([nN][oO]|[nN])$ ]]; then
      sudo systemsetup -setusingnetworktime on
      
      show_warning "시간 서비스 재시작 중..."
      sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.timed.plist 2>/dev/null
      sleep 5
      sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.timed.plist
      
      show_warning "시간 강제 동기화 중..."
      sudo sntp -sS "$current_server"
      
      show_success "네트워크 시간 동기화가 활성화되었습니다."
    else
      show_warning "네트워크 시간 동기화가 비활성화된 상태로 유지됩니다. 블록체인 노드 운영에 문제가 발생할 수 있습니다."
    fi
  else
    show_success "시간 서버가 올바르게 설정되어 있습니다: $current_server"
    show_success "네트워크 시간 동기화가 활성화되어 있습니다."
    
    # 강제 시간 동기화 제안
    read -p "시간을 강제로 동기화하시겠습니까? (Y/n): " sync_response
    if [[ ! "$sync_response" =~ ^([nN][oO]|[nN])$ ]]; then
      show_warning "시간 강제 동기화 중..."
      sudo sntp -sS "$current_server"
      show_success "시간이 강제로 동기화되었습니다."
    fi
  fi
  
  # 현재 시간 표시
  current_time=$(date)
  show_success "현재 시스템 시간: $current_time"
}

# Homebrew 설치
install_homebrew() {
  show_step "Homebrew 설치 확인"
  
  if ! command -v brew &> /dev/null; then
    show_warning "Homebrew가 설치되어 있지 않습니다. 설치를 시작합니다..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Homebrew PATH 설정 
    if [[ "$ARCH" == "arm64" ]]; then
      show_warning "Apple Silicon용 Homebrew 경로를 설정합니다..."
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$SHELL_PROFILE"
      eval "$(/opt/homebrew/bin/brew shellenv)"
    else
      echo 'eval "$(/usr/local/bin/brew shellenv)"' >> "$SHELL_PROFILE"
      eval "$(/usr/local/bin/brew shellenv)"
    fi
    
    show_success "Homebrew가 설치되었습니다."
  else
    show_success "Homebrew가 이미 설치되어 있습니다."
  fi
  
  # Homebrew 업데이트
  show_warning "Homebrew 업데이트 중..."
  brew update
}

# 필요한 도구 설치
install_tools() {
  show_step "필요한 도구 설치"
  
  # git-lfs 확인 및 설치
  if ! command -v git-lfs &> /dev/null; then
    show_warning "git-lfs가 설치되어 있지 않습니다. 설치를 시작합니다..."
    brew install git-lfs
    git lfs install
    show_success "git-lfs가 설치되었습니다."
  else
    show_success "git-lfs가 설치되어 있습니다."
  fi
  
  # jq 확인 및 설치 (JSON 처리 유틸리티)
  if ! command -v jq &> /dev/null; then
    show_warning "jq가 설치되어 있지 않습니다. 설치를 시작합니다..."
    brew install jq
    show_success "jq가 설치되었습니다."
  else
    show_success "jq가 설치되어 있습니다."
  fi
  
  # GNU 유틸리티 설치 (Linux 호환 유틸리티)
  show_warning "GNU 버전 유틸리티 설치 중..."
  brew install coreutils findutils gnu-sed gawk grep
  
  show_success "모든 필요한 도구가 설치되었습니다."
}

# OrbStack 설치
install_orbstack() {
  show_step "OrbStack 설치 확인"
  
  # OrbStack이 설치되어 있는지 확인
  if [ -d "/Applications/OrbStack.app" ]; then
    show_success "OrbStack이 이미 설치되어 있습니다."
  else
    show_warning "OrbStack이 설치되어 있지 않습니다. 설치를 시작합니다..."
    
    # Homebrew를 통해 설치
    brew install orbstack
    
    if [ -d "/Applications/OrbStack.app" ]; then
      show_success "OrbStack이 설치되었습니다."
      
      # 로컬 환경에서 실행 중인 경우에만 데스크톱 앱 열기
      if [ -z "$SSH_CLIENT" ] && [ -z "$SSH_TTY" ]; then
        show_warning "OrbStack 앱을 열어 초기 설정을 완료하세요."
        open -a OrbStack
      else
        show_warning "이 스크립트는 SSH 세션에서 실행 중입니다."
        show_warning "데스크톱 환경에서 OrbStack 앱을 열어 초기 설정을 완료하세요."
      fi
    else
      show_error "OrbStack 설치에 실패했습니다."
      show_warning "수동으로 설치를 시도하세요: https://orbstack.dev/download"
      exit 1
    fi
  fi
  
  # Docker CLI 경로 설정
  if ! command -v docker &> /dev/null; then
    show_warning "Docker CLI를 PATH에 추가합니다..."
    
    if [ -f "/Applications/OrbStack.app/Contents/MacOS/xbin/docker" ]; then
      export PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:$PATH"
      show_success "Docker CLI 경로가 PATH에 추가되었습니다."
    else
      show_warning "Docker CLI를 찾을 수 없습니다. OrbStack이 제대로 설치되었는지 확인하세요."
    fi
  fi
}

# 쉘 프로필에 유틸리티 추가
add_to_shell_profile() {
  show_step "쉘 프로필 설정"
  
  # 마커 문자열 설정
  local marker="# === Creditcoin Docker Utils ==="
  local endmarker="# === End Creditcoin Docker Utils ==="
  
  # 이미 추가되었는지 확인
  if grep -q "$marker" "$SHELL_PROFILE" 2>/dev/null; then
    show_warning "이미 $SHELL_PROFILE에 설정이 추가되어 있습니다."
    
    # 기존 설정 백업
    cp "$SHELL_PROFILE" "${SHELL_PROFILE}.bak.$(date +%Y%m%d%H%M%S)"
    show_success "$SHELL_PROFILE 백업 파일이 생성되었습니다."
    
    # 기존 설정 블록 제거
    sed -i.tmp "/$marker/,/$endmarker/d" "$SHELL_PROFILE"
    rm -f "${SHELL_PROFILE}.tmp"
    
    show_success "기존 Creditcoin Docker Utils 설정이 제거되었습니다."
  fi
  
  # 프로필 파일에 추가
  cat >> "$SHELL_PROFILE" << EOT
$marker
# Creditcoin Docker 설치 경로
CREDITCOIN_DIR="$SCRIPT_DIR"
CREDITCOIN_UTILS="\$CREDITCOIN_DIR/creditcoin-utils.sh"
SYSINFO_SCRIPT="\$CREDITCOIN_DIR/sysinfo.sh"

# OrbStack Docker CLI 경로 추가
if [ -f "/Applications/OrbStack.app/Contents/MacOS/xbin/docker" ]; then
    export PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:\$PATH"
fi

# OrbStack Docker 호스트 설정
export DOCKER_HOST="unix://\$HOME/.orbstack/run/docker.sock"

# Docker 키체인 인증 비활성화
export DOCKER_CLI_NO_CREDENTIAL_STORE=1

# 유틸리티 함수 로드
if [ -f "\$CREDITCOIN_UTILS" ]; then
    source "\$CREDITCOIN_UTILS"
fi

# sysinfo 명령어 등록
if [ -f "\$SYSINFO_SCRIPT" ]; then
    alias sysinfo="\$SYSINFO_SCRIPT"
fi
$endmarker
EOT

  # sysinfo.sh에 실행 권한 부여
  chmod +x "$SCRIPT_DIR/sysinfo.sh"

  show_success "$SHELL_PROFILE에 유틸리티가 추가되었습니다."
}

# 리소스 권장 설정 안내
show_resource_recommendations() {
  show_step "리소스 권장 설정"
  
  show_warning "Creditcoin 노드는 리소스를 많이 사용합니다. 다음과 같은 리소스 설정을 권장합니다:"
  echo -e "${GREEN}1. CPU: 4코어 이상${NC}"
  echo -e "${GREEN}2. 메모리: 8GB 이상${NC}"
  echo -e "${GREEN}3. 디스크 공간: 100GB 이상${NC}"
  
  show_warning "데스크톱 환경에서 OrbStack 앱을 열고 설정에서 리소스를 적절히 조정하세요."
}

# 최종 안내 메시지
show_final_instructions() {
  show_step "설치 완료"
  
  show_success "Creditcoin Docker 유틸리티 설정이 완료되었습니다!"
  
  show_warning "변경 사항을 적용하려면 다음 명령어를 실행하세요:"
  echo -e "${BLUE}source $SHELL_PROFILE${NC}"
  
  echo -e "\n${YELLOW}다음으로 add3node.sh 또는 add2node.sh 스크립트를 사용하여 노드를 생성할 수 있습니다.${NC}"
  echo -e "${YELLOW}시스템 모니터링은 'sysinfo' 명령어를 사용할 수 있습니다.${NC}"
  
  # SSH 세션인 경우 데스크톱 앱 설정 강조
  if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    echo -e "\n${YELLOW}중요: OrbStack은 데스크톱 앱에서 관리해야 합니다.${NC}"
    echo -e "${YELLOW}데스크톱 환경에서 OrbStack.app을 실행하고, 자동 시작 옵션을 활성화하세요.${NC}"
  fi
}

# 메인 함수
main() {
  echo -e "${BLUE}=== Creditcoin Docker 유틸리티 설정 (macOS + OrbStack) ===${NC}"
  
  # 환경 확인
  check_environment
  
  # 시간 서버 설정 확인
  check_time_server
  
  # 전원 관리 설정 최적화
  optimize_power_settings
  
  # 기본 도구 설치
  install_homebrew
  install_tools
  
  # OrbStack 설치
  install_orbstack
  
  # 쉘 프로필 설정
  add_to_shell_profile
  
  # 리소스 권장 설정 안내
  show_resource_recommendations
  
  # 최종 안내
  show_final_instructions
}

# 스크립트 실행
main