#!/bin/bash
# setup.sh - Creditcoin Docker 유틸리티 설정 스크립트 (macOS + OrbStack 환경용)

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

# macOS 환경 확인
check_environment() {
  show_step "시스템 환경 확인 중"
  
  # macOS 확인
  if [[ "$(uname)" != "Darwin" ]]; then
    show_error "이 스크립트는 macOS 전용입니다."
    exit 1
  fi
  
  # 아키텍처 확인
  ARCH=$(uname -m)
  
  if [[ "$ARCH" == "arm64" ]]; then
    show_success "감지된 아키텍처: $ARCH (Apple Silicon)"
    export ARCH="arm64"
  elif [[ "$ARCH" == "x86_64" ]]; then
    show_success "감지된 아키텍처: $ARCH (Intel Mac)"
    export ARCH="x86_64"
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
    export SHELL_TYPE="zsh"
    export SHELL_PROFILE="$HOME/.zshrc"
  else
    show_success "기본 쉘: bash 또는 기타"
    export SHELL_TYPE="bash"
    export SHELL_PROFILE="$HOME/.bash_profile"
  fi
  
  # Xcode 명령줄 도구 확인
  if ! xcode-select -p &> /dev/null; then
    show_warning "Xcode 명령줄 도구가 설치되어 있지 않습니다."
    show_warning "macOS에 직접 로그인한 후 'xcode-select --install' 명령을 실행하고 다시 시도하세요."
    exit 1
  else
    show_success "Xcode 명령줄 도구가 설치되어 있습니다."
  fi
  
  show_success "환경 확인이 완료되었습니다."
}

