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
FORCE=true
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
  
  # 소스 디렉토리 (mclient_org)
  local SRC_DIR="${CURRENT_DIR}/mclient_org"
  
  # 소스 디렉토리 존재 확인
  if [ ! -d "$SRC_DIR" ]; then
    echo -e "${RED}오류: mclient_org 디렉토리를 찾을 수 없습니다.${NC}"
    echo -e "${YELLOW}현재 디렉토리: $(pwd)${NC}"
    exit 1
  fi
  
  # 필요한 파일들 목록
  local files=(
    "main.py" 
    "docker_stats_client.py" 
    "websocket_client.py" 
    "requirements.txt"
  )
  
  # 각 파일 복사
  for file in "${files[@]}"; do
    local src_file="${SRC_DIR}/${file}"
    
    # 파일 존재 확인
    if [ -f "$src_file" ]; then
      echo -e "${YELLOW}복사 중: ${file}${NC}"
      cp "$src_file" "${MCLIENT_DIR}/${file}"
      echo -e "${GREEN}${file} 복사 완료${NC}"
    else
      echo -e "${RED}오류: ${SRC_DIR}/${file} 파일을 찾을 수 없습니다.${NC}"
      exit 1
    fi
  done
  
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

# docker-compose.yml 파일 업데이트
update_docker_compose() {
  echo -e "${BLUE}docker-compose.yml 파일 업데이트 중...${NC}"
  
  # docker-compose.yml 파일 확인
  if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}오류: docker-compose.yml 파일이 없습니다.${NC}"
    echo -e "${YELLOW}먼저 기본 docker-compose.yml 파일을 생성하세요.${NC}"
    exit 1
  fi
  
  # docker-compose.yml 파일 백업
  cp docker-compose.yml docker-compose.yml.bak.$(date +%Y%m%d%H%M%S)
  echo -e "${GREEN}docker-compose.yml 파일이 백업되었습니다.${NC}"
  
  # Docker 소켓 경로 찾기 (메시지 출력 없음)
  DOCKER_SOCK_PATH=$(find_docker_sock_path)
  
  # 환경 변수 설정
  mclient_environment="      - SERVER_ID=${SERVER_ID}\n"
  mclient_environment+="      - NODE_NAMES=${NODE_NAMES}\n"
  mclient_environment+="      - MONITOR_INTERVAL=${MONITOR_INTERVAL}\n"
  
  # 모드별 환경 변수
  if [ "$MODE" = "local" ]; then
    mclient_environment+="      - LOCAL_MODE=true\n"
  else
    if [ ! -z "$SERVER_URL" ]; then
      mclient_environment+="      - SERVER_URL=${SERVER_URL}\n"
    fi
    
    if [ ! -z "$SERVER_HOST" ]; then
      mclient_environment+="      - WS_SERVER_HOST=${SERVER_HOST}\n"
    fi
  fi
  
  # SSL 검증 비활성화 설정
  if [ "$NO_SSL_VERIFY" = true ]; then
    mclient_environment+="      - NO_SSL_VERIFY=true\n"
  fi
  
  # 디버그 모드 설정
  if [ "$DEBUG_MODE" = true ]; then
    mclient_environment+="      - DEBUG_MODE=true\n"
  fi
  
  # 공통 환경 변수
  mclient_environment+="      # Docker 접근을 위한 환경 변수\n"
  mclient_environment+="      - DOCKER_HOST=unix:///var/run/docker.sock\n"
  mclient_environment+="      # 호스트 시스템 정보 접근을 위한 환경 변수\n"
  mclient_environment+="      - HOST_PROC=/host/proc\n"
  mclient_environment+="      - HOST_SYS=/host/sys\n"
  
  # mclient 서비스 블록 생성
  mclient_service=$(cat << EOF

  mclient:
    build:
      context: ./mclient
      dockerfile: Dockerfile
    container_name: mclient
    # 호스트 프로세스 네임스페이스 공유
    pid: "host"
    # 호스트 네트워크 모드 사용
    network_mode: "host"
    volumes:
      # Docker 소켓 마운트
      - ${DOCKER_SOCK_PATH}:/var/run/docker.sock:ro
      # 호스트 시간대 정보
      - /etc/localtime:/etc/localtime:ro
      # 호스트 시스템 정보 접근
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      # mclient 디렉토리 마운트
      - ./mclient:/app
    environment:
${mclient_environment}
EOF
)
  
  # 임시 파일 생성
  TEMP_FILE=$(mktemp)
  
  # 기존 파일에서 mclient 서비스 제거
  if grep -q "  mclient:" docker-compose.yml; then
    echo -e "${YELLOW}mclient 서비스가 이미 존재합니다. 삭제 후 재생성합니다...${NC}"
    
    # mclient 서비스를 제외한 모든 내용 임시 파일에 복사
    awk '
    BEGIN { print_line = 1; in_mclient = 0; }
    /^  mclient:/ { in_mclient = 1; print_line = 0; next; }
    /^  [a-zA-Z0-9_-]+:/ && in_mclient { in_mclient = 0; print_line = 1; }
    { if (print_line) print $0; }
    ' docker-compose.yml > "$TEMP_FILE"
    
    # 결과 확인
    if [ ! -s "$TEMP_FILE" ]; then
      echo -e "${RED}오류: docker-compose.yml 파일 처리 중 문제가 발생했습니다.${NC}"
      rm -f "$TEMP_FILE"
      exit 1
    fi
    
    # 원본 파일 대체
    cp "$TEMP_FILE" docker-compose.yml
    rm -f "$TEMP_FILE"
  fi
  
  # 파일에 서비스 추가 위치 결정 (네트워크 섹션이나 파일 끝)
  INSERTION_POINT=$(grep -n "^networks:" docker-compose.yml 2>/dev/null | head -1 | cut -d: -f1)
  
  if [ -z "$INSERTION_POINT" ]; then
    # networks 섹션이 없으면 파일 끝에 추가
    echo -e "${YELLOW}docker-compose.yml 파일에서 networks 섹션을 찾을 수 없습니다. 파일 끝에 추가합니다.${NC}"
    echo -e "$mclient_service" >> docker-compose.yml
  else
    # networks 섹션 앞에 추가
    TEMP_FILE=$(mktemp)
    head -n $((INSERTION_POINT-1)) docker-compose.yml > "$TEMP_FILE"
    echo -e "$mclient_service" >> "$TEMP_FILE"
    tail -n +$((INSERTION_POINT)) docker-compose.yml >> "$TEMP_FILE"
    
    # 결과 확인
    if [ ! -s "$TEMP_FILE" ]; then
      echo -e "${RED}오류: docker-compose.yml 파일 수정 중 문제가 발생했습니다.${NC}"
      rm -f "$TEMP_FILE"
      exit 1
    fi
    
    # 원본 파일 대체
    cp "$TEMP_FILE" docker-compose.yml
    rm -f "$TEMP_FILE"
  fi
  
  echo -e "${GREEN}mclient 서비스가 docker-compose.yml에 추가되었습니다.${NC}"
}

