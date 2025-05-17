#!/bin/bash
# removemclient.sh - Creditcoin 모니터링 클라이언트 제거 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}!!! 경고 !!!${NC}"
echo -e "${YELLOW}이 스크립트는 Creditcoin 모니터링 클라이언트 관련 설정과 컨테이너를 삭제합니다:${NC}"
echo -e " - mclient 컨테이너"
echo -e " - mclient 서비스 (docker-compose.yml 파일에서)"
echo -e " - mclient 디렉토리 및 모든 관련 파일"
echo -e " - 쉘 프로필에서 mclient 유틸리티 함수"
echo ""
echo -e "${RED}이 작업은 되돌릴 수 없습니다.${NC}"
echo -e "${YELLOW}Creditcoin 노드 관련 파일 및 컨테이너는 영향받지 않습니다.${NC}"
echo -e "${YELLOW}모니터링 클라이언트를 다시 설치하려면 addmclient.sh를 실행하세요.${NC}"
echo ""
read -p "계속 진행하시겠습니까? (y/N) " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "${BLUE}===== Creditcoin 모니터링 클라이언트 제거 시작 =====${NC}"

    echo -e "${YELLOW}실행 중인 mclient 컨테이너 중지 및 삭제...${NC}"
    # 실행 중인 mclient 컨테이너 확인
    if docker ps -a --format "{{.Names}}" | grep -q 'mclient'; then
        echo -e "${YELLOW}mclient 컨테이너를 중지합니다...${NC}"
        docker stop mclient
        docker rm mclient
        echo -e "${GREEN}mclient 컨테이너 중지 및 삭제 완료${NC}"
    else
        echo -e "${GREEN}중지할 mclient 컨테이너가 없습니다.${NC}"
    fi
    
    # docker-compose.yml 파일에서 mclient 서비스 제거
    if [ -f "docker-compose.yml" ]; then
        echo -e "${YELLOW}docker-compose.yml 파일에서 mclient 서비스 제거 중...${NC}"
        
        # 백업 생성
        cp docker-compose.yml docker-compose.yml.bak.$(date +%Y%m%d%H%M%S)
        
        # mclient 서비스가 있는지 확인
        if grep -q "  mclient:" docker-compose.yml; then
            # mclient 서비스 라인 찾기
            mclient_line=$(grep -n "  mclient:" docker-compose.yml | cut -d: -f1)
            
            # mclient 서비스 블록 제거
            # 다음 서비스나 networks 섹션 시작 위치 찾기
            next_service_line=$(awk "
                /^  [a-zA-Z0-9_-]+:/ && NR > $mclient_line && !/^  mclient:/ {print NR; exit}
                /^networks:/ && NR > $mclient_line {print NR; exit}
            " docker-compose.yml)
            
            if [ -n "$next_service_line" ]; then
                # mclient 서비스 블록 제거
                sed -i.tmp "${mclient_line},$(($next_service_line-1))d" docker-compose.yml
                rm -f docker-compose.yml.tmp
                echo -e "${GREEN}docker-compose.yml 파일에서 mclient 서비스 제거 완료${NC}"
            else
                echo -e "${RED}docker-compose.yml 파일 구조를 식별할 수 없습니다.${NC}"
                echo -e "${YELLOW}mclient 서비스를 수동으로 제거해야 할 수 있습니다.${NC}"
            fi
        else
            echo -e "${GREEN}docker-compose.yml 파일에 mclient 서비스가 없습니다.${NC}"
        fi
    else
        echo -e "${GREEN}docker-compose.yml 파일이 없습니다.${NC}"
    fi
    
    # mclient 이미지 삭제
    echo -e "${YELLOW}mclient 이미지 삭제...${NC}"
    if docker images | grep -q 'creditcoin3_mclient'; then
        docker rmi $(docker images -q creditcoin3_mclient)
        echo -e "${GREEN}mclient 이미지 삭제 완료${NC}"
    elif docker images | grep -q 'mclient'; then
        docker rmi $(docker images -q mclient)
        echo -e "${GREEN}mclient 이미지 삭제 완료${NC}"
    else
        echo -e "${GREEN}삭제할 mclient 이미지가 없습니다.${NC}"
    fi
    
    # mclient 디렉토리 삭제
    echo -e "${YELLOW}mclient 디렉토리 삭제...${NC}"
    if [ -d "./mclient" ]; then
        rm -rf ./mclient
        echo -e "${GREEN}mclient 디렉토리 삭제 완료${NC}"
    else
        echo -e "${GREEN}삭제할 mclient 디렉토리가 없습니다.${NC}"
    fi
    
    # .env 파일에서 모니터링 관련 변수 제거
    if [ -f ".env" ]; then
        echo -e "${YELLOW}.env 파일에서 모니터링 관련 변수 제거...${NC}"
        
        # 백업 생성
        cp .env .env.bak.$(date +%Y%m%d%H%M%S)
        
        # 모니터링 관련 변수 제거
        grep -v "^SERVER_ID=\|^NODE_NAMES=\|^MONITOR_INTERVAL=\|^WS_MODE=\|^WS_SERVER_URL=\|^CREDITCOIN_DIR=" .env > .env.new
        mv .env.new .env
        
        echo -e "${GREEN}.env 파일 업데이트 완료${NC}"
    fi
    
    # 쉘 프로필에서 모니터링 유틸리티 함수 제거
    echo -e "${YELLOW}쉘 프로필에서 모니터링 유틸리티 함수 제거...${NC}"
    
    # 쉘 프로필 결정
    if [[ "$SHELL" == *"zsh"* ]]; then
        SHELL_PROFILE="$HOME/.zshrc"
    else
        SHELL_PROFILE="$HOME/.bash_profile"
    fi
    
    # 마커 문자열 설정
    MARKER="# === Creditcoin Monitor Client Utils ==="
    ENDMARKER="# === End Creditcoin Monitor Client Utils ==="
    
    # 쉘 프로필에서 모니터링 유틸리티 함수 제거
    if [ -f "$SHELL_PROFILE" ]; then
        if grep -q "$MARKER" "$SHELL_PROFILE"; then
            # 백업 생성
            cp "$SHELL_PROFILE" "${SHELL_PROFILE}.bak.$(date +%Y%m%d%H%M%S)"
            
            # 모니터링 유틸리티 함수 제거
            sed -i.tmp "/$MARKER/,/$ENDMARKER/d" "$SHELL_PROFILE"
            rm -f "${SHELL_PROFILE}.tmp"
            
            echo -e "${GREEN}쉘 프로필에서 모니터링 유틸리티 함수 제거 완료${NC}"
            echo -e "${YELLOW}변경사항이 적용되려면 쉘을 다시 시작하거나 다음 명령어를 실행하세요:${NC}"
            echo -e "${GREEN}source $SHELL_PROFILE${NC}"
        else
            echo -e "${GREEN}쉘 프로필에 모니터링 유틸리티 함수가 없습니다.${NC}"
        fi
    else
        echo -e "${GREEN}쉘 프로필 파일이 없습니다.${NC}"
    fi
    
    # 네트워크 설정 확인 (호스트 네트워크 모드 사용 시)
    echo -e "${YELLOW}호스트 네트워크 설정 확인 중...${NC}"
    if [ -f "/etc/hosts" ] && grep -q "mclient" /etc/hosts; then
        echo -e "${YELLOW}/etc/hosts 파일에 mclient 관련 설정이 있을 수 있습니다. 수동으로 확인하세요.${NC}"
    else
        echo -e "${GREEN}호스트 네트워크 설정에 문제가 없습니다.${NC}"
    fi
    
    echo -e "${BLUE}===== 정리 완료 =====${NC}"
    echo -e "${GREEN}Creditcoin 모니터링 클라이언트 관련 파일 및 설정이 모두 제거되었습니다.${NC}"
    echo -e "${YELLOW}모니터링 클라이언트를 다시 설치하려면 addmclient.sh를 실행하세요.${NC}"
else
    echo -e "${BLUE}작업이 취소되었습니다.${NC}"
fi