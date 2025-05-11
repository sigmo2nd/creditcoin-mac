#!/bin/bash
# setup.sh - Creditcoin Docker 유틸리티 설정 스크립트 (macOS + OrbStack 환경용)
# 이 스크립트는 macOS에서 Creditcoin 노드 운영을 위한 환경을 설정합니다.
# 기능: OrbStack 설치, FileVault 확인, 시스템 절전 모드 비활성화, 런치데몬 설정

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
    show_warning "Xcode 명령줄 도구가 설치되어 있지 않습니다. 설치를 시작합니다..."
    xcode-select --install
    
    show_warning "Xcode 명령줄 도구 설치 창이 나타납니다."
    show_warning "설치를 완료하면 엔터를 눌러 계속하세요..."
    read -p ""
  else
    show_success "Xcode 명령줄 도구가 설치되어 있습니다."
  fi
  
  show_success "환경 확인이 완료되었습니다."
}

# FileVault 상태 확인 함수
check_filevault() {
  show_step "FileVault 상태 확인 중"
  
  # FileVault 상태 확인
  FILEVAULT_STATUS=$(fdesetup status)
  
  if [[ "$FILEVAULT_STATUS" == *"FileVault is On"* ]]; then
    show_warning "FileVault가 활성화되어 있습니다."
    show_warning "FileVault는 디스크 암호화로 인해 OrbStack 성능에 영향을 줄 수 있습니다."
    show_warning "최적의 성능을 위해 FileVault 해제를 권장합니다."
    
    # 해제 방법 안내
    echo ""
    echo -e "${YELLOW}===== FileVault 해제 방법 =====${NC}"
    echo "1. 시스템 환경설정(또는 시스템 설정) 열기"
    echo "2. '보안 및 개인 정보 보호' 선택"
    echo "3. 'FileVault' 탭 선택"
    echo "4. '해제' 버튼 클릭"
    echo "5. 관리자 암호 입력"
    echo "6. 컴퓨터 재시작으로 암호화 해제 과정이 완료됩니다."
    echo ""
    
    # 해제 확인 절차
    read -p "지금 시스템 설정에서 FileVault 설정을 열까요? (y/N) " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      if [[ -d "/System/Applications/System Settings.app" ]]; then
        # macOS Ventura 이상
        open "/System/Applications/System Settings.app"
        show_warning "시스템 설정에서 '개인 정보 보호 및 보안 > FileVault'로 이동하세요."
      else
        # macOS Monterey 이하
        open "x-apple.systempreferences:com.apple.preference.security?FileVault"
      fi
    fi
    
    echo ""
    show_warning "FileVault 해제는 시간이 오래 걸릴 수 있으며, 디스크 크기에 따라 수 시간이 소요될 수 있습니다."
    show_warning "해제 과정 중에도 설치를 계속 진행합니다."
  else
    show_success "FileVault가 비활성화되어 있습니다. OrbStack 성능에 최적화되어 있습니다."
  fi
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
      show_warning "OrbStack CLI가 PATH에 없습니다. OrbStack 앱을 실행하여 초기 설정을 완료하세요."
      open -a OrbStack
      show_warning "OrbStack이 완전히 시작될 때까지 기다려 주세요..."
      sleep 5
    fi
  else
    show_warning "OrbStack이 설치되어 있지 않습니다. 설치를 시작합니다..."
    
    # Homebrew를 통해 설치
    brew install orbstack
    
    if [ -d "/Applications/OrbStack.app" ]; then
      show_success "OrbStack이 설치되었습니다."
      
      # OrbStack 실행
      open -a OrbStack
      show_warning "OrbStack이 완전히 시작될 때까지 기다려 주세요..."
      sleep 10
    else
      show_error "OrbStack 설치에 실패했습니다."
      show_warning "수동으로 설치를 시도하세요: https://orbstack.dev/download"
      exit 1
    fi
  fi
  
  # Docker CLI 경로 설정
  if ! command -v docker &> /dev/null; then
    show_warning "Docker CLI가 PATH에 없습니다. 경로를 추가합니다..."
    
    if [ -f "/Applications/OrbStack.app/Contents/MacOS/xbin/docker" ]; then
      export PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:$PATH"
      # 쉘 프로필에 추가
      if [[ "$SHELL" == *"zsh"* ]]; then
        echo 'export PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:$PATH"' >> ~/.zshrc
      else
        echo 'export PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:$PATH"' >> ~/.bash_profile
      fi
      show_success "Docker CLI 경로가 PATH에 추가되었습니다."
    else
      show_warning "Docker CLI를 찾을 수 없습니다. OrbStack이 제대로 설치되었는지 확인하세요."
    fi
  fi
  
  # Docker 호스트 설정 (SSH 세션 호환성)
  export DOCKER_HOST="unix://$HOME/.orbstack/run/docker.sock"
  
  # Docker 키체인 인증 비활성화 (SSH 세션 호환성)
  export DOCKER_CLI_NO_CREDENTIAL_STORE=1
  
  # Docker 실행 상태 확인
  if ! docker info &> /dev/null; then
    show_warning "Docker 엔진(OrbStack)이 실행 중이 아닙니다. 시작을 시도합니다..."
    orb start
    sleep 10
    
    # 다시 확인
    if ! docker info &> /dev/null; then
      show_error "Docker 엔진(OrbStack)을 시작할 수 없습니다."
      exit 1
    else
      show_success "Docker 엔진(OrbStack)이 시작되었습니다."
    fi
  else
    show_success "Docker 엔진(OrbStack)이 실행 중입니다."
  fi
  
  # Docker Compose 확인
  if ! docker compose version &> /dev/null; then
    show_warning "Docker Compose가 감지되지 않았습니다."
    show_warning "OrbStack에는 Docker Compose가 포함되어 있어야 합니다."
    show_warning "OrbStack을 최신 버전으로 업데이트하는 것을 권장합니다."
  else
    show_success "Docker Compose가 설치되어 있습니다: $(docker compose version | head -n 1)"
  fi
}

