#!/bin/bash
# addmc.sh - Creditcoin 모니터링 클라이언트 추가 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 기본값 설정
SERVER_ID="server1"
MONITOR_INTERVAL="5"
MODE="server"  # server 또는 local
NODE_NAMES=""
SERVER_URL=""
SERVER_HOST=""
NO_SSL_VERIFY=false
DEBUG_MODE=false
FORCE=false
NON_INTERACTIVE=false

# 현재 디렉토리 저장
CURRENT_DIR=$(pwd)
MCLIENT_DIR="${CURRENT_DIR}/mclient"

# Docker 명령어 및 환경 확인 (OrbStack 호환성)
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
      sleep 5 # 초기화 시간 부여
      
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
  
  echo -e "${GREEN}Docker 환경 확인 완료.${NC}"
}

# 도움말 출력
show_help() {
  echo "사용법: $0 [옵션]"
  echo ""
  echo "옵션:"
  echo "  --non-interactive   대화형 모드 비활성화"
  echo "  --server-id ID      서버 ID 설정 (기본값: server1)"
  echo "  --interval SEC      모니터링 간격(초) 설정 (기본값: 5)"
  echo "  --mode MODE         연결 모드: server, local (기본값: server)"
  echo "  --url URL           WebSocket 서버 URL 직접 지정"
  echo "  --host HOST         WebSocket 서버 호스트 지정"
  echo "  --no-ssl-verify     SSL 인증서 검증 비활성화"
  echo "  --debug             디버그 모드 활성화"
  echo "  --force             기존 파일을 강제로 덮어쓰기"
  echo "  --help, -h          이 도움말 표시"
  echo ""
  echo "사용 예시:"
  echo "  $0                              # 대화형 모드로 실행"
  echo "  $0 --mode local                 # 로컬 모드로 설치"
  echo "  $0 --url wss://example.com/ws   # 특정 URL 사용"
  echo "  $0 --host monitor.example.com   # 특정 호스트 사용"
  echo ""
}

# 명령줄 인자 처리
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --non-interactive)
        NON_INTERACTIVE=true
        shift
        ;;
      --server-id)
        SERVER_ID="$2"
        shift 2
        ;;
      --interval)
        MONITOR_INTERVAL="$2"
        shift 2
        ;;
      --mode)
        MODE="$2"
        shift 2
        ;;
      --url)
        SERVER_URL="$2"
        shift 2
        ;;
      --host)
        SERVER_HOST="$2"
        shift 2
        ;;
      --no-ssl-verify)
        NO_SSL_VERIFY=true
        shift
        ;;
      --debug)
        DEBUG_MODE=true
        shift
        ;;
      --force)
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
}

# 실행 중인 Docker 노드 자동 감지
detect_nodes() {
  echo -e "${BLUE}실행 중인 Creditcoin 노드 감지 중...${NC}" >&2
  
  # Docker 컨테이너 목록에서 node 또는 3node로 시작하는 컨테이너 찾기
  local nodes=""
  nodes=$(docker ps --format "{{.Names}}" | grep -E '^(node|3node)' | tr '\n' ',' | sed 's/,$//')
  
  if [ -z "$nodes" ]; then
    echo -e "${YELLOW}실행 중인 Creditcoin 노드를 찾을 수 없습니다. 기본값을 사용합니다.${NC}" >&2
    echo "node,3node"
    return
  fi
  
  echo -e "${GREEN}감지된 노드: $nodes${NC}" >&2
  echo "$nodes"
}

# 서버 호스트 자동 감지
detect_server_host() {
  echo -e "${BLUE}서버 호스트 감지 중...${NC}" >&2
  
  local default_host=""
  
  # 환경변수가 이미 설정되어 있는지 확인
  if [ ! -z "${SERVER_HOST}" ]; then
    echo -e "${GREEN}환경변수에서 설정된 호스트: ${SERVER_HOST}${NC}" >&2
    echo "${SERVER_HOST}"
    return
  fi
  
  # 기본 서버 호스트 (로컬호스트)
  default_host="localhost"
  
  echo -e "${GREEN}서버 호스트 감지 완료: ${default_host}${NC}" >&2
  echo "${default_host}"
}