# 대화형 모드 실행
run_interactive_mode() {
  echo -e "${BLUE}=== Creditcoin 모니터링 클라이언트 설정 ====${NC}"
  
  # 노드 자동 감지
  NODE_NAMES=$(detect_nodes)
  
  # 서버 ID 입력 (선택 사항)
  read -p "서버 ID를 입력하세요 (기본값: $SERVER_ID): " input
  if [ ! -z "$input" ]; then
    SERVER_ID="$input"
  fi
  
  # 모니터링 간격 입력 (선택 사항)
  read -p "모니터링 간격(초)을 입력하세요 (기본값: $MONITOR_INTERVAL): " input
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
          read -p "서버 호스트를 입력하세요 (기본값: $default_host): " input
          SERVER_HOST=${input:-$default_host}
          ;;
      esac
      
      # SSL 검증 설정 (기본값은 활성화 = No)
      read -p "SSL 인증서 검증을 비활성화하시겠습니까? (y/N): " ssl_choice
      if [[ "$ssl_choice" =~ ^[Yy]$ ]]; then
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
  # setupmc.sh가 먼저 실행되었는지 확인
  if [ ! -d "$MCLIENT_DIR" ]; then
    echo -e "${RED}오류: mclient 디렉토리가 없습니다.${NC}"
    echo -e "${YELLOW}먼저 setupmc.sh를 실행하여 기본 환경을 설정하세요.${NC}"
    exit 1
  fi
  
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