#!/bin/bash
# add-monitor.sh - Creditcoin 모니터링 추가 스크립트 (개선된 버전)

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Docker 명령어 및 환경 확인 (SSH 및 OrbStack 호환성)
check_docker_env() {
  # Docker 명령어 경로 확인 및 추가
  if ! command -v docker &>/dev/null; then
    echo -e "${YELLOW}Docker 명령어를 찾을 수 없습니다. OrbStack에서 제공하는 Docker CLI를 PATH에 추가합니다.${NC}"
    
    if [ -f "/Applications/OrbStack.app/Contents/MacOS/xbin/docker" ]; then
      export PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:$PATH"
    fi
    
    # 다시 확인
    if ! command -v docker &>/dev/null; then
      echo -e "${RED}Docker CLI를 찾을 수 없습니다. OrbStack이 설치되어 있는지 확인하세요.${NC}"
      exit 1
    fi
  fi

  # SSH 세션 호환성 설정
  if [ -S "$HOME/.orbstack/run/docker.sock" ]; then
    export DOCKER_HOST="unix://$HOME/.orbstack/run/docker.sock"
    export DOCKER_CLI_NO_CREDENTIAL_STORE=1
  fi
  
  # Docker 실행 상태 확인 및 시작 시도
  if ! docker info &> /dev/null; then
    echo -e "${YELLOW}Docker 엔진(OrbStack)이 실행 중이 아닙니다. 시작을 시도합니다...${NC}"
    # OrbStack 시작 시도
    if command -v orb &> /dev/null; then
      orb start
      sleep 10 # 초기화 시간 부여
      
      # 다시 확인
      if ! docker info &> /dev/null; then
        echo -e "${RED}오류: Docker 엔진(OrbStack)을 시작할 수 없습니다.${NC}"
        echo -e "${YELLOW}OrbStack을 수동으로 실행한 후 다시 시도하세요.${NC}"
        exit 1
      fi
    else
      echo -e "${RED}오류: Docker 엔진(OrbStack)이 실행 중이 아닙니다.${NC}"
      echo -e "${YELLOW}OrbStack을 실행한 후 다시 시도하세요.${NC}"
      exit 1
    fi
  fi
}

# Docker 환경 확인
check_docker_env

# 도움말 표시 함수
show_help() {
  echo "사용법: $0 [옵션]"
  echo ""
  echo "옵션:"
  echo "  -s, --server-id    서버 ID (기본값: server1)"
  echo "  -n, --node-names   모니터링할 노드 이름 목록 (쉼표로 구분, 기본값: node,3node)"
  echo "  -i, --interval     모니터링 간격(초) (기본값: 5)"
  echo "  -w, --ws-url       웹소켓 서버 URL (기본값: ws://localhost:8080/ws)"
  echo "  -c, --creditcoin   Creditcoin 디렉토리 (기본값: /Users/사용자/creditcoin-mac)"
  echo "  -f, --force        기존 설정 덮어쓰기"
  echo "  -h, --help         도움말 표시"
  echo ""
  echo "사용 예시:"
  echo "  ./add-monitor.sh                      # 기본 설정으로 모니터 설치"
  echo "  ./add-monitor.sh -s server2           # 다른 서버 ID로 설치"
  echo "  ./add-monitor.sh -n node0,node1,3node0  # 특정 노드만 모니터링"
  echo "  ./add-monitor.sh -i 10                # 10초 간격으로 모니터링"
  echo "  ./add-monitor.sh -w ws://monitor.example.com/ws  # 다른 웹소켓 서버 사용"
  echo ""
}

# 기본값 설정
SERVER_ID="server1"
NODE_NAMES="node,3node"
MONITOR_INTERVAL="5"
WS_SERVER_URL="ws://localhost:8080/ws"
CREDITCOIN_DIR="$HOME/creditcoin-mac"
FORCE=false

# 옵션 파싱
while [ $# -gt 0 ]; do
  case "$1" in
    -s|--server-id)
      SERVER_ID="$2"
      shift 2
      ;;
    -n|--node-names)
      NODE_NAMES="$2"
      shift 2
      ;;
    -i|--interval)
      MONITOR_INTERVAL="$2"
      shift 2
      ;;
    -w|--ws-url)
      WS_SERVER_URL="$2"
      shift 2
      ;;
    -c|--creditcoin)
      CREDITCOIN_DIR="$2"
      shift 2
      ;;
    -f|--force)
      FORCE=true
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

echo -e "${BLUE}Creditcoin 모니터링 설정:${NC}"
echo -e "${GREEN}- 서버 ID: $SERVER_ID${NC}"
echo -e "${GREEN}- 모니터링 노드: $NODE_NAMES${NC}"
echo -e "${GREEN}- 모니터링 간격: ${MONITOR_INTERVAL}초${NC}"
echo -e "${GREEN}- 웹소켓 URL: $WS_SERVER_URL${NC}"
echo -e "${GREEN}- Creditcoin 디렉토리: $CREDITCOIN_DIR${NC}"

