#!/bin/bash
# setup.sh - Creditcoin Docker 유틸리티 설정 스크립트 (macOS 환경용)

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 현재 디렉토리 저장
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# VS Code 편집기 확인 변수
HAS_VSCODE=false

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
    show_warning "Xcode 명령줄 도구가 설치되어 있지 않습니다. 설치를 시작합니다..."
    xcode-select --install
    
    show_warning "Xcode 명령줄 도구 설치 창이 나타납니다."
    show_warning "설치를 완료하면 엔터를 눌러 계속하세요..."
    read -p ""
  else
    show_success "Xcode 명령줄 도구가 설치되어 있습니다."
  fi
  
  # VS Code 확인
  if command -v code &> /dev/null; then
    show_success "VS Code가 설치되어 있고 PATH에 추가되어 있습니다."
    HAS_VSCODE=true
  elif [ -d "/Applications/Visual Studio Code.app" ]; then
    show_warning "VS Code가 설치되어 있지만 PATH에 추가되어 있지 않습니다."
    show_warning "VS Code에서 'Shell Command: Install code command in PATH'를 실행하여 PATH에 추가하세요."
    HAS_VSCODE=true
  else
    show_warning "VS Code가 설치되어 있지 않은 것 같습니다. TextEdit을 기본 에디터로 사용합니다."
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
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
      eval "$(/opt/homebrew/bin/brew shellenv)"
    else
      # Intel Mac
      echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.bash_profile
      eval "$(/usr/local/bin/brew shellenv)"
    fi
    
    show_success "Homebrew가 설치되었습니다."
  else
    show_success "Homebrew가 이미 설치되어 있습니다."
  fi
  
  # Homebrew 업데이트
  show_warning "Homebrew 업데이트 중..."
  brew update
  
  # 완성 스크립트 문제를 감지하고 해결
  if [[ "$SHELL" == *"zsh"* ]]; then
    # Homebrew 접두사 확인
    BREW_PREFIX=$(brew --prefix)
    
    # 완성 스크립트 디렉토리 확인
    if [ ! -d "${BREW_PREFIX}/share/zsh/site-functions" ]; then
      show_warning "zsh 완성 스크립트 디렉토리가 없습니다. 생성합니다..."
      mkdir -p "${BREW_PREFIX}/share/zsh/site-functions"
    fi
    
    # 완성 스크립트 문제 해결
    show_warning "Homebrew 완성 스크립트를 설정합니다..."
    brew completions link
  fi
}

# Docker Desktop 설치 함수
install_docker_desktop() {
  show_step "Docker Desktop 설치 확인 중"
  
  # Docker 명령어 확인
  if ! command -v docker &> /dev/null; then
    show_warning "Docker Desktop이 설치되어 있지 않거나 PATH에 추가되지 않았습니다."
    
    if [ -d "/Applications/Docker.app" ]; then
      show_warning "Docker.app이 설치되어 있지만 PATH에 추가되지 않았습니다."
      
      # Docker 실행
      open -a Docker
      show_warning "Docker Desktop을 시작했습니다. 초기화될 때까지 기다려 주세요..."
      
    else
      show_warning "Docker Desktop을 설치합니다. Homebrew를 사용합니다..."
      brew install --cask docker
      
      show_warning "Docker Desktop이 설치되었습니다. 시작하려면 Applications 폴더에서 Docker 앱을 실행하세요."
      open -a Docker
      show_warning "Docker Desktop을 시작했습니다. 초기화될 때까지 기다려 주세요..."
    fi
    
    show_warning "Docker Desktop이 초기화를 완료할 때까지 기다립니다 (약 30초)..."
    sleep 30
    
    # 여전히 Docker가 시작되지 않았다면 사용자에게 알림
    if ! docker info &> /dev/null; then
      show_warning "Docker Desktop이 아직 시작되지 않았습니다."
      show_warning "Docker Desktop이 완전히 시작된 후 엔터 키를 눌러 계속하세요..."
      read -p ""
    fi
  else
    show_success "Docker Desktop이 설치되어 있습니다."
  fi
  
  # Docker 실행 상태 확인
  if ! docker info &> /dev/null; then
    show_error "Docker Desktop이 실행 중이 아닙니다."
    show_warning "Applications 폴더에서 Docker 앱을 실행한 후 이 스크립트를 다시 실행하세요."
    exit 1
  else
    show_success "Docker Desktop이 실행 중입니다."
  fi
  
  # Docker Compose 확인
  if ! docker compose version &> /dev/null; then
    show_warning "Docker Compose V2가 감지되지 않았습니다."
    show_warning "최신 Docker Desktop에는 Docker Compose V2가 포함되어 있어야 합니다."
    show_warning "Docker Desktop을 업데이트하는 것을 권장합니다."
  else
    show_success "Docker Compose가 설치되어 있습니다: $(docker compose version | head -n 1)"
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
  
  # Docker Desktop 설치
  install_docker_desktop
  
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

# 유틸리티 함수 로드
if [ -f "\$CREDITCOIN_UTILS" ]; then
    source "\$CREDITCOIN_UTILS"
fi
# === End Creditcoin Docker Utils ===
EOF

  show_success "$PROFILE_FILE에 유틸리티가 추가되었습니다."
}

# Docker Desktop 리소스 권장 설정 안내
show_docker_resource_recommendations() {
  show_step "Docker Desktop 리소스 권장 설정"
  show_warning "Creditcoin 노드는 리소스를 많이 사용합니다. Docker Desktop 설정에서 다음과 같이 리소스를 조정하는 것이 좋습니다:"
  echo -e "${GREEN}1. CPU: 4코어 이상${NC}"
  echo -e "${GREEN}2. 메모리: 8GB 이상${NC}"
  echo -e "${GREEN}3. 디스크 이미지 크기: 100GB 이상${NC}"
  show_warning "설정을 변경하려면 Docker Desktop 애플리케이션 > 설정 > 리소스에서 조정하세요."
}

# 메인 함수
main() {
  echo -e "${BLUE}=== Creditcoin Docker 유틸리티 설정 ===${NC}"

  # 환경 확인
  check_environment

  # 의존성 확인 및 설치
  install_dependencies

  # 쉘 프로필에 추가
  add_to_shell_profile

  # Docker 리소스 권장 설정 안내
  show_docker_resource_recommendations

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