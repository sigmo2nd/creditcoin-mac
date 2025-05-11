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

# 사용자 쉘 프로필 파일 찾기
get_shell_profile() {
  if [[ "$SHELL" == *"zsh"* ]]; then
    echo "$HOME/.zshrc"
  else
    echo "$HOME/.bash_profile"
  fi
}

# macOS 환경 확인
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
  else
    show_success "기본 쉘: bash 또는 기타"
    export SHELL_TYPE="bash"
  fi
  
  # SSH 세션 확인
  if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    show_success "SSH 세션으로 접속 중입니다."
    export SSH_SESSION=true
  else
    show_success "로컬 터미널 세션입니다."
    export SSH_SESSION=false
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
    echo ""
    
    show_warning "FileVault 해제는 시간이 오래 걸릴 수 있으며, 디스크 크기에 따라 수 시간이 소요될 수 있습니다."
  else
    show_success "FileVault가 비활성화되어 있거나 상태를 확인할 수 없습니다."
  fi
}

# Homebrew 설치 함수
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
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.bash_profile
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

# OrbStack 설치 함수
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
  
  # Docker CLI 경로 설정
  if ! command -v docker &> /dev/null; then
    show_warning "Docker CLI를 PATH에 추가합니다..."
    
    if [ -f "/Applications/OrbStack.app/Contents/MacOS/xbin/docker" ]; then
      export PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:$PATH"
      
      # 프로필 파일에 경로 추가
      PROFILE_FILE=$(get_shell_profile)
      if ! grep -q "OrbStack.app/Contents/MacOS/xbin" "$PROFILE_FILE"; then
        echo 'export PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:$PATH"' >> "$PROFILE_FILE"
      fi
      
      show_success "Docker CLI 경로가 PATH에 추가되었습니다."
    else
      show_warning "Docker CLI를 찾을 수 없습니다. OrbStack이 제대로 설치되었는지 확인하세요."
    fi
  fi
  
  # 소켓 디렉토리 생성
  mkdir -p "$HOME/.orbstack/run"
}

# OrbStack 자동 시작 설정 (sudo 필요)
setup_orbstack_autostart() {
  show_step "OrbStack 자동 시작 설정"
  
  # 권한 확인 및 sudo 요청
  if [ "$(id -u)" != "0" ]; then
    show_warning "OrbStack 자동 시작을 설정하려면 관리자 권한이 필요합니다."
    show_warning "관리자 암호를 입력하세요:"
    sudo -v || return 1
    
    # 현재 스크립트를 sudo로 실행하여 이 함수만 다시 호출
    show_warning "관리자 권한으로 자동 시작 설정을 진행합니다..."
    sudo "$0" --autostart-only
    local RET=$?
    
    # 성공 여부 반환
    return $RET
  fi
  
  # 로그 디렉토리 생성
  show_warning "OrbStack 로그 디렉토리 생성 중..."
  mkdir -p /Library/Logs/OrbStack
  chmod 755 /Library/Logs/OrbStack
  
  # 기존 런치데몬 정리
  show_warning "기존 런치데몬 정리 중..."
  launchctl unload /Library/LaunchDaemons/com.orbstack.autostart.plist 2>/dev/null || true
  rm -f /Library/LaunchDaemons/com.orbstack.autostart.plist
  launchctl unload /Library/LaunchDaemons/local.orbstack.plist 2>/dev/null || true
  rm -f /Library/LaunchDaemons/local.orbstack.plist
  launchctl unload /Library/LaunchDaemons/dev.orbstack.daemon.plist 2>/dev/null || true
  
  # 새 런치데몬 생성
  show_warning "OrbStack 자동 시작 런치데몬 생성 중..."
  cat > /Library/LaunchDaemons/dev.orbstack.daemon.plist << 'EOT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.orbstack.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/OrbStack.app/Contents/MacOS/orbd</string>
        <string>daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/Library/Logs/OrbStack/orbstack-daemon.log</string>
    <key>StandardOutPath</key>
    <string>/Library/Logs/OrbStack/orbstack-daemon.log</string>
</dict>
</plist>
EOT
  
  # 권한 설정
  chmod 644 /Library/LaunchDaemons/dev.orbstack.daemon.plist
  chown root:wheel /Library/LaunchDaemons/dev.orbstack.daemon.plist
  
  # 런치데몬 로드
  show_warning "런치데몬 로드 중..."
  launchctl load -w /Library/LaunchDaemons/dev.orbstack.daemon.plist
  
  if [ $? -eq 0 ]; then
    show_success "런치데몬이 성공적으로 로드되었습니다."
  else
    show_error "런치데몬 로드 중 오류가 발생했습니다."
    return 1
  fi
  
  # CLI 설정으로 자동 시작 및 헤드리스 모드 활성화
  # orb 명령어 경로 찾기
  ORB_CMD=""
  for path in "/opt/homebrew/bin/orb" "/usr/local/bin/orb" "/Applications/OrbStack.app/Contents/MacOS/orb"; do
    if [ -f "$path" ]; then
      ORB_CMD="$path"
      break
    fi
  done
  
  if [ -n "$ORB_CMD" ]; then
    show_warning "OrbStack CLI 설정 중..."
    show_warning "자동 시작 활성화..."
    "$ORB_CMD" settings set auto-start true
    
    # 서버 환경에서는 헤드리스 모드 활성화
    if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
      show_warning "헤드리스 모드 활성화..."
      "$ORB_CMD" settings set headless true
    fi
  fi
  
  # 소켓 디렉토리 생성
  mkdir -p /var/run/orbstack
  chmod 777 /var/run/orbstack
  
  # OrbStack 시작
  show_warning "OrbStack 시작 중..."
  if [ -n "$ORB_CMD" ]; then
    "$ORB_CMD" start
    sleep 5
    
    # 시작 상태 확인
    STATUS=$("$ORB_CMD" status)
    if [ "$STATUS" == "Running" ]; then
      show_success "OrbStack이 성공적으로 시작되었습니다."
    else
      show_warning "OrbStack 시작이 지연되고 있습니다. 몇 분 내에 시작될 예정입니다."
    fi
  fi
  
  show_success "OrbStack 자동 시작 설정이 완료되었습니다."
  show_success "시스템 재부팅 후 OrbStack이 자동으로 시작됩니다."
  return 0
}

