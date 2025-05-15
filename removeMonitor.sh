#!/bin/bash
# remove-monitor.sh - Creditcoin 모니터링 제거 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 도움말 표시 함수
show_help() {
  echo "사용법: $0 [옵션]"
  echo ""
  echo "옵션:"
  echo "  -y, --yes          확인 없이 진행"
  echo "  -k, --keep-source  소스 코드 유지"
  echo "  -h, --help         도움말 표시"
  echo ""
}

# 기본값 설정
YES=false
KEEP_SOURCE=false

# 옵션 파싱
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)
      YES=true
      shift
      ;;
    -k|--keep-source)
      KEEP_SOURCE=true
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      echo -e "${RED}알 수 없는 옵션: $1${NC}"
      show_help
      exit 1
      ;;
  esac
done

# 확인 메시지
if [ "$YES" != true ]; then
  echo -e "${YELLOW}Creditcoin 모니터링 서비스를 제거하시겠습니까?${NC}"
  echo -e "${YELLOW}이 작업은 다음을 포함합니다:${NC}"
  echo -e "${YELLOW} - 모니터 컨테이너 중지 및 제거${NC}"
  if [ "$KEEP_SOURCE" != true ]; then
    echo -e "${YELLOW} - 소스 코드 및 관련 파일 삭제${NC}"
  fi
  echo -e "${YELLOW} - docker-compose.yml에서 모니터 서비스 제거${NC}"
  echo ""
  echo -e "${YELLOW}계속하시겠습니까? (y/N)${NC}"
  read response
  if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "${BLUE}작업이 취소되었습니다.${NC}"
    exit 0
  fi
fi

# 모니터 컨테이너 중지 및 제거
echo -e "${BLUE}모니터 컨테이너 중지 및 제거 중...${NC}"
docker stop creditcoin-monitor 2>/dev/null || true
docker rm creditcoin-monitor 2>/dev/null || true

# docker-compose.yml에서 모니터 서비스 제거
if [ -f "docker-compose.yml" ]; then
  echo -e "${BLUE}docker-compose.yml에서 모니터 서비스 제거 중...${NC}"
  
  # 백업 생성
  cp docker-compose.yml docker-compose.yml.bak
  
  # 모니터 서비스 블록 제거
  sed -i.tmp '/^  monitor:/,/^  [^[:space:]]/s/^/#/' docker-compose.yml
  rm -f docker-compose.yml.tmp
  
  echo -e "${GREEN}docker-compose.yml에서 모니터 서비스가 제거되었습니다.${NC}"
  echo -e "${GREEN}백업 파일: docker-compose.yml.bak${NC}"
fi

# 소스 코드 및 관련 파일 삭제
if [ "$KEEP_SOURCE" != true ]; then
  echo -e "${BLUE}소스 코드 및 관련 파일 삭제 중...${NC}"
  
  # 소스 디렉토리 삭제
  if [ -d "monitor" ]; then
    rm -rf monitor
    echo -e "${GREEN}monitor 디렉토리가 삭제되었습니다.${NC}"
  fi
fi

# .env 파일에서 모니터링 관련 변수 제거
if [ -f ".env" ]; then
  echo -e "${BLUE}.env 파일에서 모니터링 관련 변수 제거 중...${NC}"
  
  # 백업 생성
  cp .env .env.bak
  
  # 모니터링 관련 변수 제거
  grep -v "^SERVER_ID=\|^NODE_NAMES=\|^MONITOR_INTERVAL=\|^WS_SERVER_URL=\|^CREDITCOIN_DIR=" .env > .env.new
  mv .env.new .env
  
  echo -e "${GREEN}.env 파일에서 모니터링 관련 변수가 제거되었습니다.${NC}"
  echo -e "${GREEN}백업 파일: .env.bak${NC}"
fi

# creditcoin-utils.sh에서 모니터링 함수 제거
if [ -f "creditcoin-utils.sh" ]; then
  echo -e "${BLUE}creditcoin-utils.sh에서 모니터링 함수 제거 중...${NC}"
  
  # 백업 생성
  cp creditcoin-utils.sh creditcoin-utils.sh.bak
  
  # 모니터링 관련 함수 제거
  sed -i.tmp '/^# 모니터링 관련 함수/,/^}/d' creditcoin-utils.sh
  rm -f creditcoin-utils.sh.tmp
  
  echo -e "${GREEN}creditcoin-utils.sh에서 모니터링 함수가 제거되었습니다.${NC}"
  echo -e "${GREEN}백업 파일: creditcoin-utils.sh.bak${NC}"
fi

echo -e "${GREEN}Creditcoin 모니터링 서비스가 성공적으로 제거되었습니다.${NC}"
