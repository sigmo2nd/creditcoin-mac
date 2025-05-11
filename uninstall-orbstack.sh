#!/bin/bash
# uninstall_orbstack.sh - OrbStack 완전 제거 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${RED}!!! 경고 !!!${NC}"
echo -e "${YELLOW}이 스크립트는 OrbStack을 완전히 제거합니다.${NC}"
echo -e "${YELLOW}OrbStack에서 실행 중인 컨테이너, 이미지 및 볼륨 데이터가 모두 삭제됩니다.${NC}"
echo ""
read -p "계속 진행하시겠습니까? (y/N) " response

if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "${BLUE}작업이 취소되었습니다.${NC}"
    exit 0
fi

echo -e "${BLUE}===== OrbStack 제거 시작 =====${NC}"

# 1. 실행 중인 OrbStack 중지
echo -e "${YELLOW}1. OrbStack 중지 중...${NC}"
if command -v orb &> /dev/null; then
    orb stop
    sleep 2
    echo -e "${GREEN}OrbStack 중지됨${NC}"
else
    echo -e "${YELLOW}orb 명령어를 찾을 수 없습니다. OrbStack이 이미 제거되었거나 PATH에 없습니다.${NC}"
fi

# 2. Homebrew로 설치한 경우 제거
echo -e "${YELLOW}2. Homebrew로 OrbStack 제거 중...${NC}"
if brew list | grep -q orbstack; then
    brew uninstall orbstack
    echo -e "${GREEN}Homebrew에서 OrbStack 제거됨${NC}"
else
    echo -e "${YELLOW}Homebrew에 OrbStack이 설치되어 있지 않습니다.${NC}"
fi

# 3. 앱 제거
echo -e "${YELLOW}3. OrbStack 앱 제거 중...${NC}"
if [ -d "/Applications/OrbStack.app" ]; then
    rm -rf "/Applications/OrbStack.app"
    echo -e "${GREEN}/Applications/OrbStack.app 제거됨${NC}"
else
    echo -e "${YELLOW}/Applications/OrbStack.app이 존재하지 않습니다.${NC}"
fi

# 4. OrbStack 데이터 디렉토리 제거
echo -e "${YELLOW}4. OrbStack 데이터 디렉토리 제거 중...${NC}"
if [ -d "$HOME/.orbstack" ]; then
    rm -rf "$HOME/.orbstack"
    echo -e "${GREEN}~/.orbstack 디렉토리 제거됨${NC}"
else
    echo -e "${YELLOW}~/.orbstack 디렉토리가 존재하지 않습니다.${NC}"
fi

# 5. 환경설정 파일 제거
echo -e "${YELLOW}5. OrbStack 환경설정 파일 제거 중...${NC}"
if [ -d "$HOME/Library/Application Support/com.orbstack.OrbStack" ]; then
    rm -rf "$HOME/Library/Application Support/com.orbstack.OrbStack"
    echo -e "${GREEN}환경설정 파일 제거됨${NC}"
else
    echo -e "${YELLOW}환경설정 파일 디렉토리가 존재하지 않습니다.${NC}"
fi

# 6. 로그 파일 제거
echo -e "${YELLOW}6. OrbStack 로그 파일 제거 중...${NC}"
if [ -d "$HOME/Library/Logs/OrbStack" ]; then
    rm -rf "$HOME/Library/Logs/OrbStack"
    echo -e "${GREEN}로그 파일 제거됨${NC}"
else
    echo -e "${YELLOW}로그 파일 디렉토리가 존재하지 않습니다.${NC}"
fi

# 7. 캐시 파일 제거
echo -e "${YELLOW}7. OrbStack 캐시 파일 제거 중...${NC}"
if [ -d "$HOME/Library/Caches/com.orbstack.OrbStack" ]; then
    rm -rf "$HOME/Library/Caches/com.orbstack.OrbStack"
    echo -e "${GREEN}캐시 파일 제거됨${NC}"
else
    echo -e "${YELLOW}캐시 파일 디렉토리가 존재하지 않습니다.${NC}"
fi

# 8. 자동 시작 설정 제거
echo -e "${YELLOW}8. OrbStack 자동 시작 설정 제거 중...${NC}"
defaults delete com.orbstack.OrbStack LaunchAtLogin 2>/dev/null
echo -e "${GREEN}자동 시작 설정 제거됨${NC}"

# 9. 쉘 프로필에서 OrbStack 관련 라인 제거
echo -e "${YELLOW}9. 쉘 프로필에서 OrbStack 관련 설정 제거 중...${NC}"

# 쉘 프로필 파일 결정
if [[ "$SHELL" == *"zsh"* ]]; then
    PROFILE_FILE="$HOME/.zshrc"
else
    PROFILE_FILE="$HOME/.bash_profile"
fi

# 백업 생성
cp "$PROFILE_FILE" "${PROFILE_FILE}.bak.$(date +%Y%m%d%H%M%S)"

# OrbStack 관련 라인 제거
if grep -q "OrbStack" "$PROFILE_FILE"; then
    sed -i '' '/OrbStack/d' "$PROFILE_FILE"
    echo -e "${GREEN}쉘 프로필에서 OrbStack 관련 설정이 제거되었습니다.${NC}"
else
    echo -e "${YELLOW}쉘 프로필에 OrbStack 관련 설정이 없습니다.${NC}"
fi

echo -e "${BLUE}===== OrbStack 제거 완료 =====${NC}"
echo -e "${GREEN}OrbStack이 완전히 제거되었습니다.${NC}"
echo -e "${YELLOW}변경사항을 적용하려면 터미널을 재시작하거나 새 터미널 창을 여세요.${NC}"