# 현재 디렉토리
CURRENT_DIR=$(pwd)

# 환경 변수 안전하게 업데이트 함수
update_env_file() {
  # 백업 생성
  if [ -f ".env" ]; then
    echo -e "${BLUE}기존 .env 파일 백업 중...${NC}"
    cp .env ".env.bak.$(date +%Y%m%d%H%M%S)"
  fi
  
  # 새 .env 파일 생성
  echo -e "${BLUE}새 .env 파일 생성 중...${NC}"
  
  # 기존 .env 파일에서 모니터링 관련 변수를 제외한 내용 추출
  if [ -f ".env" ]; then
    grep -v "^SERVER_ID=\|^NODE_NAMES=\|^MONITOR_INTERVAL=\|^WS_SERVER_URL=\|^CREDITCOIN_DIR=" .env > .env.tmp
  else
    touch .env.tmp
  fi
  
  # 모니터링 변수 추가
  echo "SERVER_ID=${SERVER_ID}" >> .env.tmp
  echo "NODE_NAMES=${NODE_NAMES}" >> .env.tmp
  echo "MONITOR_INTERVAL=${MONITOR_INTERVAL}" >> .env.tmp
  echo "WS_SERVER_URL=${WS_SERVER_URL}" >> .env.tmp
  echo "CREDITCOIN_DIR=${CREDITCOIN_DIR}" >> .env.tmp
  
  # 임시 파일을 .env로 이동
  mv .env.tmp .env
  
  echo -e "${GREEN}.env 파일이 성공적으로 업데이트되었습니다.${NC}"
}

# .env 파일 업데이트
update_env_file

# 모니터링 폴더 생성
mkdir -p ./monitor

# 모니터링 코드 확인
if [ ! -f "./monitor/Cargo.toml" ]; then
  # 현재 디렉토리에 Cargo.toml이 있으면 복사
  if [ -f "./Cargo.toml" ]; then
    echo -e "${YELLOW}현재 디렉토리의 소스 코드를 ./monitor 디렉토리로 복사합니다.${NC}"
    
    # 소스 복사
    cp -r ./src ./Cargo.toml ./Cargo.lock ./monitor/ 2>/dev/null
    
    if [ -f "./monitor/Cargo.toml" ]; then
      echo -e "${GREEN}소스 코드가 복사되었습니다.${NC}"
    else
      echo -e "${RED}소스 코드 복사에 실패했습니다.${NC}"
      echo -e "${YELLOW}모니터링 소스 코드를 수동으로 ./monitor 디렉토리에 복사한 후 다시 시도하세요.${NC}"
      exit 1
    fi
  else
    echo -e "${YELLOW}모니터링 소스 코드가 필요합니다.${NC}"
    echo -e "${YELLOW}모니터링 소스 코드를 ./monitor 디렉토리에 복사한 후 다시 시도하세요.${NC}"
    exit 1
  fi
fi

# Dockerfile 생성
echo -e "${BLUE}Dockerfile 생성 중...${NC}"
cat > ./monitor/Dockerfile << 'EODF'
FROM ubuntu:24.04

# 환경 설정 (타임존, 로케일 등)
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Seoul
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 필요한 패키지 설치
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    libssl-dev \
    pkg-config \
    ca-certificates \
    git \
    wget \
    jq \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# Rust 설치
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# 작업 디렉토리 생성
WORKDIR /app

# 소스 코드 복사
COPY . .

# 빌드
RUN cargo build --release

# 시작 스크립트 생성
RUN echo '#!/bin/bash \n\
echo "크레딧코인 모니터 시작" \n\
\n\
# 설정 정보 출력 \n\
echo "=== 설정 정보 ===" \n\
echo "- CREDITCOIN_DIR: ${CREDITCOIN_DIR}" \n\
echo "- NODE_NAMES: ${NODE_NAMES}" \n\
echo "- MONITOR_INTERVAL: ${MONITOR_INTERVAL}초" \n\
echo "- WS_SERVER_URL: ${WS_SERVER_URL}" \n\
echo "- SERVER_ID: ${SERVER_ID}" \n\
\n\
# 모니터링 실행 \n\
echo "크레딧코인 모니터링을 시작합니다..." \n\
/app/target/release/creditcoin-monitor \n\
' > /app/start.sh

# 실행 권한 부여
RUN chmod +x /app/start.sh

# 시작 스크립트 실행
ENTRYPOINT ["/app/start.sh"]
EODF

