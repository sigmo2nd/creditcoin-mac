#!/bin/bash
# cleanup2.sh - Creditcoin 2.0 레거시 관련 파일과 컨테이너 정리 (macOS 호환)

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}!!! 경고 !!!${NC}"
echo -e "${YELLOW}이 스크립트는 Creditcoin 2.0 레거시 관련 파일과 컨테이너를 완전히 삭제합니다:${NC}"
echo -e " - 모든 node 컨테이너"
echo -e " - docker-compose-legacy.yml"
echo -e " - Dockerfile.legacy"
echo -e " - 모든 node 디렉토리"
echo -e " - 모든 관련 빌드 캐시"
echo ""
echo -e "${RED}이 작업은 되돌릴 수 없습니다.${NC}"
echo ""
read -p "계속 진행하시겠습니까? (y/N) " response

if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "${BLUE}===== Creditcoin 2.0 레거시 노드 정리 시작 =====${NC}"

    echo -e "${YELLOW}실행 중인 node 컨테이너 중지 및 삭제...${NC}"
    # 실행 중인 노드 목록 조회
    RUNNING_NODES=$(docker ps -a --format "{{.Names}}" | grep '^node[0-9]')
    
    # 노드가 있는 경우에만 중지 및 삭제
    if [ ! -z "$RUNNING_NODES" ]; then
        echo -e "${YELLOW}다음 노드 컨테이너를 중지합니다:${NC}"
        echo "$RUNNING_NODES"
        docker ps -a --format "{{.Names}}" | grep '^node[0-9]' | xargs -r docker stop
        docker ps -a --format "{{.Names}}" | grep '^node[0-9]' | xargs -r docker rm
        echo -e "${GREEN}컨테이너 중지 및 삭제 완료${NC}"
    else
        echo -e "${GREEN}중지할 node 컨테이너가 없습니다.${NC}"
    fi
    
    echo -e "${YELLOW}node 이미지 삭제...${NC}"
    # creditcoin2 이미지 존재 확인
    IMAGES=$(docker images | grep 'creditcoin2' | awk '{print $3}')
    if [ ! -z "$IMAGES" ]; then
        docker images | grep 'creditcoin2' | awk '{print $3}' | xargs -r docker rmi -f
        echo -e "${GREEN}이미지 삭제 완료${NC}"
    else
        echo -e "${GREEN}삭제할 creditcoin2 이미지가 없습니다.${NC}"
    fi
    
    echo -e "${BLUE}===== 파일 시스템 정리 시작 =====${NC}"

    echo -e "${YELLOW}모든 node 디렉토리 삭제...${NC}"
    if ls -d ./node[0-9]* >/dev/null 2>&1; then
        rm -rf ./node[0-9]*
        echo -e "${GREEN}node 디렉토리 삭제 완료${NC}"
    else
        echo -e "${GREEN}삭제할 node 디렉토리가 없습니다.${NC}"
    fi

    echo -e "${YELLOW}Dockerfile.legacy 삭제...${NC}"
    if [ -f "Dockerfile.legacy" ]; then
        rm -f Dockerfile.legacy
        echo -e "${GREEN}Dockerfile.legacy 삭제 완료${NC}"
    else
        echo -e "${GREEN}삭제할 Dockerfile.legacy 파일이 없습니다.${NC}"
    fi

    echo -e "${YELLOW}docker-compose-legacy.yml 삭제...${NC}"
    if [ -f "docker-compose-legacy.yml" ]; then
        rm -f docker-compose-legacy.yml
        echo -e "${GREEN}docker-compose-legacy.yml 삭제 완료${NC}"
    else
        echo -e "${GREEN}삭제할 docker-compose-legacy.yml 파일이 없습니다.${NC}"
    fi
    
    echo -e "${BLUE}===== Docker 캐시 정리 시작 =====${NC}"
    
    echo -e "${YELLOW}Docker 빌드 캐시 삭제...${NC}"
    docker builder prune -f
    
    echo -e "${YELLOW}사용하지 않는 Docker 볼륨 삭제...${NC}"
    docker volume prune -f
    
    echo -e "${YELLOW}사용하지 않는 네트워크 삭제...${NC}"
    docker network prune -f

    echo -e "${BLUE}===== 정리 완료 =====${NC}"
    echo -e "${GREEN}모든 Creditcoin 2.0 레거시 관련 컨테이너, 이미지, 캐시 및 파일들이 삭제되었습니다.${NC}"
else
    echo -e "${BLUE}작업이 취소되었습니다.${NC}"
fi