# Homebrew 설치 함수
install_homebrew() {
  show_step "Homebrew 설치 확인 중"
  
  if ! command -v brew &> /dev/null; then
    show_warning "Homebrew가 설치되어 있지 않습니다. 설치를 시작합니다..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Homebrew PATH 설정 
    if [[ "$ARCH" == "arm64" ]]; then
      # Apple Silicon
      show_warning "Apple Silicon용 Homebrew 경로를 설정합니다..."
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$SHELL_PROFILE"
      eval "$(/opt/homebrew/bin/brew shellenv)"
    else
      # Intel Mac
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

# OrbStack 설치 함수
install_orbstack() {
  show_step "OrbStack 설치 확인 중"
  
  # OrbStack이 설치되어 있는지 확인
  if [ -d "/Applications/OrbStack.app" ]; then
    show_success "OrbStack이 이미 설치되어 있습니다."
    
    # OrbStack CLI 명령어 확인
    if command -v orb &> /dev/null; then
      show_success "OrbStack CLI(orb)가 PATH에 추가되어 있습니다."
    else
      show_warning "OrbStack CLI가 PATH에 없습니다."
      
      # PATH에 OrbStack CLI 추가 시도
      if [ -f "/Applications/OrbStack.app/Contents/MacOS/orb" ]; then
        show_warning "OrbStack CLI를 PATH에 추가합니다..."
        export PATH="/Applications/OrbStack.app/Contents/MacOS:$PATH"
        
        # 쉘 프로필에 추가
        if ! grep -q "/Applications/OrbStack.app/Contents/MacOS" "$SHELL_PROFILE"; then
          echo 'export PATH="/Applications/OrbStack.app/Contents/MacOS:$PATH"' >> "$SHELL_PROFILE"
        fi
      fi
    fi
  else
    show_warning "OrbStack이 설치되어 있지 않습니다. 설치를 시작합니다..."
    
    # Homebrew를 통해 설치
    brew install orbstack
    
    if [ -d "/Applications/OrbStack.app" ]; then
      show_success "OrbStack이 설치되었습니다."
      
      # OrbStack 자동으로 시작 설정
      defaults write com.orbstack.OrbStack LaunchAtLogin -bool true
    else
      show_error "OrbStack 설치에 실패했습니다."
      exit 1
    fi
  fi
  
  # Docker CLI 경로 설정
  if ! command -v docker &> /dev/null; then
    show_warning "Docker CLI가 PATH에 없습니다. 경로를 추가합니다..."
    
    if [ -f "/Applications/OrbStack.app/Contents/MacOS/xbin/docker" ]; then
      export PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:$PATH"
      # 쉘 프로필에 추가 (중복 체크)
      if ! grep -q "/Applications/OrbStack.app/Contents/MacOS/xbin" "$SHELL_PROFILE"; then
        echo 'export PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:$PATH"' >> "$SHELL_PROFILE"
      fi
      show_success "Docker CLI 경로가 PATH에 추가되었습니다."
    fi
  fi
  
  # Docker 호스트 설정 (SSH 세션 호환성)
  export DOCKER_HOST="unix://$HOME/.orbstack/run/docker.sock"
  
  # Docker 키체인 인증 비활성화 (SSH 세션 호환성)
  export DOCKER_CLI_NO_CREDENTIAL_STORE=1
  
  # OrbStack 시작 시도 (CLI만 사용)
  if command -v orb &> /dev/null; then
    show_warning "OrbStack 시작 시도 중..."
    orb start
    sleep 5
  fi
  
  # Docker 실행 상태 확인
  if ! docker info &> /dev/null; then
    show_error "Docker 엔진(OrbStack)이 실행 중이 아닙니다."
    if command -v orb &> /dev/null; then
      orb start
      sleep 5
      
      # 다시 확인
      if ! docker info &> /dev/null; then
        show_error "Docker 엔진(OrbStack)을 시작할 수 없습니다."
        exit 1
      else
        show_success "Docker 엔진(OrbStack)이 시작되었습니다."
      fi
    else
      show_error "orb 명령어를 찾을 수 없습니다."
      exit 1
    fi
  else
    show_success "Docker 엔진(OrbStack)이 실행 중입니다."
  fi
}

# 필요한 도구 설치
install_tools() {
  show_step "필요한 도구 설치 중"
  
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

# 의존성 확인 및 설치
install_dependencies() {
  show_step "필요한 의존성 설치 중"
  
  # Homebrew 설치
  install_homebrew
  
  # OrbStack 설치
  install_orbstack
  
  # 필요한 도구 설치
  install_tools
  
  show_success "모든 필요한 의존성이 설치되었습니다."
}

# 쉘 프로필에 추가
add_to_shell_profile() {
  local marker="# === Creditcoin Docker Utils ==="
  
  # zsh 또는 bash 확인
  if [[ "$SHELL" == *"zsh"* ]]; then
    PROFILE_FILE="$HOME/.zshrc"
    show_warning "zsh 쉘이 감지되었습니다. ~/.zshrc에 설정을 추가합니다."
  else
    PROFILE_FILE="$HOME/.bash_profile"
    show_warning "bash 쉘이 감지되었습니다. ~/.bash_profile에 설정을 추가합니다."
  fi
  
  # 이미 추가되었는지 확인
  if grep -q "$marker" "$PROFILE_FILE" 2>/dev/null; then
    show_warning "이미 $PROFILE_FILE에 설정이 추가되어 있습니다."
    
    # 기존 설정 백업
    cp "$PROFILE_FILE" "${PROFILE_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    show_warning "$PROFILE_FILE 백업 파일이 생성되었습니다: ${PROFILE_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    
    # 기존 설정 블록 제거
    awk -v marker="$marker" 'BEGIN{skip=0;} /^# === Creditcoin Docker Utils ===$/{ skip=1; next } /^# === End Creditcoin Docker Utils ===$/{ skip=0; next } !skip{ print $0 }' "$PROFILE_FILE" > "${PROFILE_FILE}.tmp"
    mv "${PROFILE_FILE}.tmp" "$PROFILE_FILE"
    
    show_warning "기존 Creditcoin Docker Utils 설정이 제거되었습니다."
  fi
  
  # 프로필 파일에 추가
  cat >> "$PROFILE_FILE" << EOF

$marker
# Creditcoin Docker 설치 경로
CREDITCOIN_DIR="$SCRIPT_DIR"
CREDITCOIN_UTILS="\$CREDITCOIN_DIR/creditcoin-utils.sh"

# OrbStack Docker CLI 경로 추가
if [ -f "/Applications/OrbStack.app/Contents/MacOS/xbin/docker" ]; then
    export PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:\$PATH"
fi

# OrbStack CLI 경로 추가
if [ -f "/Applications/OrbStack.app/Contents/MacOS/orb" ]; then
    export PATH="/Applications/OrbStack.app/Contents/MacOS:\$PATH"
fi

# OrbStack Docker 호스트 설정 (SSH 세션 호환성)
export DOCKER_HOST="unix://\$HOME/.orbstack/run/docker.sock"

# Docker 키체인 인증 비활성화 (SSH 세션 호환성)
export DOCKER_CLI_NO_CREDENTIAL_STORE=1

# 유틸리티 함수 로드
if [ -f "\$CREDITCOIN_UTILS" ]; then
    source "\$CREDITCOIN_UTILS"
fi
# === End Creditcoin Docker Utils ===
EOF

  show_success "$PROFILE_FILE에 유틸리티가 추가되었습니다."
}

# 메인 함수
main() {
  echo -e "${BLUE}=== Creditcoin Docker 유틸리티 설정 (OrbStack) ===${NC}"

  # 환경 확인
  check_environment

  # 의존성 확인 및 설치
  install_dependencies

  # 자동 시작 설정
  defaults write com.orbstack.OrbStack LaunchAtLogin -bool true

  # 쉘 프로필에 추가
  add_to_shell_profile

  # 마무리 메시지
  show_success "설치가 완료되었습니다!"
  show_warning "변경 사항을 적용하려면 터미널을 다시 시작하거나 다음 명령어를 실행하세요:"

  if [[ "$SHELL" == *"zsh"* ]]; then
    echo -e "${BLUE}source ~/.zshrc${NC}"
  else
    echo -e "${BLUE}source ~/.bash_profile${NC}"
  fi

  echo -e "\n${YELLOW}다음으로 add3node.sh 또는 add2node.sh 스크립트를 사용하여 노드를 생성할 수 있습니다.${NC}"
}

# 메인 함수 실행
main