# OrbStack 런치데몬 설정 함수 (시스템 부팅 시 실행, 로그인 불필요)
setup_orbstack_launchdaemon() {
  show_step "OrbStack 런치데몬 설정 중 (시스템 부팅 시 자동 실행)"
  
  # OrbStack이 설치되어 있는지 확인
  if [ ! -d "/Applications/OrbStack.app" ]; then
    show_warning "OrbStack이 설치되어 있지 않아 런치데몬을 설정할 수 없습니다."
    return 1
  fi
  
  # 현재 사용자 이름 가져오기 (참고용)
  local CURRENT_USER=$(whoami)
  
  # 런치데몬 plist 파일 경로
  local LAUNCH_DAEMON_DIR="/Library/LaunchDaemons"
  local LAUNCH_DAEMON_FILE="${LAUNCH_DAEMON_DIR}/dev.orbstack.daemon.plist"
  
  # 관리자 권한 확인
  if [ ! -w "$LAUNCH_DAEMON_DIR" ]; then
    show_warning "런치데몬 설정을 위해 관리자 권한이 필요합니다."
    show_warning "암호를 묻는 창이 뜨면 사용자 암호를 입력하세요."
  fi
  
  # 다른 버전의 런치데몬 파일이 있는지 확인
  if sudo test -f "$LAUNCH_DAEMON_FILE"; then
    show_warning "OrbStack 런치데몬 파일이 이미 존재합니다. 백업 후 새로 설정합니다."
    sudo cp "$LAUNCH_DAEMON_FILE" "${LAUNCH_DAEMON_FILE}.bak.$(date +%Y%m%d%H%M%S)"
  fi
  
  # 새 런치데몬 파일 생성 (시스템 수준에서 실행, 사용자 로그인 전에 실행됨)
  cat > /tmp/orbstack_daemon.plist << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.orbstack.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/OrbStack.app/Contents/MacOS/orb-service</string>
        <string>daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/orbstack-daemon.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/orbstack-daemon.log</string>
    <key>UserName</key>
    <string>root</string>
    <key>ProcessType</key>
    <string>Background</string>
    <key>AbandonProcessGroup</key>
    <true/>
</dict>
</plist>
EOL
  
  # 런치데몬 파일 복사 및 권한 설정
  sudo cp /tmp/orbstack_daemon.plist "$LAUNCH_DAEMON_FILE"
  sudo chown root:wheel "$LAUNCH_DAEMON_FILE"
  sudo chmod 644 "$LAUNCH_DAEMON_FILE"
  
  # 임시 파일 삭제
  rm /tmp/orbstack_daemon.plist
  
  # 기존 런치데몬 중지 (있는 경우)
  if sudo launchctl list | grep -q "dev.orbstack.daemon"; then
    show_warning "기존 OrbStack 런치데몬을 중지합니다..."
    sudo launchctl unload "$LAUNCH_DAEMON_FILE"
  fi
  
  # 새 런치데몬 로드
  show_warning "OrbStack 런치데몬을 로드합니다..."
  sudo launchctl load "$LAUNCH_DAEMON_FILE"
  
  # OrbStack 서비스 권한 설정 (루트로 실행되지만 더 엄격한 권한 설정)
  if [ -f "/Applications/OrbStack.app/Contents/MacOS/orb-service" ]; then
    show_warning "OrbStack 서비스 실행 권한을 설정합니다..."
    sudo chown root:wheel "/Applications/OrbStack.app/Contents/MacOS/orb-service"
    sudo chmod 4755 "/Applications/OrbStack.app/Contents/MacOS/orb-service"
    
    # OrbStack 관련 디렉토리 권한 설정 (필요한 경우)
    if [ -d "/Library/Application Support/OrbStack" ]; then
      sudo chmod -R 755 "/Library/Application Support/OrbStack"
    fi
  fi
  
  # 필요한 하위 디렉토리 생성 (시스템 부팅 시 필요할 수 있음)
  sudo mkdir -p "/var/run/orbstack"
  sudo chmod 777 "/var/run/orbstack"
  
  # OrbStack 시스템 설정 보안 이슈 해결
  defaults write com.apple.security.syspolicy.kernel-extension-policy AllowUnknownSystemExtensions -bool true
  
  # 시스템 부팅 시 OrbStack 데몬이 자동 실행됨을 알림
  show_success "OrbStack 런치데몬이 설정되었습니다. 이제 시스템 부팅 시 자동으로 시작됩니다."
  show_success "중요: 로그인 전에도 OrbStack 데몬이 실행되므로 SSH 접속으로 즉시 컨테이너를 관리할 수 있습니다."
}