# docker-compose.yml 파일 확인/업데이트
if [ ! -f "docker-compose.yml" ]; then
  echo -e "${RED}오류: docker-compose.yml 파일이 없습니다.${NC}"
  echo -e "${YELLOW}먼저 add3node.sh를 실행하여 기본 환경을 구성한 후 다시 시도하세요.${NC}"
  exit 1
fi

# docker-compose.yml 파일 백업
cp docker-compose.yml docker-compose.yml.bak

# docker-compose.yml 파일에 모니터 서비스 추가
if grep -q "monitor:" docker-compose.yml 2>/dev/null; then
  if [ "$FORCE" = true ]; then
    echo -e "${YELLOW}모니터 서비스가 이미 존재하지만 덮어쓰기 옵션이 활성화되어 있습니다.${NC}"
    # 기존 모니터 서비스 제거
    sed -i.tmp '/^  monitor:/,/^  [^[:space:]]/s/^/#/' docker-compose.yml
    rm -f docker-compose.yml.tmp
  else
    echo -e "${YELLOW}모니터 서비스는 이미 docker-compose.yml에 존재합니다.${NC}"
    echo -e "${YELLOW}덮어쓰려면 -f 또는 --force 옵션을 사용하세요.${NC}"
    echo -e "${YELLOW}예: $0 --force${NC}"
    exit 1
  fi
fi

echo -e "${BLUE}docker-compose.yml에 모니터 서비스 추가 중...${NC}"

# 모니터 설정을 임시 파일에 저장
cat > monitor-service.yml << EOF
  monitor:
    build:
      context: ./monitor
      dockerfile: Dockerfile
    container_name: creditcoin-monitor
    restart: unless-stopped
    environment:
      - SERVER_ID=\${SERVER_ID:-$SERVER_ID}
      - NODE_NAMES=\${NODE_NAMES:-$NODE_NAMES}
      - MONITOR_INTERVAL=\${MONITOR_INTERVAL:-$MONITOR_INTERVAL}
      - WS_SERVER_URL=\${WS_SERVER_URL:-$WS_SERVER_URL}
      - CREDITCOIN_DIR=\${CREDITCOIN_DIR:-$CREDITCOIN_DIR}
    volumes:
      - ${CREDITCOIN_DIR}:${CREDITCOIN_DIR}
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      creditnet:

EOF

# networks 섹션 위치 찾기
networks_line=$(grep -n "^networks:" docker-compose.yml | cut -d: -f1)

if [ -n "$networks_line" ]; then
  # networks 섹션 위에 모니터 서비스 삽입
  head -n $((networks_line-1)) docker-compose.yml > docker-compose.new
  cat monitor-service.yml >> docker-compose.new
  tail -n +$((networks_line)) docker-compose.yml >> docker-compose.new
  mv docker-compose.new docker-compose.yml
  rm monitor-service.yml
else
  # networks 섹션이 없는 경우, 파일 끝에 추가
  cat monitor-service.yml >> docker-compose.yml
  rm monitor-service.yml
  
  # networks 섹션 추가
  if ! grep -q "networks:" docker-compose.yml; then
    cat >> docker-compose.yml << EOF

networks:
  creditnet:
    driver: bridge
EOF
  fi
fi

echo -e "${GREEN}모니터 서비스 추가 완료${NC}"

# monsetup 유틸리티 함수 추가
echo -e "${BLUE}creditcoin-utils.sh에 모니터링 유틸리티 함수 추가 중...${NC}"

if [ -f "creditcoin-utils.sh" ]; then
  # creditcoin-utils.sh 백업
  cp creditcoin-utils.sh creditcoin-utils.sh.bak
  
  # 이미 모니터링 함수가 있는지 확인
  if grep -q "monstart()" creditcoin-utils.sh; then
    echo -e "${YELLOW}creditcoin-utils.sh에 이미 모니터링 함수가 있습니다.${NC}"
  else
    # 파일 끝에 모니터링 함수 추가
    cat >> creditcoin-utils.sh << 'EOF'

# 모니터링 관련 함수

# 모니터 시작
monstart() {
  echo -e "${BLUE}모니터 서비스 시작 중...${NC}"
  docker compose up -d monitor
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}모니터 서비스가 시작되었습니다.${NC}"
  else
    echo -e "${RED}모니터 서비스 시작에 실패했습니다.${NC}"
  fi
}

# 모니터 중지
monstop() {
  echo -e "${BLUE}모니터 서비스 중지 중...${NC}"
  docker compose stop monitor
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}모니터 서비스가 중지되었습니다.${NC}"
  else
    echo -e "${RED}모니터 서비스 중지에 실패했습니다.${NC}"
  fi
}

