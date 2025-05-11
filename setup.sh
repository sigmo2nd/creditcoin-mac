#!/bin/bash
# setup.sh - Creditcoin Docker 유틸리티 설정 스크립트 (macOS + OrbStack 환경용)
# 이 스크립트는 macOS에서 Creditcoin 노드 운영을 위한 환경을 설정합니다.

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 현재 디렉토리 저장
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# 관리자 권한 확인
IS_ADMIN=false
if groups | grep -q -w admin; then
  IS_ADMIN=true
fi

# 메시지 출력 함수들
show_step() {
  echo -e "\n${BLUE}=== $1 ===${NC}"
}

show_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

show_warning() {
  echo -e "${YELLOW}! $1${NC}"
}

show_error() {
  echo -e "${RED}✗ $1${NC}"
}

# 관리자 권한으로 명령 실행
run_as_admin() {
  sudo "$@"
  return $?
}

# 시스템 환경 체크
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
  
  # SSH 세션 확인
  if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    show_success "SSH 세션으로 접속 중입니다."
    export SSH_SESSION=true
  else
    show_success "로컬 터미널 세션입니다."
    export SSH_SESSION=false
  fi
  
  # 관리자 권한 확인
  if [ "$IS_ADMIN" = true ]; then
    show_success "관리자 권한으로 필요한 모든 설정을 수행할 수 있습니다."
  else
    show_warning "관리자 권한이 없습니다. 일부 설정은 건너뛰게 됩니다."
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