# 시스템 절전 모드 설정 함수 (pmset만 사용)
configure_power_management() {
  show_step "시스템 절전 모드 설정 중 (시스템 잠자기 방지)"
  
  # 현재 절전 모드 설정 백업
  show_warning "현재 전원 관리 설정을 백업합니다..."
  local BACKUP_DATE=$(date +%Y%m%d%H%M%S)
  local BACKUP_FILE="/tmp/pmset_backup_${BACKUP_DATE}.txt"
  sudo pmset -g > "$BACKUP_FILE"
  show_success "현재 설정이 백업되었습니다: $BACKUP_FILE"
  
  # 현재 절전 모드 설정 표시
  echo -e "${YELLOW}현재 전원 관리 설정:${NC}"
  sudo pmset -g
  echo ""
  
  # 절전 모드 비활성화 확인
  echo -e "${YELLOW}서버 운영을 위해 시스템 절전 모드를 비활성화하시겠습니까? (y/N)${NC}"
  read -p "" DISABLE_SLEEP
  
  if [[ "$DISABLE_SLEEP" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    show_warning "시스템 절전 모드를 비활성화합니다..."
    
    # AC 전원 설정 (콘센트 연결 시) - 기본 서버 설정
    # sleep=0: 시스템 절전 모드 비활성화
    # disksleep=0: 디스크 절전 모드 비활성화
    # womp=1: Wake on LAN 활성화
    # networkoversleep=0: 네트워크 접근 시 절전 모드에서 깨어남
    # ttyskeepawake=1: SSH/터미널 연결 시 시스템 깨어 있음
    # autorestart=1: 시스템 충돌 시 자동 재시작
    sudo pmset -c sleep 0 disksleep 0 womp 1 networkoversleep 0 ttyskeepawake 1 autorestart 1
    
    # 배터리 설정 (노트북인 경우)
    if pmset -g | grep -q "Battery Power"; then
      echo -e "${YELLOW}노트북을 위한 배터리 설정:${NC}"
      echo -e "${YELLOW}배터리 사용 중 시스템 절전 모드도 비활성화하시겠습니까? (y/N)${NC}"
      echo -e "${RED}주의: 배터리 설정 비활성화는 배터리 수명을 크게 단축시킬 수 있습니다.${NC}"
      read -p "" DISABLE_BATTERY_SLEEP
      
      if [[ "$DISABLE_BATTERY_SLEEP" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        # 배터리 사용 시 절전 방지 설정
        sudo pmset -b sleep 0 disksleep 0 ttyskeepawake 1
        show_warning "배터리 사용 중에도 절전 모드가 비활성화되었습니다."
      else
        # 배터리 사용 시 기본 설정은 변경하지 않음
        show_success "배터리 사용 시 기본 절전 설정을 유지합니다."
      fi
    fi
    
    # 전원 버튼 누를 때 잠자기 방지 (macOS 버전에 따라 다를 수 있음)
    if [[ $(sw_vers -productVersion | cut -d. -f1) -ge 11 ]]; then
      # Big Sur 이상
      sudo pmset powerbutton 0
    else
      # Catalina 이하
      sudo pmset powerbuttonssleep 0
    fi
    
    show_success "시스템 절전 모드가 비활성화되었습니다. 이제 서버가 자동으로 절전 모드로 전환되지 않습니다."
    show_success "디스플레이 절전 설정은 기존 설정을 유지합니다 (전력 소비 절약을 위해)."
  else
    show_warning "전원 설정이 변경되지 않았습니다. 기본 설정을 유지합니다."
  fi
  
  # 변경된 설정 표시
  echo -e "${GREEN}새로운 전원 관리 설정:${NC}"
  sudo pmset -g
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

# OrbStack 리소스 권장 설정 안내
show_orbstack_resource_recommendations() {
  show_step "OrbStack 리소스 권장 설정"
  show_warning "Creditcoin 노드는 리소스를 많이 사용합니다. 다음과 같은 리소스 설정을 권장합니다:"
  echo -e "${GREEN}1. CPU: 4코어 이상${NC}"
  echo -e "${GREEN}2. 메모리: 8GB 이상${NC}"
  echo -e "${GREEN}3. 디스크 공간: 100GB 이상${NC}"
  show_warning "OrbStack은 기본적으로 시스템 리소스를 자동으로 관리하지만, 필요한 경우 설정에서 조정할 수 있습니다."
  show_warning "설정을 확인하려면 OrbStack 앱을 열고 설정(Settings) > 리소스(Resources)에서 확인하세요."
}

# 메인 함수
main() {
  echo -e "${BLUE}=== Creditcoin Docker 유틸리티 설정 (OrbStack) ===${NC}"

  # 환경 확인
  check_environment

  # FileVault 상태 확인
  check_filevault

  # 의존성 확인 및 설치
  install_dependencies

  # 시스템 절전 모드 설정
  configure_power_management

  # OrbStack 런치데몬 설정
  setup_orbstack_launchdaemon

  # 쉘 프로필에 추가
  add_to_shell_profile

  # OrbStack 리소스 권장 설정 안내
  show_orbstack_resource_recommendations

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