# 모니터 재시작
monrestart() {
  echo -e "${BLUE}모니터 서비스 재시작 중...${NC}"
  docker compose restart monitor
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}모니터 서비스가 재시작되었습니다.${NC}"
  else
    echo -e "${RED}모니터 서비스 재시작에 실패했습니다.${NC}"
  fi
}

# 모니터 로그 확인
monlog() {
  echo -e "${BLUE}모니터 서비스 로그 확인 중...${NC}"
  docker logs -f creditcoin-monitor
}

# 모니터 상태 확인
monstatus() {
  echo -e "${BLUE}모니터 서비스 상태 확인 중...${NC}"
  if docker ps | grep -q "creditcoin-monitor"; then
    echo -e "${GREEN}모니터 서비스가 실행 중입니다.${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "creditcoin-monitor"
  else
    echo -e "${RED}모니터 서비스가 실행 중이 아닙니다.${NC}"
  fi
}

# 모니터 서버 URL 업데이트
monurl() {
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: monurl <새 웹소켓 URL>${NC}"
    echo -e "${YELLOW}예시: monurl wss://monitor.example.com/ws${NC}"
    return 1
  fi
  
  NEW_URL="$1"
  echo -e "${BLUE}웹소켓 서버 URL 업데이트 중: ${NEW_URL}${NC}"
  
  # .env 파일 확인
  if [ ! -f ".env" ]; then
    echo -e "${RED}오류: .env 파일이 없습니다.${NC}"
    return 1
  fi
  
  # .env 백업 생성
  cp .env .env.bak
  
  # 새 .env 파일 생성
  grep -v "^WS_SERVER_URL=" .env > .env.new
  echo "WS_SERVER_URL=${NEW_URL}" >> .env.new
  mv .env.new .env
  
  echo -e "${GREEN}웹소켓 서버 URL이 업데이트되었습니다.${NC}"
  echo -e "${YELLOW}변경 사항을 적용하려면 모니터 서비스를 재시작하세요:${NC}"
  echo -e "${GREEN}monrestart${NC}"
}
EOF
    echo -e "${GREEN}모니터링 유틸리티 함수가 추가되었습니다.${NC}"
  fi
else
  echo -e "${YELLOW}creditcoin-utils.sh 파일이 없습니다. 모니터링 유틸리티 함수를 추가할 수 없습니다.${NC}"
fi

# 제거 스크립트 생성
echo -e "${BLUE}모니터 제거 스크립트 생성 중...${NC}"
cat > remove-monitor.sh << 'EOF'
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
EOF

# 실행 권한 부여
chmod +x add-monitor.sh
chmod +x remove-monitor.sh

echo -e "${BLUE}----------------------------------------------------${NC}"
echo -e "${GREEN}Creditcoin 모니터링 도구가 준비되었습니다.${NC}"
echo -e "${GREEN}다음 설정으로 모니터링 서비스가 구성되었습니다:${NC}"
echo -e "${GREEN}- 서버 ID: ${SERVER_ID}${NC}"
echo -e "${GREEN}- 모니터링 노드: ${NODE_NAMES}${NC}"
echo -e "${GREEN}- 모니터링 간격: ${MONITOR_INTERVAL}초${NC}"
echo -e "${GREEN}- 웹소켓 URL: ${WS_SERVER_URL}${NC}"
echo -e "${GREEN}- Creditcoin 디렉토리: ${CREDITCOIN_DIR}${NC}"
echo -e "${BLUE}----------------------------------------------------${NC}"
echo ""
echo -e "${YELLOW}모니터링 서비스를 관리하려면 다음 명령어를 사용하세요:${NC}"
echo -e "${GREEN}monstart    # 모니터 시작${NC}"
echo -e "${GREEN}monstop     # 모니터 중지${NC}"
echo -e "${GREEN}monrestart  # 모니터 재시작${NC}"
echo -e "${GREEN}monlog      # 로그 보기${NC}"
echo -e "${GREEN}monstatus   # 상태 확인${NC}"
echo -e "${GREEN}monurl      # 서버 URL 업데이트${NC}"
echo ""
echo -e "${YELLOW}지금 모니터링 서비스를 시작하시겠습니까? (y/N)${NC}"
read response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  echo -e "${BLUE}모니터링 서비스를 시작합니다...${NC}"
  # monstart 함수 사용 시도
  if command -v monstart &> /dev/null; then
    monstart
  else
    echo -e "${YELLOW}monstart 함수를 사용할 수 없습니다. docker-compose 명령 사용...${NC}"
    docker compose up -d monitor
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}모니터링 서비스가 시작되었습니다.${NC}"
    else
      echo -e "${RED}모니터링 서비스 시작에 실패했습니다.${NC}"
    fi
  fi
else
  echo -e "${YELLOW}모니터링 서비스를 나중에 시작하려면 'monstart' 명령어를 실행하세요.${NC}"
fi