# Docker 소켓 경로 찾기
find_docker_sock_path() {
  echo -e "${BLUE}Docker 소켓 경로 감지 중...${NC}" >&2
  
  # 기본 OrbStack Docker 소켓 경로
  local docker_sock_path="$HOME/.orbstack/run/docker.sock"
  
  if [ -S "$docker_sock_path" ]; then
    echo -e "${GREEN}Docker 소켓 발견: $docker_sock_path${NC}" >&2
    echo "$docker_sock_path"
    return
  fi
  
  # 대체 가능한 Docker 소켓 경로 목록
  local possible_paths=(
    "/var/run/docker.sock"
    "/var/run/orbstack/docker.sock"
    "$HOME/Library/Containers/com.orbstack.Orbstack/Data/run/docker.sock"
  )
  
  for path in "${possible_paths[@]}"; do
    if [ -S "$path" ]; then
      echo -e "${GREEN}Docker 소켓 발견: $path${NC}" >&2
      echo "$path"
      return
    fi
  done
  
  echo -e "${YELLOW}Docker 소켓을 찾을 수 없습니다. 기본 경로를 사용합니다.${NC}" >&2
  echo "/var/run/docker.sock"
}

# 필요한 파일 준비
prepare_client_files() {
  echo -e "${BLUE}모니터링 클라이언트 파일 준비 중...${NC}"
  
  # mclient 디렉토리 확인/생성
  if [ ! -d "$MCLIENT_DIR" ]; then
    mkdir -p "$MCLIENT_DIR"
    echo -e "${GREEN}mclient 디렉토리를 생성했습니다.${NC}"
  else
    echo -e "${BLUE}기존 mclient 디렉토리를 사용합니다.${NC}"
  fi
  
  # 필요한 파일 경로들
  local main_py="${MCLIENT_DIR}/main.py"
  local docker_stats="${MCLIENT_DIR}/docker_stats_client.py"
  local websocket="${MCLIENT_DIR}/websocket_client.py"
  local requirements="${MCLIENT_DIR}/requirements.txt"
  
  # 필수 파일이 모두 존재하는지 확인
  if [ -f "$main_py" ] && [ -f "$docker_stats" ] && [ -f "$websocket" ] && [ -f "$requirements" ]; then
    # 모든 파일이 존재하면 사용자에게 확인 요청
    if [ "$FORCE" != true ] && [ "$NON_INTERACTIVE" != true ]; then
      echo -e "${YELLOW}기존 모니터링 클라이언트 파일을 발견했습니다.${NC}"
      read -p "기존 파일을 덮어쓰시겠습니까? (y/N): " override
      if [[ ! "$override" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}기존 파일을 유지합니다.${NC}"
        return
      fi
    fi
  fi
  
  # 현재 디렉토리에서 필요한 파일들 찾기
  local src_files=(
    "main.py" 
    "docker_stats_client.py" 
    "websocket_client.py" 
    "requirements.txt"
  )
  
  local file_found=false
  
  # 현재 디렉토리에서 파일 찾기
  for file in "${src_files[@]}"; do
    if [ -f "${CURRENT_DIR}/${file}" ]; then
      echo -e "${GREEN}파일 발견: ${CURRENT_DIR}/${file}${NC}"
      echo -e "${YELLOW}복사 중: ${file}${NC}"
      cp "${CURRENT_DIR}/${file}" "${MCLIENT_DIR}/${file}"
      file_found=true
    fi
  done
  
  # mclient_org 디렉토리 확인
  local mclient_org="${CURRENT_DIR}/mclient_org"
  if [ -d "$mclient_org" ]; then
    for file in "${src_files[@]}"; do
      if [ -f "${mclient_org}/${file}" ]; then
        echo -e "${GREEN}파일 발견: ${mclient_org}/${file}${NC}"
        echo -e "${YELLOW}복사 중: ${file}${NC}"
        cp "${mclient_org}/${file}" "${MCLIENT_DIR}/${file}"
        file_found=true
      fi
    done
  fi
  
  # 파일을 찾지 못한 경우
  if [ "$file_found" = false ]; then
    echo -e "${YELLOW}필요한 소스 파일을 찾을 수 없습니다.${NC}"
    echo -e "${YELLOW}수동으로 필요한 파일을 ${MCLIENT_DIR} 디렉토리에 복사해야 합니다.${NC}"
  fi
  
  # 스타트 스크립트 추가
  cat > "${MCLIENT_DIR}/start.sh" << 'EOF'
#!/bin/bash
# 환경 변수 확인 및 기본값 설정
echo "크레딧코인 모니터링 클라이언트 시작"
python3 main.py "$@"
EOF
  
  # 실행 권한 부여
  chmod +x "${MCLIENT_DIR}/start.sh"
  
  # Docker 엔트리포인트 스크립트 직접 추가
  cat > "${MCLIENT_DIR}/docker-entrypoint.sh" << 'EOF'
#!/bin/bash
echo "== Creditcoin 모니터링 클라이언트 =="
echo "서버 ID: ${SERVER_ID}"
echo "모니터링 노드: ${NODE_NAMES}"
echo "모니터링 간격: ${MONITOR_INTERVAL}초"
if [ "${LOCAL_MODE}" = "true" ]; then
  echo "모드: 로컬 (데이터 전송 없음)"
else
  echo "모드: 서버 연결"
  if [ ! -z "${SERVER_URL}" ]; then echo "서버 URL: ${SERVER_URL}"; fi
  if [ ! -z "${SERVER_HOST}" ]; then echo "서버 호스트: ${SERVER_HOST}"; fi
fi
echo "시작 중..."
export PROCFS_PATH=/host/proc
python /app/main.py "$@"
EOF

  # 실행 권한 부여
  chmod +x "${MCLIENT_DIR}/docker-entrypoint.sh"
  
  echo -e "${GREEN}모니터링 클라이언트 파일 준비 완료${NC}"
}

# Dockerfile 생성
create_dockerfile() {
  echo -e "${BLUE}Dockerfile 생성 중...${NC}"
  
  cat > "${MCLIENT_DIR}/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app

# 시스템 패키지 설치
RUN apt-get update && apt-get install -y \
    curl \
    procps \
    iproute2 \
    iputils-ping \
    net-tools \
    gcc \
    g++ \
    python3-dev \
    build-essential \
    tzdata \
    docker.io \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI 설치 확인
RUN docker --version || echo "Docker CLI가 설치되지 않았습니다."

# pip 업그레이드 및 기본 패키지 설치
RUN pip install --no-cache-dir --upgrade pip setuptools wheel
RUN pip install --no-cache-dir psutil==5.9.6 docker==6.1.3

# 애플리케이션 파일 복사
COPY . /app/

# 의존성 설치
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# 권한 설정
RUN chmod +x /app/*.py /app/start.sh /app/docker-entrypoint.sh

# 시작 명령어
ENTRYPOINT ["/app/docker-entrypoint.sh"]

# 헬스체크
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD ps aux | grep python | grep main.py || exit 1
EOF

  echo -e "${GREEN}Dockerfile이 생성되었습니다.${NC}"
}

# .env 파일 생성
create_env_file() {
  echo -e "${BLUE}.env 파일 생성 중...${NC}"
  
  # .env 파일 생성
  cat > "${MCLIENT_DIR}/.env" << EOF
# 모니터링 클라이언트 기본 설정
SERVER_ID=${SERVER_ID}
NODE_NAMES=${NODE_NAMES}
MONITOR_INTERVAL=${MONITOR_INTERVAL}

EOF

  # 모드별 설정 추가
  if [ "$MODE" = "local" ]; then
    echo "# 로컬 모드 설정 (전송 없음)" >> "${MCLIENT_DIR}/.env"
    echo "LOCAL_MODE=true" >> "${MCLIENT_DIR}/.env"
  else
    echo "# 서버 연결 설정" >> "${MCLIENT_DIR}/.env"
    
    # URL이 직접 지정된 경우
    if [ ! -z "$SERVER_URL" ]; then
      echo "SERVER_URL=${SERVER_URL}" >> "${MCLIENT_DIR}/.env"
    fi
    
    # 서버 호스트가 지정된 경우
    if [ ! -z "$SERVER_HOST" ]; then
      echo "WS_SERVER_HOST=${SERVER_HOST}" >> "${MCLIENT_DIR}/.env"
    fi
  fi
  
  # SSL 검증 설정
  if [ "$NO_SSL_VERIFY" = true ]; then
    echo "NO_SSL_VERIFY=true" >> "${MCLIENT_DIR}/.env"
  fi
  
  # 디버그 모드 설정
  if [ "$DEBUG_MODE" = true ]; then
    echo "DEBUG_MODE=true" >> "${MCLIENT_DIR}/.env"
  fi
  
  echo -e "${GREEN}.env 파일이 생성되었습니다.${NC}"
}

# 파일 정리 함수 (기존 파일이 이상할 때 사용)
cleanup_docker_compose() {
  echo -e "${BLUE}docker-compose.yml 파일 구조 정리 중...${NC}"
  
  # docker-compose.yml 파일 확인
  if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}오류: docker-compose.yml 파일이 없습니다.${NC}"
    return 1
  fi
  
  # 백업 파일 생성
  BACKUP_FILE="docker-compose.yml.cleanup.$(date +%Y%m%d%H%M%S)"
  cp docker-compose.yml "$BACKUP_FILE"
  echo -e "${GREEN}docker-compose.yml 파일이 $BACKUP_FILE으로 백업되었습니다.${NC}"
  
  # 임시 파일 생성
  TEMP_FILE=$(mktemp)
  
  # 상단 기본 설정 (x-node-defaults) 찾기
  if grep -q "^x-node-defaults:" docker-compose.yml; then
    # x-node-defaults 섹션 추출
    echo -e "${YELLOW}기본 설정 섹션 추출 중...${NC}"
    grep -B 10 "^services:" docker-compose.yml | grep -v "^services:" > "$TEMP_FILE"
    echo "services:" >> "$TEMP_FILE"
  else
    # 기본 설정이 없으면 services 섹션만 시작
    echo -e "${YELLOW}서비스 섹션만 시작...${NC}"
    echo "services:" > "$TEMP_FILE"
  fi
  
  # 3node 서비스 복사
  echo -e "${YELLOW}3node 서비스 복사 중...${NC}"
  for node in 3node0 3node1 3node2 3node3; do
    if grep -q "  $node:" docker-compose.yml; then
      echo -e "${GREEN}${node} 서비스 발견, 복사 중...${NC}"
      
      # 서비스 시작 라인
      grep -A 1 "  $node:" docker-compose.yml >> "$TEMP_FILE"
      
      # 서비스 내용 복사 (다음 서비스 또는 networks 전까지)
      grep -A 100 "  $node:" docker-compose.yml | grep -v "  $node:" | \
        sed -n '/^  [a-zA-Z0-9_-]\+:/q;p' | \
        grep -v "^networks:" >> "$TEMP_FILE"
    fi
  done
  
  # networks 섹션 재구성
  echo -e "${YELLOW}networks 섹션 재구성 중...${NC}"
  echo "" >> "$TEMP_FILE"  # 빈 줄 추가
  
  if grep -q "driver: bridge" docker-compose.yml; then
    # 기존 networks 섹션에서 일부 정보 추출
    echo "networks:" >> "$TEMP_FILE"
    echo "  creditnet:" >> "$TEMP_FILE"
    echo "    driver: bridge" >> "$TEMP_FILE"
  else
    # 기본 networks 정의 추가
    echo "networks:" >> "$TEMP_FILE"
    echo "  creditnet:" >> "$TEMP_FILE"
    echo "    driver: bridge" >> "$TEMP_FILE"
  fi
  
  # 원본 파일 대체
  mv "$TEMP_FILE" docker-compose.yml
  
  echo -e "${GREEN}docker-compose.yml 파일이 정리되었습니다. 이제 mclient를 추가할 수 있습니다.${NC}"
  return 0
}

# docker-compose.yml 파일 업데이트 (완전 재작성 버전)
update_docker_compose() {
  echo -e "${BLUE}docker-compose.yml 파일 업데이트 중...${NC}"
  
  # docker-compose.yml 파일 확인
  if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}오류: docker-compose.yml 파일이 없습니다.${NC}"
    echo -e "${YELLOW}먼저 기본 docker-compose.yml 파일을 생성하세요.${NC}"
    exit 1
  fi
  
  # docker-compose.yml 파일 백업
  BACKUP_FILE="docker-compose.yml.bak.$(date +%Y%m%d%H%M%S)"
  cp docker-compose.yml "$BACKUP_FILE"
  echo -e "${GREEN}docker-compose.yml 파일이 $BACKUP_FILE으로 백업되었습니다.${NC}"
  
  # Docker 소켓 경로 찾기 (메시지 출력 없음)
  DOCKER_SOCK_PATH=$(find_docker_sock_path)
  
  # 임시 파일 생성
  TEMP_FILE=$(mktemp)
  
  # 먼저, mclient 서비스가 있는지 확인
  if grep -q "  mclient:" docker-compose.yml; then
    echo -e "${YELLOW}기존 mclient 서비스를 제거하고 새로 추가합니다.${NC}"
    
    # 기존 mclient 서비스를 제거 (방법 1: sed 사용)
    sed '/^  mclient:/,/^  [a-zA-Z0-9_-]\+:/{ /^  [a-zA-Z0-9_-]\+:/!d; /^  mclient:/d; }' docker-compose.yml > "$TEMP_FILE"
    
    # 임시 파일 확인
    if [ ! -s "$TEMP_FILE" ]; then
      echo -e "${YELLOW}mclient 서비스 제거 중 문제가 발생했습니다. 파일 정리를 시도합니다.${NC}"
      cleanup_docker_compose
      cp docker-compose.yml "$TEMP_FILE"
    fi
  else
    # mclient 서비스가 없으면 전체 복사
    cp docker-compose.yml "$TEMP_FILE"
  fi
  
  # networks 섹션 위치 확인
  NETWORK_LINE=$(grep -n "^networks:" "$TEMP_FILE" | head -1 | cut -d: -f1)
  
  if [ -z "$NETWORK_LINE" ]; then
    # networks 섹션이 없으면 파일 끝에 추가
    echo -e "${YELLOW}networks 섹션을 찾을 수 없습니다. 파일 끝에 mclient와 networks 섹션을 추가합니다.${NC}"
    
    # mclient 서비스 추가
    echo "" >> "$TEMP_FILE"  # 빈 줄 추가
    echo "  mclient:" >> "$TEMP_FILE"
    echo "    build:" >> "$TEMP_FILE"
    echo "      context: ./mclient" >> "$TEMP_FILE"
    echo "      dockerfile: Dockerfile" >> "$TEMP_FILE"
    echo "    container_name: mclient" >> "$TEMP_FILE"
    echo "    # 호스트 프로세스 네임스페이스 공유" >> "$TEMP_FILE"
    echo "    pid: \"host\"" >> "$TEMP_FILE"
    echo "    # 호스트 네트워크 모드 사용" >> "$TEMP_FILE"
    echo "    network_mode: \"host\"" >> "$TEMP_FILE"
    echo "    volumes:" >> "$TEMP_FILE"
    echo "      # Docker 소켓 마운트" >> "$TEMP_FILE"
    echo "      - ${DOCKER_SOCK_PATH}:/var/run/docker.sock:ro" >> "$TEMP_FILE"
    echo "      # 호스트 시간대 정보" >> "$TEMP_FILE"
    echo "      - /etc/localtime:/etc/localtime:ro" >> "$TEMP_FILE"
    echo "      # 호스트 시스템 정보 접근" >> "$TEMP_FILE"
    echo "      - /proc:/host/proc:ro" >> "$TEMP_FILE"
    echo "      - /sys:/host/sys:ro" >> "$TEMP_FILE"
    echo "      # mclient 디렉토리 마운트" >> "$TEMP_FILE"
    echo "      - ./mclient:/app" >> "$TEMP_FILE"
    echo "    environment:" >> "$TEMP_FILE"
    echo "      - SERVER_ID=${SERVER_ID}" >> "$TEMP_FILE"
    echo "      - NODE_NAMES=${NODE_NAMES}" >> "$TEMP_FILE"
    echo "      - MONITOR_INTERVAL=${MONITOR_INTERVAL}" >> "$TEMP_FILE"
    
    # 모드별 환경 변수
    if [ "$MODE" = "local" ]; then
      echo "      - LOCAL_MODE=true" >> "$TEMP_FILE"
    else
      if [ ! -z "$SERVER_URL" ]; then
        echo "      - SERVER_URL=${SERVER_URL}" >> "$TEMP_FILE"
      fi
      
      if [ ! -z "$SERVER_HOST" ]; then
        echo "      - WS_SERVER_HOST=${SERVER_HOST}" >> "$TEMP_FILE"
      fi
    fi
    
    # SSL 검증 비활성화 설정
    if [ "$NO_SSL_VERIFY" = true ]; then
      echo "      - NO_SSL_VERIFY=true" >> "$TEMP_FILE"
    fi
    
    # 디버그 모드 설정
    if [ "$DEBUG_MODE" = true ]; then
      echo "      - DEBUG_MODE=true" >> "$TEMP_FILE"
    fi
    
    # 공통 환경 변수
    echo "      # Docker 접근을 위한 환경 변수" >> "$TEMP_FILE"
    echo "      - DOCKER_HOST=unix:///var/run/docker.sock" >> "$TEMP_FILE"
    echo "      # 호스트 시스템 정보 접근을 위한 환경 변수" >> "$TEMP_FILE"
    echo "      - HOST_PROC=/host/proc" >> "$TEMP_FILE"
    echo "      - HOST_SYS=/host/sys" >> "$TEMP_FILE"
    
    # networks 섹션 추가
    echo "" >> "$TEMP_FILE"  # 빈 줄 추가
    echo "networks:" >> "$TEMP_FILE"
    echo "  creditnet:" >> "$TEMP_FILE"
    echo "    driver: bridge" >> "$TEMP_FILE"
  else
    # networks 섹션 앞에 mclient 서비스 추가
    NEW_TEMP_FILE=$(mktemp)
    head -n $((NETWORK_LINE-1)) "$TEMP_FILE" > "$NEW_TEMP_FILE"
    
    # mclient 서비스 추가
    echo "" >> "$NEW_TEMP_FILE"  # 빈 줄 추가
    echo "  mclient:" >> "$NEW_TEMP_FILE"
    echo "    build:" >> "$NEW_TEMP_FILE"
    echo "      context: ./mclient" >> "$NEW_TEMP_FILE"
    echo "      dockerfile: Dockerfile" >> "$NEW_TEMP_FILE"
    echo "    container_name: mclient" >> "$NEW_TEMP_FILE"
    echo "    # 호스트 프로세스 네임스페이스 공유" >> "$NEW_TEMP_FILE"
    echo "    pid: \"host\"" >> "$NEW_TEMP_FILE"
    echo "    # 호스트 네트워크 모드 사용" >> "$NEW_TEMP_FILE"
    echo "    network_mode: \"host\"" >> "$NEW_TEMP_FILE"
    echo "    volumes:" >> "$NEW_TEMP_FILE"
    echo "      # Docker 소켓 마운트" >> "$NEW_TEMP_FILE"
    echo "      - ${DOCKER_SOCK_PATH}:/var/run/docker.sock:ro" >> "$NEW_TEMP_FILE"
    echo "      # 호스트 시간대 정보" >> "$NEW_TEMP_FILE"
    echo "      - /etc/localtime:/etc/localtime:ro" >> "$NEW_TEMP_FILE"
    echo "      # 호스트 시스템 정보 접근" >> "$NEW_TEMP_FILE"
    echo "      - /proc:/host/proc:ro" >> "$NEW_TEMP_FILE"
    echo "      - /sys:/host/sys:ro" >> "$NEW_TEMP_FILE"
    echo "      # mclient 디렉토리 마운트" >> "$NEW_TEMP_FILE"
    echo "      - ./mclient:/app" >> "$NEW_TEMP_FILE"
    echo "    environment:" >> "$NEW_TEMP_FILE"
    echo "      - SERVER_ID=${SERVER_ID}" >> "$NEW_TEMP_FILE"
    echo "      - NODE_NAMES=${NODE_NAMES}" >> "$NEW_TEMP_FILE"
    echo "      - MONITOR_INTERVAL=${MONITOR_INTERVAL}" >> "$NEW_TEMP_FILE"
    
    # 모드별 환경 변수
    if [ "$MODE" = "local" ]; then
      echo "      - LOCAL_MODE=true" >> "$NEW_TEMP_FILE"
    else
      if [ ! -z "$SERVER_URL" ]; then
        echo "      - SERVER_URL=${SERVER_URL}" >> "$NEW_TEMP_FILE"
      fi
      
      if [ ! -z "$SERVER_HOST" ]; then
        echo "      - WS_SERVER_HOST=${SERVER_HOST}" >> "$NEW_TEMP_FILE"
      fi
    fi
    
    # SSL 검증 비활성화 설정
    if [ "$NO_SSL_VERIFY" = true ]; then
      echo "      - NO_SSL_VERIFY=true" >> "$NEW_TEMP_FILE"
    fi
    
    # 디버그 모드 설정
    if [ "$DEBUG_MODE" = true ]; then
      echo "      - DEBUG_MODE=true" >> "$NEW_TEMP_FILE"
    fi
    
    # 공통 환경 변수
    echo "      # Docker 접근을 위한 환경 변수" >> "$NEW_TEMP_FILE"
    echo "      - DOCKER_HOST=unix:///var/run/docker.sock" >> "$NEW_TEMP_FILE"
    echo "      # 호스트 시스템 정보 접근을 위한 환경 변수" >> "$NEW_TEMP_FILE"
    echo "      - HOST_PROC=/host/proc" >> "$NEW_TEMP_FILE"
    echo "      - HOST_SYS=/host/sys" >> "$NEW_TEMP_FILE"
    
    # networks 섹션 추가
    echo "" >> "$NEW_TEMP_FILE"  # 빈 줄 추가
    tail -n +$NETWORK_LINE "$TEMP_FILE" >> "$NEW_TEMP_FILE"
    
    # 임시 파일 교체
    mv "$NEW_TEMP_FILE" "$TEMP_FILE"
  fi
  
  # 결과 확인
  if [ ! -s "$TEMP_FILE" ]; then
    echo -e "${RED}오류: docker-compose.yml 파일 처리 중 문제가 발생했습니다.${NC}"
    echo -e "${YELLOW}백업 파일($BACKUP_FILE)을 확인하세요.${NC}"
    rm -f "$TEMP_FILE"
    exit 1
  fi
  
  # 원본 파일 대체
  mv "$TEMP_FILE" docker-compose.yml
  
  # 성공 메시지
  echo -e "${GREEN}mclient 서비스가 docker-compose.yml에 성공적으로 추가되었습니다.${NC}"
  echo -e "${YELLOW}백업 파일: $BACKUP_FILE${NC}"
}

# 대화형 모드 실행
run_interactive_mode() {
  echo -e "${BLUE}=== Creditcoin 모니터링 클라이언트 설정 ====${NC}"
  
  # 노드 자동 감지
  NODE_NAMES=$(detect_nodes)
  
  # 서버 ID 입력 (선택 사항)
  read -p "서버 ID를 입력하세요 ($SERVER_ID): " input
  if [ ! -z "$input" ]; then
    SERVER_ID="$input"
  fi
  
  # 모니터링 간격 입력 (선택 사항)
  read -p "모니터링 간격(초)을 입력하세요 ($MONITOR_INTERVAL): " input
  if [ ! -z "$input" ]; then
    MONITOR_INTERVAL="$input"
  fi
  
  # 모니터링 모드 선택
  echo -e "${YELLOW}모니터링 모드를 선택하세요:${NC}"
  echo "1) 서버 모드 - 중앙 모니터링 서버에 데이터 전송"
  echo "2) 로컬 모드 - 화면에만 표시 (데이터 전송 없음)"
  read -p "선택 (1/2) [1]: " mode_choice
  
  case $mode_choice in
    2)
      MODE="local"
      echo -e "${GREEN}로컬 모드가 선택되었습니다. 데이터가 중앙 서버로 전송되지 않습니다.${NC}"
      ;;
    *)
      MODE="server"
      # 연결 설정
      echo -e "${YELLOW}연결 설정 방식을 선택하세요:${NC}"
      echo "1) 호스트만 지정 - 서버의 호스트 이름이나 IP만 입력 (포트와 경로는 자동 구성)"
      echo "   예: monitor.example.com 또는 192.168.1.100"
      echo "2) 전체 URL 직접 지정 - 프로토콜, 호스트, 포트, 경로를 포함한 전체 URL 입력"
      echo "   예: wss://monitor.example.com:8443/ws"
      read -p "선택 (1/2) [1]: " conn_choice
      
      case $conn_choice in
        2)
          read -p "WebSocket URL을 입력하세요 (예: wss://monitor.example.com/ws): " input_url
          # URL 형식 확인 및 수정
          if [[ ! "$input_url" =~ ^(ws|wss):// ]]; then
            # 프로토콜이 없는 경우, 기본값으로 ws:// 추가
            input_url="ws://$input_url"
            echo -e "${YELLOW}프로토콜이 지정되지 않아 'ws://'를 기본값으로 추가했습니다.${NC}"
          fi
          # 경로가 없는 경우 /ws 추가
          if [[ ! "$input_url" =~ /[^/]+$ ]]; then
            # URL 끝에 슬래시가 없으면 추가
            if [[ ! "$input_url" =~ /$ ]]; then
              input_url="$input_url/"
            fi
            input_url="${input_url}ws"
            echo -e "${YELLOW}경로가 지정되지 않아 '/ws'를 기본값으로 추가했습니다.${NC}"
          fi
          SERVER_URL="$input_url"
          echo -e "${GREEN}설정된 WebSocket URL: $SERVER_URL${NC}"
          ;;
        *)
          # 기본 호스트 감지
          default_host=$(detect_server_host)
          read -p "서버 호스트를 입력하세요 ($default_host): " input
          SERVER_HOST=${input:-$default_host}
          ;;
      esac
      
      # SSL 검증 설정 (기본값은 활성화 = Yes)
      read -p "SSL 인증서 검증을 활성화하시겠습니까? (Y/n): " ssl_choice
      if [[ "$ssl_choice" =~ ^[Nn]$ ]]; then
        NO_SSL_VERIFY=true
        echo -e "${GREEN}SSL 인증서 검증이 비활성화되었습니다.${NC}"
      else
        NO_SSL_VERIFY=false
        echo -e "${GREEN}SSL 인증서 검증이 활성화되었습니다.${NC}"
      fi
      
      # 디버그 모드 설정 (기본값은 비활성화 = No)
      read -p "디버그 모드를 활성화하시겠습니까? (y/N): " debug_choice
      if [[ "$debug_choice" =~ ^[Yy]$ ]]; then
        DEBUG_MODE=true
        echo -e "${GREEN}디버그 모드가 활성화되었습니다.${NC}"
      else
        DEBUG_MODE=false
        echo -e "${GREEN}디버그 모드가 비활성화되었습니다.${NC}"
      fi
      ;;
  esac
  
  # 설정 요약 표시
  echo -e "${BLUE}\n=== 설정 요약 ===${NC}"
  echo -e "${GREEN}서버 ID: $SERVER_ID${NC}"
  echo -e "${GREEN}모니터링 노드: $NODE_NAMES${NC}"
  echo -e "${GREEN}모니터링 간격: ${MONITOR_INTERVAL}초${NC}"
  
  if [ "$MODE" = "local" ]; then
    echo -e "${GREEN}모드: 로컬 (데이터 전송 없음)${NC}"
  else
    echo -e "${GREEN}모드: 서버 연결${NC}"
    if [ ! -z "$SERVER_URL" ]; then
      echo -e "${GREEN}WebSocket URL: $SERVER_URL${NC}"
    fi
    if [ ! -z "$SERVER_HOST" ]; then
      echo -e "${GREEN}WebSocket 호스트: $SERVER_HOST${NC}"
    fi
    if [ "$NO_SSL_VERIFY" = true ]; then
      echo -e "${GREEN}SSL 검증: 비활성화${NC}"
    else
      echo -e "${GREEN}SSL 검증: 활성화${NC}"
    fi
  fi
  
  if [ "$DEBUG_MODE" = true ]; then
    echo -e "${GREEN}디버그 모드: 활성화${NC}"
  else
    echo -e "${GREEN}디버그 모드: 비활성화${NC}"
  fi
  
  # 확인 및 진행
  read -p "위 설정으로 진행하시겠습니까? (Y/n): " confirm
  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo -e "${RED}설치가 취소되었습니다.${NC}"
    exit 0
  fi
}

# 메인 실행 함수
main() {
  # Docker 환경 확인
  check_docker_env
  
  # 명령줄 인자 처리
  parse_args "$@"
  
  # 기본적으로 대화형 모드 실행 (--non-interactive 옵션이 없을 때)
  if [ "$NON_INTERACTIVE" = false ]; then
    run_interactive_mode
  else
    # 비대화형 모드에서는 노드 자동 감지
    if [ -z "$NODE_NAMES" ]; then
      NODE_NAMES=$(detect_nodes)
    fi
    
    # 비대화형 모드에서 호스트 자동 감지 (설정되지 않은 경우)
    if [ -z "$SERVER_HOST" ] && [ "$MODE" = "server" ] && [ -z "$SERVER_URL" ]; then
      SERVER_HOST=$(detect_server_host)
    fi
  fi
  
  # 필요한 파일 준비
  prepare_client_files
  
  # Dockerfile 생성
  create_dockerfile
  
  # .env 파일 생성
  create_env_file
  
  # docker-compose.yml 파일이 이상하면 정리 먼저 시도
  if grep -q "creditnet:" docker-compose.yml && ! grep -q "networks:" docker-compose.yml; then
    echo -e "${YELLOW}docker-compose.yml 파일이 잘못된 형식입니다. 정리 시도...${NC}"
    cleanup_docker_compose
  fi
  
  # docker-compose.yml 파일 업데이트
  update_docker_compose
  
  echo -e "${BLUE}===================================================${NC}"
  echo -e "${GREEN}Creditcoin 모니터링 클라이언트 설정이 완료되었습니다!${NC}"
  
  # 컨테이너 시작 여부 확인
  read -p "모니터링 클라이언트를 지금 시작하시겠습니까? (Y/n): " start_now
  if [[ -z "$start_now" || ! "$start_now" =~ ^[Nn]$ ]]; then
    echo -e "${BLUE}이전 mclient 컨테이너 확인 및 제거 중...${NC}"
    # 기존 mclient 컨테이너 제거
    if docker ps -a --format "{{.Names}}" | grep -q "mclient$"; then
      echo -e "${YELLOW}기존 mclient 컨테이너가 발견되었습니다. 제거합니다...${NC}"
      docker stop mclient 2>/dev/null || true
      docker rm mclient 2>/dev/null || true
      echo -e "${GREEN}기존 컨테이너가 제거되었습니다.${NC}"
    fi
    
    echo -e "${BLUE}모니터링 클라이언트를 시작합니다...${NC}"
    docker compose -p creditcoin3 up -d mclient
    
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}모니터링 클라이언트가 성공적으로 시작되었습니다.${NC}"
      echo -e "${YELLOW}로그 확인: ${GREEN}docker compose -p creditcoin3 logs -f mclient${NC}"
      echo -e "${YELLOW}또는 명령어 사용: ${GREEN}mclogs${NC}"
    else
      echo -e "${RED}모니터링 클라이언트 시작에 실패했습니다.${NC}"
      echo -e "${YELLOW}로그를 확인하여 문제를 진단하세요.${NC}"
    fi
  else
    echo -e "${YELLOW}모니터링 클라이언트를 시작하지 않았습니다.${NC}"
    echo -e "${YELLOW}나중에 다음 명령어로 시작할 수 있습니다:${NC}"
    echo -e "${GREEN}docker compose -p creditcoin3 up -d mclient${NC}"
    echo -e "${YELLOW}또는 간단히: ${GREEN}mcstart${NC}"
  fi
  
  echo -e "${BLUE}===================================================${NC}"
  echo -e "${YELLOW}사용 가능한 명령어:${NC}"
  echo -e "${GREEN}mcstart${NC}     - 모니터링 클라이언트 시작"
  echo -e "${GREEN}mcstop${NC}      - 모니터링 클라이언트 중지"
  echo -e "${GREEN}mcrestart${NC}   - 모니터링 클라이언트 재시작"
  echo -e "${GREEN}mclogs${NC}      - 모니터링 클라이언트 로그 표시"
  echo -e "${GREEN}mcstatus${NC}    - 모니터링 클라이언트 상태 확인"
  echo -e "${GREEN}mclocal${NC}     - 로컬 모드로 모니터링 클라이언트 실행"
  echo -e "${BLUE}===================================================${NC}"
}

# 스크립트 실행
main "$@"