# Homebrew 설치
install_homebrew() {
  show_step "Homebrew 설치 확인"
  
  if ! command -v brew &> /dev/null; then
    show_warning "Homebrew가 설치되어 있지 않습니다. 설치를 시작합니다..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Homebrew PATH 설정 
    if [[ "$ARCH" == "arm64" ]]; then
      # Apple Silicon
      show_warning "Apple Silicon용 Homebrew 경로를 설정합니다..."
      if [[ "$SHELL_TYPE" == "zsh" ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
      else
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.bash_profile
      fi
      eval "$(/opt/homebrew/bin/brew shellenv)"
    else
      # Intel Mac
      if [[ "$SHELL_TYPE" == "zsh" ]]; then
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
      else
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.bash_profile
      fi
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
    else
      show_error "OrbStack 설치에 실패했습니다."
      show_warning "수동으로 설치를 시도하세요: https://orbstack.dev/download"
      exit 1
    fi
  fi
  
  # OrbStack CLI 확인
  if command -v orb &> /dev/null; then
    show_success "OrbStack CLI가 PATH에 추가되어 있습니다."
  else
    show_warning "OrbStack CLI를 PATH에 추가합니다..."
    if [ -f "/Applications/OrbStack.app/Contents/MacOS/orb" ]; then
      if [[ "$SHELL_TYPE" == "zsh" ]]; then
        echo 'export PATH="/Applications/OrbStack.app/Contents/MacOS:$PATH"' >> ~/.zshrc
      else
        echo 'export PATH="/Applications/OrbStack.app/Contents/MacOS:$PATH"' >> ~/.bash_profile
      fi
      export PATH="/Applications/OrbStack.app/Contents/MacOS:$PATH"
      show_success "OrbStack CLI가 PATH에 추가되었습니다."
    fi
  fi
  
  # Docker CLI 경로 설정
  if ! command -v docker &> /dev/null; then
    show_warning "Docker CLI를 PATH에 추가합니다..."
    
    if [ -f "/Applications/OrbStack.app/Contents/MacOS/xbin/docker" ]; then
      export PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:$PATH"
      if [[ "$SHELL_TYPE" == "zsh" ]]; then
        echo 'export PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:$PATH"' >> ~/.zshrc
      else
        echo 'export PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:$PATH"' >> ~/.bash_profile
      fi
      show_success "Docker CLI 경로가 PATH에 추가되었습니다."
    else
      show_warning "Docker CLI를 찾을 수 없습니다. OrbStack이 제대로 설치되었는지 확인하세요."
    fi
  fi
}

# OrbStack 자동 시작 설정
setup_orbstack_autostart() {
  show_step "OrbStack 자동 시작 설정"
  
  if [ "$IS_ADMIN" != true ]; then
    show_warning "일부 설정에는 관리자 권한이 필요합니다."
    show_warning "나중에 'sudo ./setup.sh'로 다시 실행하여 자동 시작을 설정하세요."
    return 1
  fi
  
  # 사용자 확인
  echo -e "${YELLOW}시스템 부팅 시 OrbStack 자동 시작을 설정하시겠습니까? (y/N)${NC}"
  read -p "" setup_autostart
  
  if [[ ! "$setup_autostart" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    show_warning "OrbStack 자동 시작 설정을 건너뜁니다."
    return 0
  fi
  
  # 1. 로그인 항목에 OrbStack 추가
  show_warning "로그인 항목에 OrbStack 추가 중..."
  
  if [[ "$SSH_SESSION" == true ]]; then
    show_warning "SSH 세션에서는 로그인 항목 추가를 건너뛰고 다른 방법을 사용합니다."
  else
    # 로컬 세션에서만 AppleScript 실행
    osascript <<EOT 2>/dev/null
tell application "System Events"
    set loginItems to the name of every login item
    set orbExists to false
    
    repeat with itemName in loginItems
        if itemName is "OrbStack" then
            set orbExists to true
        end if
    end repeat
    
    if orbExists is false then
        make new login item at end with properties {path:"/Applications/OrbStack.app", hidden:false}
    end if
end tell
EOT
    
    if [ $? -eq 0 ]; then
      show_success "OrbStack이 로그인 항목에 추가되었습니다."
    else
      show_warning "로그인 항목 추가에 실패했습니다. 다른 방법을 사용합니다."
    fi
  fi
  
  # 2. OrbStack 자체 자동 시작 설정
  show_warning "OrbStack 자체 자동 시작 설정 중..."
  
  # OrbStack 설정 디렉토리 생성
  mkdir -p "$HOME/Library/Application Support/OrbStack"
  
  # SSH 세션에서는 직접 파일 수정
  if [[ "$SSH_SESSION" == true ]]; then
    # 설정 파일 경로
    PLIST_PATH="$HOME/Library/Preferences/dev.orbstack.plist"
    
    if [ -f "$PLIST_PATH" ]; then
      # 파일이 존재하면 백업
      cp "$PLIST_PATH" "${PLIST_PATH}.bak"
      # defaults 명령 대신 직접 설정
      plutil -replace "app.launch-at-login" -bool true "$PLIST_PATH" 2>/dev/null
    else
      # 파일이 없으면 새로 생성
      echo '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>app.launch-at-login</key>
    <true/>
</dict>
</plist>' > "$PLIST_PATH"
    fi
  else
    # 로컬 세션에서는 defaults 명령 사용
    defaults write dev.orbstack app.launch-at-login -bool true
  fi
  
  show_success "OrbStack 자체 자동 시작 설정이 완료되었습니다."
  
  # 3. 시작 스크립트 생성
  show_warning "시스템 시작 스크립트 생성 중..."
  
  STARTUP_SCRIPT="/usr/local/bin/orbstack-startup.sh"
  
  # 스크립트 내용 생성
  cat > /tmp/orbstack-startup.sh << 'EOT'
#!/bin/bash

# OrbStack 시작 스크립트
LOG_FILE="/var/log/orbstack-startup.log"

echo "$(date): OrbStack 시작 스크립트 실행" > "$LOG_FILE"

# OrbStack이 실행 중인지 확인
if ! pgrep -f "OrbStack" > /dev/null; then
    echo "$(date): OrbStack 시작 중..." >> "$LOG_FILE"
    open -a OrbStack
    sleep 10
else
    echo "$(date): OrbStack이 이미 실행 중입니다." >> "$LOG_FILE"
fi

# Docker 소켓 파일 확인
for i in {1..30}; do
    if [ -S "/var/run/orbstack/docker.sock" ]; then
        echo "$(date): Docker 소켓 파일이 준비되었습니다." >> "$LOG_FILE"
        chmod 777 "/var/run/orbstack/docker.sock"
        
        # 모든 사용자에게 소켓 파일 링크 생성
        for USER_HOME in /Users/*; do
            USER_NAME=$(basename "$USER_HOME")
            if [ -d "$USER_HOME" ] && [ "$USER_NAME" != "Shared" ]; then
                mkdir -p "$USER_HOME/.orbstack/run" 2>/dev/null
                chown -R "$USER_NAME" "$USER_HOME/.orbstack" 2>/dev/null
                ln -sf "/var/run/orbstack/docker.sock" "$USER_HOME/.orbstack/run/docker.sock" 2>/dev/null
                echo "$(date): $USER_NAME 사용자의 Docker 소켓 링크 생성" >> "$LOG_FILE"
            fi
        done
        
        echo "$(date): 모든 설정이 완료되었습니다." >> "$LOG_FILE"
        exit 0
    fi
    echo "$(date): Docker 소켓 대기 중... ($i/30)" >> "$LOG_FILE"
    sleep 2
done

echo "$(date): 시간 내에 Docker 소켓 파일이 생성되지 않았습니다." >> "$LOG_FILE"
exit 1
EOT
  
  # 스크립트 설치 및 권한 설정
  run_as_admin mkdir -p /usr/local/bin
  run_as_admin cp /tmp/orbstack-startup.sh "$STARTUP_SCRIPT"
  run_as_admin chmod +x "$STARTUP_SCRIPT"
  rm -f /tmp/orbstack-startup.sh
  
  # LaunchDaemon 생성
  LAUNCH_DAEMON_FILE="/Library/LaunchDaemons/com.orbstack.startup.plist"
  
  cat > /tmp/orbstack-startup.plist << EOT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.orbstack.startup</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/orbstack-startup.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>StandardOutPath</key>
    <string>/var/log/orbstack-startup-output.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/orbstack-startup-error.log</string>
</dict>
</plist>
EOT
  
  # LaunchDaemon 설치 및 로드
  run_as_admin cp /tmp/orbstack-startup.plist "$LAUNCH_DAEMON_FILE"
  run_as_admin chown root:wheel "$LAUNCH_DAEMON_FILE"
  run_as_admin chmod 644 "$LAUNCH_DAEMON_FILE"
  rm -f /tmp/orbstack-startup.plist
  
  # 기존 LaunchDaemon 언로드 (있는 경우)
  if sudo launchctl list | grep -q "com.orbstack.startup"; then
    run_as_admin launchctl unload "$LAUNCH_DAEMON_FILE"
  fi
  
  # LaunchDaemon 로드
  run_as_admin launchctl load "$LAUNCH_DAEMON_FILE"
  
  # 소켓 디렉토리 생성
  run_as_admin mkdir -p "/var/run/orbstack"
  run_as_admin chmod 777 "/var/run/orbstack"
  
  # OrbStack 시작
  if ! pgrep -f "OrbStack" > /dev/null; then
    show_warning "OrbStack을 시작합니다..."
    open -a OrbStack
    sleep 5
  fi
  
  # 소켓 파일 생성 기다리기
  show_warning "Docker 소켓 파일 생성 대기 중... (최대 30초)"
  for i in {1..30}; do
    if [ -S "/var/run/orbstack/docker.sock" ] || [ -S "$HOME/.orbstack/run/docker.sock" ]; then
      show_success "Docker 소켓 파일이 생성되었습니다."
      break
    fi
    echo -n "."
    sleep 1
  done
  
  if [ ! -S "/var/run/orbstack/docker.sock" ] && [ ! -S "$HOME/.orbstack/run/docker.sock" ]; then
    show_warning "시간 내에 Docker 소켓 파일이 생성되지 않았습니다."
    show_warning "스크립트가 부팅 시 OrbStack을 시작할 것입니다."
  fi
  
  show_success "OrbStack 자동 시작 설정이 완료되었습니다."
  show_success "시스템 부팅 시 OrbStack이 자동으로 시작됩니다."
  
  return 0
}

# 시스템 절전 모드 설정
configure_power_management() {
  show_step "시스템 절전 모드 설정"
  
  # 관리자 권한 확인
  if [ "$IS_ADMIN" != true ]; then
    show_warning "절전 모드 설정에는 관리자 권한이 필요합니다."
    show_warning "이 단계를 건너뛰고 나중에 'sudo pmset -c sleep 0 disksleep 0 womp 1 autorestart 1'로 설정하세요."
    return 0
  fi
  
  # 사용자 확인
  echo -e "${YELLOW}서버 운영을 위해 시스템 절전 모드를 비활성화하시겠습니까? (y/N)${NC}"
  read -p "" DISABLE_SLEEP
  
  if [[ ! "$DISABLE_SLEEP" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    show_warning "전원 설정이 변경되지 않았습니다. 기본 설정을 유지합니다."
    return 0
  fi
  
  # 현재 절전 모드 설정 표시
  echo -e "${YELLOW}현재 전원 관리 설정:${NC}"
  pmset -g
  echo ""
  
  show_warning "시스템 절전 모드를 비활성화합니다..."
  
  # AC 전원 설정 (콘센트 연결 시) - 기본 서버 설정
  run_as_admin pmset -c sleep 0 disksleep 0 womp 1 networkoversleep 0 ttyskeepawake 1 autorestart 1
  
  # 배터리 설정 (노트북인 경우)
  if pmset -g | grep -q "Battery Power"; then
    echo -e "${YELLOW}노트북을 위한 배터리 설정:${NC}"
    echo -e "${YELLOW}배터리 사용 중 시스템 절전 모드도 비활성화하시겠습니까? (y/N)${NC}"
    echo -e "${RED}주의: 배터리 설정 비활성화는 배터리 수명을 크게 단축시킬 수 있습니다.${NC}"
    read -p "" DISABLE_BATTERY_SLEEP
    
    if [[ "$DISABLE_BATTERY_SLEEP" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      # 배터리 사용 시 절전 방지 설정
      run_as_admin pmset -b sleep 0 disksleep 0 ttyskeepawake 1
      show_warning "배터리 사용 중에도 절전 모드가 비활성화되었습니다."
    else
      # 배터리 사용 시 기본 설정은 변경하지 않음
      show_success "배터리 사용 시 기본 절전 설정을 유지합니다."
    fi
  fi
  
  show_success "시스템 절전 모드가 비활성화되었습니다. 이제 서버가 자동으로 절전 모드로 전환되지 않습니다."
  
  # 변경된 설정 표시
  echo -e "${GREEN}새로운 전원 관리 설정:${NC}"
  pmset -g
}

# FileVault 상태 확인
check_filevault() {
  show_step "FileVault 상태 확인"
  
  if [[ "$SSH_SESSION" == true ]]; then
    show_warning "SSH 세션에서는 FileVault 상태를 확인할 수 없습니다."
    return 0
  fi
  
  # FileVault 상태 확인
  FILEVAULT_STATUS=$(fdesetup status 2>/dev/null || echo "FileVault status unknown")
  
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
    
    show_warning "FileVault 해제는 시간이 오래 걸릴 수 있으며, 디스크 크기에 따라 수 시간이 소요될 수 있습니다."
    show_warning "해제 과정 중에도 설치를 계속 진행합니다."
  else
    show_success "FileVault가 비활성화되어 있거나 상태를 확인할 수 없습니다."
  fi
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

# 쉘 프로필에 추가
add_to_shell_profile() {
  show_step "쉘 프로필 설정"
  
  # 마커 문자열 설정
  local marker="# === Creditcoin Docker Utils ==="
  local endmarker="# === End Creditcoin Docker Utils ==="
  
  # 프로필 파일 설정
  if [[ "$SHELL_TYPE" == "zsh" ]]; then
    PROFILE_FILE="$HOME/.zshrc"
    show_success "zsh 쉘이 감지되었습니다. $PROFILE_FILE에 설정을 추가합니다."
  else
    PROFILE_FILE="$HOME/.bash_profile"
    show_success "bash 쉘이 감지되었습니다. $PROFILE_FILE에 설정을 추가합니다."
  fi
  
  # 이미 추가되었는지 확인
  if grep -q "$marker" "$PROFILE_FILE" 2>/dev/null; then
    show_warning "이미 $PROFILE_FILE에 설정이 추가되어 있습니다."
    
    # 기존 설정 백업
    cp "$PROFILE_FILE" "${PROFILE_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    show_success "$PROFILE_FILE 백업 파일이 생성되었습니다."
    
    # 기존 설정 블록 제거
    sed -i.bak "/$marker/,/$endmarker/d" "$PROFILE_FILE"
    show_success "기존 Creditcoin Docker Utils 설정이 제거되었습니다."
  fi
  
  # 프로필 파일에 추가
  cat >> "$PROFILE_FILE" << EOT
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

# OrbStack 시작 확인 및 시작 (SSH 세션에서)
orbstack_check() {
    # OrbStack이 실행 중인지 확인
    if ! pgrep -x "OrbStack" > /dev/null && [ -d "/Applications/OrbStack.app" ]; then
        echo "OrbStack을 시작합니다..."
        open -a OrbStack
        # 소켓 생성 대기
        for i in {1..10}; do
            if [ -S "\$HOME/.orbstack/run/docker.sock" ]; then
                echo "Docker 소켓이 준비되었습니다."
                break
            fi
            echo -n "."
            sleep 1
        done
    fi
}

# SSH 세션일 경우 OrbStack 확인
if [ -n "\$SSH_CLIENT" ] || [ -n "\$SSH_TTY" ]; then
    orbstack_check
fi

# 유틸리티 함수 로드
if [ -f "\$CREDITCOIN_UTILS" ]; then
    source "\$CREDITCOIN_UTILS"
fi
$endmarker
EOT

  show_success "$PROFILE_FILE에 유틸리티가 추가되었습니다."
  
  # 소켓 디렉토리 생성
  mkdir -p "$HOME/.orbstack/run"
}

# 리소스 권장 설정 안내
show_resource_recommendations() {
  show_step "리소스 권장 설정"
  
  show_warning "Creditcoin 노드는 리소스를 많이 사용합니다. 다음과 같은 리소스 설정을 권장합니다:"
  echo -e "${GREEN}1. CPU: 4코어 이상${NC}"
  echo -e "${GREEN}2. 메모리: 8GB 이상${NC}"
  echo -e "${GREEN}3. 디스크 공간: 100GB 이상${NC}"
  
  if [[ "$SSH_SESSION" != true ]]; then
    show_warning "OrbStack은 기본적으로 시스템 리소스를 자동으로 관리하지만, 필요한 경우 설정에서 조정할 수 있습니다."
    show_warning "설정을 확인하려면 OrbStack 앱을 열고 설정(Settings) > 리소스(Resources)에서 확인하세요."
  fi
}

# 최종 안내 메시지
show_final_instructions() {
  show_step "설치 완료"
  
  show_success "Creditcoin Docker 유틸리티 설정이 완료되었습니다!"
  
  show_warning "변경 사항을 적용하려면 다음 명령어를 실행하세요:"
  if [[ "$SHELL_TYPE" == "zsh" ]]; then
    echo -e "${BLUE}source ~/.zshrc${NC}"
  else
    echo -e "${BLUE}source ~/.bash_profile${NC}"
  fi
  
  echo -e "\n${YELLOW}다음으로 add3node.sh 또는 add2node.sh 스크립트를 사용하여 노드를 생성할 수 있습니다.${NC}"
  
  if [[ "$SSH_SESSION" == true ]]; then
    echo -e "\n${YELLOW}SSH 세션 사용 팁:${NC}"
    echo -e "1. 환경 변수가 제대로 설정되었는지 확인하세요: ${BLUE}echo \$DOCKER_HOST${NC}"
    echo -e "2. Docker가 작동하는지 확인하세요: ${BLUE}docker ps${NC}"
    echo -e "3. 시스템 재부팅 후에도 Docker가 자동으로 실행됩니다."
  fi
}

# 메인 스크립트
main() {
  echo -e "${BLUE}=== Creditcoin Docker 유틸리티 설정 (macOS + OrbStack) ===${NC}"
  
  # 환경 확인
  check_environment
  
  # FileVault 상태 확인
  check_filevault
  
  # Homebrew 설치
  install_homebrew
  
  # 필요한 도구 설치
  install_tools
  
  # OrbStack 설치
  install_orbstack
  
  # 관리자 권한이 있는 경우에만 추가 설정
  if [ "$IS_ADMIN" = true ]; then
    # OrbStack 자동 시작 설정
    setup_orbstack_autostart
    
    # 시스템 절전 모드 설정
    configure_power_management
  else
    show_warning "일부 설정은 관리자 권한이 필요하므로 건너뛰었습니다."
    show_warning "나중에 관리자 권한으로 'sudo ./setup.sh'를 실행하여 설정을 완료하세요."
  fi
  
  # 쉘 프로필 설정
  add_to_shell_profile
  
  # 리소스 권장 설정 안내
  show_resource_recommendations
  
  # 최종 안내
  show_final_instructions
}

# 스크립트 실행
main "$@"