# 시스템 절전 모드 설정 (sudo 필요)
configure_power_management() {
  show_step "시스템 절전 모드 설정"
  
  # 권한 확인 및 sudo 요청
  if [ "$(id -u)" != "0" ]; then
    show_warning "시스템 절전 모드 설정을 위해 관리자 권한이 필요합니다."
    show_warning "관리자 암호를 입력하세요:"
    sudo -v || return 1
    
    # 현재 스크립트를 sudo로 실행하여 이 함수만 다시 호출
    sudo "$0" --power-only
    local RET=$?
    
    # 성공 여부 반환
    return $RET
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
  pmset -c sleep 0 disksleep 0 womp 1 networkoversleep 0 ttyskeepawake 1 autorestart 1
  
  # 배터리 설정 (노트북인 경우)
  if pmset -g | grep -q "Battery Power"; then
    echo -e "${YELLOW}노트북을 위한 배터리 설정:${NC}"
    echo -e "${YELLOW}배터리 사용 중 시스템 절전 모드도 비활성화하시겠습니까? (y/N)${NC}"
    echo -e "${RED}주의: 배터리 설정 비활성화는 배터리 수명을 크게 단축시킬 수 있습니다.${NC}"
    read -p "" DISABLE_BATTERY_SLEEP
    
    if [[ "$DISABLE_BATTERY_SLEEP" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      # 배터리 사용 시 절전 방지 설정
      pmset -b sleep 0 disksleep 0 ttyskeepawake 1
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

# 쉘 프로필에 추가
add_to_shell_profile() {
  show_step "쉘 프로필 설정"
  
  # 프로필 파일 결정
  PROFILE_FILE=$(get_shell_profile)
  
  # 쉘 타입에 따른 메시지
  if [[ "$SHELL" == *"zsh"* ]]; then
    show_success "zsh 쉘이 감지되었습니다. $PROFILE_FILE에 설정을 추가합니다."
  else
    show_success "bash 쉘이 감지되었습니다. $PROFILE_FILE에 설정을 추가합니다."
  fi
  
  # 마커 문자열 설정
  local marker="# === Creditcoin Docker Utils ==="
  local endmarker="# === End Creditcoin Docker Utils ==="
  
  # 이미 추가되었는지 확인
  if grep -q "$marker" "$PROFILE_FILE" 2>/dev/null; then
    show_warning "이미 $PROFILE_FILE에 설정이 추가되어 있습니다."
    
    # 기존 설정 백업
    cp "$PROFILE_FILE" "${PROFILE_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    show_success "$PROFILE_FILE 백업 파일이 생성되었습니다."
    
    # 시작 마커와 종료 마커 사이의 내용 삭제
    sed -i.tmp "/$marker/,/$endmarker/d" "$PROFILE_FILE"
    rm -f "${PROFILE_FILE}.tmp"
    
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

# 유틸리티 함수 로드
if [ -f "\$CREDITCOIN_UTILS" ]; then
    source "\$CREDITCOIN_UTILS"
fi
$endmarker
EOT

  show_success "$PROFILE_FILE에 유틸리티가 추가되었습니다."
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
  if [[ "$SHELL" == *"zsh"* ]]; then
    echo -e "${BLUE}source ~/.zshrc${NC}"
  else
    echo -e "${BLUE}source ~/.bash_profile${NC}"
  fi
  
  echo -e "\n${YELLOW}다음으로 add3node.sh 또는 add2node.sh 스크립트를 사용하여 노드를 생성할 수 있습니다.${NC}"
  
  if [[ "$SSH_SESSION" == true ]]; then
    echo -e "\n${YELLOW}SSH 세션 사용 팁:${NC}"
    echo -e "1. 환경 변수가 제대로 설정되었는지 확인하세요: ${BLUE}echo \$DOCKER_HOST${NC}"
    echo -e "2. Docker가 작동하는지 확인하세요: ${BLUE}docker ps${NC}"
    echo -e "3. 로그 확인: ${BLUE}cat /var/log/orbstack-daemon.log${NC}"
  fi
}

# 메인 스크립트
main() {
  # 특정 기능만 실행하는 옵션 처리
  if [ "$1" == "--autostart-only" ]; then
    setup_orbstack_autostart
    exit $?
  elif [ "$1" == "--power-only" ]; then
    configure_power_management
    exit $?
  fi

  echo -e "${BLUE}=== Creditcoin Docker 유틸리티 설정 (macOS + OrbStack) ===${NC}"
  
  # 기본 설정 (sudo 필요 없음)
  check_environment
  check_filevault
  install_homebrew
  install_tools
  install_orbstack
  add_to_shell_profile
  
  # sudo 필요한 작업들
  setup_orbstack_autostart
  configure_power_management
  
  # 리소스 권장 설정 안내
  show_resource_recommendations
  
  # 최종 안내
  show_final_instructions
}

# 스크립트 실행
main "$@"