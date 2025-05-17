#!/bin/bash
# addmclient.sh - Creditcoin 모니터링 클라이언트 추가 스크립트 (개선 버전)

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# GitHub 저장소 정보
GITHUB_REPO="sigmo2nd/creditcoin-mac"
GITHUB_BRANCH="monitoring"
MCLIENT_ORG_DIR="mclient_org"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/${MCLIENT_ORG_DIR}"

# 기본값 설정
SERVER_ID="server1"
MONITOR_INTERVAL="5"
WS_MODE="auto"  # 기본값을 auto로 변경
WS_SERVER_URL=""
WS_SERVER_HOST=""
NO_SSL_VERIFY=false
CREDITCOIN_DIR=$(pwd)
FORCE=true  # 기본적으로 설정 덮어쓰기
NON_INTERACTIVE=false

# Docker 명령어 및 환경 확인
check_docker_env() {
  echo -e "${BLUE}Docker 환경 확인 중...${NC}"
  
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
  echo "  --mode MODE         연결 모드: auto, custom, ws, wss, local (기본값: auto)"
  echo "  --url URL           WebSocket URL 직접 지정 (custom 모드 사용)"
  echo "  --host HOST         WebSocket 서버 호스트 지정"
  echo "  --no-ssl-verify     SSL 인증서 검증 비활성화"
  echo "  --help, -h          이 도움말 표시"
  echo ""
  echo "사용 예시:"
  echo "  $0                                 # 대화형 모드로 실행"
  echo "  $0 --mode custom --url wss://192.168.0.24:8443/ws  # 사용자 지정 URL 사용"
  echo "  $0 --mode ws --host 192.168.0.24   # WS 프로토콜 + 호스트 지정"
  echo "  $0 --mode local                    # 로컬 모드 (WebSocket 연결 없음)"
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
        WS_MODE="$2"
        shift 2
        ;;
      --url)
        WS_SERVER_URL="$2"
        WS_MODE="custom"
        shift 2
        ;;
      --host)
        WS_SERVER_HOST="$2"
        shift 2
        ;;
      --no-ssl-verify)
        NO_SSL_VERIFY=true
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
  echo -e "${BLUE}실행 중인 Creditcoin 노드 감지 중...${NC}"
  
  # Docker 컨테이너 목록에서 node 또는 3node로 시작하는 컨테이너 찾기
  local nodes=""
  nodes=$(docker ps --format "{{.Names}}" | grep -E '^(node|3node)' | tr '\n' ',' | sed 's/,$//')
  
  if [ -z "$nodes" ]; then
    echo -e "${YELLOW}실행 중인 Creditcoin 노드를 찾을 수 없습니다. 기본값을 사용합니다.${NC}"
    echo "node,3node"
    return
  fi
  
  echo -e "${GREEN}감지된 노드: $nodes${NC}"
  echo "$nodes"
}

# 외부 IP 주소 감지
detect_external_ip() {
  echo -e "${BLUE}외부 IP 주소 감지 중...${NC}"
  
  # 여러 서비스를 시도하여 외부 IP 주소 찾기
  local external_ip=""
  external_ip=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || curl -s https://icanhazip.com)
  
  if [ -n "$external_ip" ]; then
    echo -e "${GREEN}외부 IP 주소: $external_ip${NC}"
    echo "$external_ip"
    return
  fi
  
  # 외부 IP를 찾지 못하면 로컬 네트워크 IP 시도
  echo -e "${YELLOW}외부 IP 주소를 찾을 수 없습니다. 로컬 네트워크 IP 감지를 시도합니다.${NC}"
  
  # 다양한 플랫폼에서 작동하는 IP 감지 방법
  if command -v ifconfig &> /dev/null; then
    local local_ip=""
    # Linux/macOS
    local_ip=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | sed 's/addr://')
    if [ -n "$local_ip" ]; then
      echo -e "${GREEN}로컬 네트워크 IP: $local_ip${NC}"
      echo "$local_ip"
      return
    fi
  elif command -v ip &> /dev/null; then
    # 새로운 Linux 배포판
    local local_ip=""
    local_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
    if [ -n "$local_ip" ]; then
      echo -e "${GREEN}로컬 네트워크 IP: $local_ip${NC}"
      echo "$local_ip"
      return
    fi
  fi
  
  echo -e "${YELLOW}IP 주소를 자동으로 감지할 수 없습니다. 기본값 'localhost'를 사용합니다.${NC}"
  echo "localhost"
}

# Docker 소켓 경로 찾기
find_docker_sock_path() {
  echo -e "${BLUE}Docker 소켓 경로 감지 중...${NC}"
  
  # 기본 OrbStack Docker 소켓 경로
  local docker_sock_path="$HOME/.orbstack/run/docker.sock"
  
  if [ -S "$docker_sock_path" ]; then
    echo -e "${GREEN}Docker 소켓 발견: $docker_sock_path${NC}"
    echo "$docker_sock_path"
    return
  fi
  
  echo -e "${YELLOW}OrbStack Docker 소켓을 찾을 수 없습니다. 다른 경로를 시도합니다...${NC}"
  
  # 대체 가능한 Docker 소켓 경로 목록
  local possible_paths=(
    "/var/run/docker.sock"
    "/var/run/orbstack/docker.sock"
    "$HOME/Library/Containers/com.orbstack.Orbstack/Data/run/docker.sock"
  )
  
  for path in "${possible_paths[@]}"; do
    if [ -S "$path" ]; then
      echo -e "${GREEN}Docker 소켓 발견: $path${NC}"
      echo "$path"
      return
    fi
  done
  
  echo -e "${RED}Docker 소켓을 찾을 수 없습니다. 기본 경로를 사용합니다.${NC}"
  echo "/var/run/docker.sock"
}

# 셸 함수 추가
setup_shell_functions() {
  echo -e "${BLUE}셸 함수 설정 중...${NC}"
  
  # 사용자 셸 감지
  local user_shell=$(basename "$SHELL")
  local shell_profile=""
  
  if [[ "$user_shell" == "zsh" ]]; then
    shell_profile="$HOME/.zshrc"
  else
    shell_profile="$HOME/.bash_profile"
    # bash_profile이 없으면 bashrc 사용
    if [ ! -f "$shell_profile" ]; then
      shell_profile="$HOME/.bashrc"
    fi
  fi
  
  echo -e "${BLUE}사용자 셸: $user_shell, 프로필 파일: $shell_profile${NC}"
  
  # 마커 문자열 설정
  local marker="# === Creditcoin Monitor Client Utils ==="
  local endmarker="# === End Creditcoin Monitor Client Utils ==="
  
  # 기존 설정 제거
  if grep -q "$marker" "$shell_profile" 2>/dev/null; then
    echo -e "${YELLOW}기존 셸 함수 설정 제거 중...${NC}"
    cp "$shell_profile" "${shell_profile}.bak.$(date +%Y%m%d%H%M%S)"
    sed -i.tmp "/$marker/,/$endmarker/d" "$shell_profile"
    rm -f "${shell_profile}.tmp"
  fi
  
  # 현재 디렉토리의 절대 경로 획득
  local current_dir=$(pwd)
  
  # 개선된 함수 추가
  cat >> "$shell_profile" << EOT
$marker
# Creditcoin 모니터링 클라이언트 설정
export MCLIENT_DIR="$current_dir/mclient"

# 모니터링 클라이언트 유틸리티 함수
mclient-start() {
  echo -e "${BLUE}모니터링 클라이언트 시작 중...${NC}"
  cd "$current_dir" && docker compose -p creditcoin3 up -d mclient
}

mclient-stop() {
  echo -e "${BLUE}모니터링 클라이언트 중지 중...${NC}"
  cd "$current_dir" && docker compose -p creditcoin3 stop mclient
}

mclient-restart() {
  echo -e "${BLUE}모니터링 클라이언트 재시작 중...${NC}"
  cd "$current_dir" && docker compose -p creditcoin3 restart mclient
}

mclient-logs() {
  echo -e "${BLUE}모니터링 클라이언트 로그 표시 중...${NC}"
  cd "$current_dir" && docker compose -p creditcoin3 logs -f mclient
}

mclient-status() {
  echo -e "${BLUE}모니터링 클라이언트 상태 확인 중...${NC}"
  if docker ps | grep -q mclient; then
    echo -e "${GREEN}모니터링 클라이언트가 실행 중입니다.${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep mclient
  else
    echo -e "${RED}모니터링 클라이언트가 실행 중이 아닙니다.${NC}"
  fi
}

mclient-local() {
  echo -e "${BLUE}모니터링 클라이언트 로컬 모드로 실행 중...${NC}"
  cd "$MCLIENT_DIR" && python3 main.py --local
}
$endmarker
EOT

  echo -e "${GREEN}셸 함수가 $shell_profile에 추가되었습니다.${NC}"
  echo -e "${YELLOW}새 터미널을 열거나 'source $shell_profile' 명령어를 실행하여 함수를 사용할 수 있습니다.${NC}"
  
  # 현재 세션에 함수 로드 시도
  if [ -f "$shell_profile" ]; then
    echo -e "${BLUE}현재 세션에 함수 로드 중...${NC}"
    source "$shell_profile" 2>/dev/null || true
  fi
}

# 필요한 파일 다운로드
download_mclient_files() {
  echo -e "${BLUE}모니터링 클라이언트 필수 파일 다운로드 중...${NC}"
  
  # mclient 디렉토리 확인 및 생성
  if [ ! -d "./mclient" ]; then
    mkdir -p ./mclient
    echo -e "${GREEN}mclient 디렉토리를 생성했습니다.${NC}"
  else
    echo -e "${BLUE}기존 mclient 디렉토리를 사용합니다.${NC}"
  fi
  
  # 다운로드할 파일 목록
  local files=("config.py" "docker_stats_client.py" "websocket_client.py" "main.py" "requirements.txt" "start.sh")
  
  # 각 파일 다운로드
  for file in "${files[@]}"; do
    echo -e "${YELLOW}다운로드 중: ${file}${NC}"
    
    # curl로 파일 다운로드
    if curl -s -o "./mclient/${file}" "${GITHUB_RAW_URL}/${file}"; then
      echo -e "${GREEN}${file} 다운로드 완료${NC}"
      
      # 실행 파일 권한 부여
      if [[ "${file}" == *.sh ]]; then
        chmod +x "./mclient/${file}"
        echo -e "${GREEN}${file}에 실행 권한 부여${NC}"
      fi
    else
      echo -e "${RED}${file} 다운로드 실패${NC}"
      echo -e "${YELLOW}GitHub 저장소 접근 권한을 확인하세요: ${GITHUB_RAW_URL}/${NC}"
      exit 1
    fi
  done
  
  echo -e "${GREEN}모든 필수 파일 다운로드 완료${NC}"
}

# Dockerfile 생성
create_dockerfile() {
  echo -e "${BLUE}Dockerfile 생성 중...${NC}"
  
  cat > ./mclient/Dockerfile << 'EOF'
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
RUN chmod +x /app/main.py

# 스타트업 스크립트 생성
RUN echo '#!/bin/bash' > /app/docker-entrypoint.sh && \
    echo 'echo "== Creditcoin 모니터링 클라이언트 ==" ' >> /app/docker-entrypoint.sh && \
    echo 'echo "서버 ID: ${SERVER_ID}"' >> /app/docker-entrypoint.sh && \
    echo 'echo "모니터링 노드: ${NODE_NAMES}"' >> /app/docker-entrypoint.sh && \
    echo 'echo "모니터링 간격: ${MONITOR_INTERVAL}초"' >> /app/docker-entrypoint.sh && \
    echo 'echo "WebSocket 모드: ${WS_MODE}"' >> /app/docker-entrypoint.sh && \
    echo 'if [ "${WS_SERVER_HOST}" != "" ]; then echo "WebSocket 호스트: ${WS_SERVER_HOST}"; fi' >> /app/docker-entrypoint.sh && \
    echo 'if [ "${WS_SERVER_URL}" != "" ]; then echo "WebSocket URL: ${WS_SERVER_URL}"; fi' >> /app/docker-entrypoint.sh && \
    echo 'echo "시작 중..."' >> /app/docker-entrypoint.sh && \
    echo 'export PROCFS_PATH=/host/proc' >> /app/docker-entrypoint.sh && \
    echo 'python /app/main.py "$@"' >> /app/docker-entrypoint.sh && \
    chmod +x /app/docker-entrypoint.sh

# 시작 명령어
ENTRYPOINT ["/app/docker-entrypoint.sh"]

# 헬스체크
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD ps aux | grep python | grep main.py || exit 1
EOF

  echo -e "${GREEN}Dockerfile이 생성되었습니다.${NC}"
}

# mclient/.env 파일 업데이트
update_env_file() {
  echo -e "${BLUE}.env 파일 업데이트 중...${NC}"
  
  # mclient/.env 파일 생성
  cat > ./mclient/.env << EOF
# 모니터링 클라이언트 기본 설정
SERVER_ID=${SERVER_ID}
NODE_NAMES=${NODE_NAMES}
MONITOR_INTERVAL=${MONITOR_INTERVAL}

# WebSocket 설정
WS_MODE=${WS_MODE}
EOF

  # WebSocket 모드에 따른 추가 설정
  if [ "$WS_MODE" = "custom" ] && [ ! -z "$WS_SERVER_URL" ]; then
    echo "WS_SERVER_URL=${WS_SERVER_URL}" >> ./mclient/.env
  fi
  
  if [ ! -z "$WS_SERVER_HOST" ]; then
    echo "WS_SERVER_HOST=${WS_SERVER_HOST}" >> ./mclient/.env
  fi
  
  # SSL 검증 설정
  if [ "$NO_SSL_VERIFY" = true ]; then
    echo "NO_SSL_VERIFY=true" >> ./mclient/.env
  fi
  
  # 디렉토리 설정
  echo -e "\n# 디렉토리 설정\nCREDITCOIN_DIR=${CREDITCOIN_DIR}" >> ./mclient/.env
  
  echo -e "${GREEN}.env 파일이 업데이트되었습니다.${NC}"
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
  
  # Docker 소켓 경로 찾기
  DOCKER_SOCK_PATH=$(find_docker_sock_path)
  
  # mclient 서비스가 이미 있는지 확인
  if grep -q "  mclient:" docker-compose.yml; then
    if [ "$FORCE" = "true" ]; then
      echo -e "${YELLOW}mclient 서비스가 이미 존재합니다. 업데이트합니다...${NC}"
      # mclient 서비스 라인 찾기
      mclient_line=$(grep -n "  mclient:" docker-compose.yml | cut -d: -f1)
      
      # mclient 서비스 블록 제거
      # 다음 서비스나 networks 섹션 시작 위치 찾기
      next_service_line=$(awk "/^  [a-zA-Z0-9_-]+:/ && NR > $mclient_line && !/^  mclient:/" {print NR; exit} docker-compose.yml)
      if [ -z "$next_service_line" ]; then
        next_service_line=$(grep -n "^networks:" docker-compose.yml | cut -d: -f1)
      fi
      
      if [ -n "$next_service_line" ]; then
        # mclient 서비스 블록 제거
        sed -i.tmp "${mclient_line},$(($next_service_line-1))d" docker-compose.yml
        rm -f docker-compose.yml.tmp
      else
        echo -e "${RED}오류: docker-compose.yml 파일 구조를 이해할 수 없습니다.${NC}"
        exit 1
      fi
    else
      echo -e "${YELLOW}mclient 서비스가 이미 존재합니다. FORCE 옵션이 꺼져 있어 업데이트를 건너뜁니다.${NC}"
      return
    fi
  fi
  
  # networks 섹션 위치 찾기
  networks_line=$(grep -n "^networks:" docker-compose.yml | cut -d: -f1)
  
  if [ -n "$networks_line" ]; then
    # 기본 환경 변수 설정
    mclient_environment="      - SERVER_ID=${SERVER_ID}\n"
    mclient_environment+="      - NODE_NAMES=${NODE_NAMES}\n"
    mclient_environment+="      - MONITOR_INTERVAL=${MONITOR_INTERVAL}\n"
    mclient_environment+="      - WS_MODE=${WS_MODE}\n"
    
    # 모드별 추가 환경 변수
    if [ "$WS_MODE" = "custom" ] && [ ! -z "$WS_SERVER_URL" ]; then
      mclient_environment+="      - WS_SERVER_URL=${WS_SERVER_URL}\n"
    fi
    
    if [ ! -z "$WS_SERVER_HOST" ]; then
      mclient_environment+="      - WS_SERVER_HOST=${WS_SERVER_HOST}\n"
    fi
    
    # SSL 검증 비활성화 설정
    if [ "$NO_SSL_VERIFY" = true ]; then
      mclient_environment+="      - NO_SSL_VERIFY=true\n"
    fi
    
    # 공통 환경 변수
    mclient_environment+="      - CREDITCOIN_DIR=/creditcoin-mac\n"
    mclient_environment+="      # Docker 접근을 위한 환경 변수\n"
    mclient_environment+="      - DOCKER_HOST=unix:///var/run/docker.sock\n"
    mclient_environment+="      - DOCKER_API_VERSION=1.41\n"
    mclient_environment+="      # 호스트 시스템 정보 접근을 위한 환경 변수\n"
    mclient_environment+="      - HOST_PROC=/host/proc\n"
    mclient_environment+="      - HOST_SYS=/host/sys\n"
    
    # mclient 서비스 블록 생성
    mclient_service=$(cat << EOF

  mclient:
    <<: *node-defaults
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
    
    # networks 섹션 앞에 mclient 서비스 삽입
    head -n $((networks_line-1)) docker-compose.yml > docker-compose.yml.new
    echo -e "$mclient_service" >> docker-compose.yml.new
    tail -n +$((networks_line)) docker-compose.yml >> docker-compose.yml.new
    mv docker-compose.yml.new docker-compose.yml
    
    echo -e "${GREEN}mclient 서비스가 docker-compose.yml에 추가되었습니다.${NC}"
  else
    echo -e "${RED}오류: docker-compose.yml 파일에서 networks 섹션을 찾을 수 없습니다.${NC}"
    exit 1
  fi
}

# 연결 테스트 함수
test_connection() {
  local ws_host=$1
  local ws_port=$2
  local protocol=$3
  
  echo -e "${BLUE}WebSocket 서버 연결 테스트 중... (${protocol}://${ws_host}:${ws_port})${NC}"
  
  # 먼저 호스트에 ping 테스트
  if ping -c 1 -W 2 "$ws_host" &>/dev/null; then
    echo -e "${GREEN}호스트 ${ws_host}에 접속 가능합니다.${NC}"
  else
    echo -e "${YELLOW}경고: 호스트 ${ws_host}에 ping할 수 없습니다. 방화벽이 활성화되어 있거나 호스트가 다운되었을 수 있습니다.${NC}"
  fi
  
  # 포트 연결 테스트
  if command -v nc &>/dev/null; then
    if nc -z -w 2 "$ws_host" "$ws_port" 2>/dev/null; then
      echo -e "${GREEN}${ws_host}:${ws_port} 포트에 접속 가능합니다.${NC}"
      return 0
    else
      echo -e "${YELLOW}경고: ${ws_host}:${ws_port} 포트에 접속할 수 없습니다. 방화벽이 차단하거나 해당 포트에 서비스가 실행되지 않을 수 있습니다.${NC}"
    fi
  elif command -v telnet &>/dev/null; then
    if echo -n | telnet "$ws_host" "$ws_port" 2>/dev/null >/dev/null; then
      echo -e "${GREEN}${ws_host}:${ws_port} 포트에 접속 가능합니다.${NC}"
      return 0
    else
      echo -e "${YELLOW}경고: ${ws_host}:${ws_port} 포트에 접속할 수 없습니다. 방화벽이 차단하거나 해당 포트에 서비스가 실행되지 않을 수 있습니다.${NC}"
    fi
  else
    echo -e "${YELLOW}경고: 포트 연결을 테스트할 도구(nc 또는 telnet)가 없습니다.${NC}"
  fi
  
  return 1
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
  
  # 연결 모드 선택
  echo -e "${YELLOW}연결 모드를 선택하세요:${NC}"
  echo "1) 자동 모드 (auto) - 자동으로 적절한 연결 방식 선택"
  echo "2) 사용자 지정 URL (custom) - WebSocket URL 직접 지정"
  echo "3) WS 프로토콜 (ws) - 암호화되지 않은 WebSocket 사용"
  echo "4) WSS 프로토콜 (wss) - 암호화된 WebSocket 사용"
  echo "5) 로컬 모드 (local) - WebSocket 서버 연결 없이 실행"
  read -p "선택 (1-5) [기본값: 1]: " mode_choice
  
  case $mode_choice in
    2)
      WS_MODE="custom"
      read -p "WebSocket URL을 입력하세요 (예: wss://192.168.0.24:8443/ws): " WS_SERVER_URL
      read -p "SSL 인증서 검증을 건너뛰겠습니까? (y/n) [기본값: y]: " ssl_choice
      if [[ -z "$ssl_choice" || "$ssl_choice" =~ ^[Yy]$ ]]; then
        NO_SSL_VERIFY=true
      else
        NO_SSL_VERIFY=false
      fi
      ;;
    3)
      WS_MODE="ws"
      # 외부 IP 주소 감지
      default_host=$(detect_external_ip)
      read -p "WebSocket 서버 호스트를 입력하세요 (기본값: $default_host): " input
      WS_SERVER_HOST=${input:-$default_host}
      
      # 연결 테스트
      test_connection "$WS_SERVER_HOST" "8080" "ws"
      ;;
    4)
      WS_MODE="wss"
      # 외부 IP 주소 감지
      default_host=$(detect_external_ip)
      read -p "WebSocket 서버 호스트를 입력하세요 (기본값: $default_host): " input
      WS_SERVER_HOST=${input:-$default_host}
      
      read -p "SSL 인증서 검증을 건너뛰겠습니까? (y/n) [기본값: y]: " ssl_choice
      if [[ -z "$ssl_choice" || "$ssl_choice" =~ ^[Yy]$ ]]; then
        NO_SSL_VERIFY=true
      else
        NO_SSL_VERIFY=false
      fi
      
      # 연결 테스트
      test_connection "$WS_SERVER_HOST" "8443" "wss"
      ;;
    5)
      WS_MODE="local"
      echo -e "${GREEN}로컬 모드가 선택되었습니다. WebSocket 서버 연결 없이 실행됩니다.${NC}"
      ;;
    *)
      WS_MODE="auto"
      # 외부 IP 주소 감지
      default_host=$(detect_external_ip)
      read -p "WebSocket 서버 호스트를 입력하세요 (기본값: $default_host): " input
      WS_SERVER_HOST=${input:-$default_host}
      
      read -p "SSL 인증서 검증을 건너뛰겠습니까? (y/n) [기본값: y]: " ssl_choice
      if [[ -z "$ssl_choice" || "$ssl_choice" =~ ^[Yy]$ ]]; then
        NO_SSL_VERIFY=true
      else
        NO_SSL_VERIFY=false
      fi
      
      # 연결 테스트
      test_connection "$WS_SERVER_HOST" "8443" "wss"
      if [ $? -ne 0 ]; then
        test_connection "$WS_SERVER_HOST" "8080" "ws"
      fi
      ;;
  esac
  
  # 설정 요약 표시
  echo -e "${BLUE}\n=== 설정 요약 ===${NC}"
  echo -e "${GREEN}서버 ID: $SERVER_ID${NC}"
  echo -e "${GREEN}모니터링 노드: $NODE_NAMES${NC}"
  echo -e "${GREEN}모니터링 간격: ${MONITOR_INTERVAL}초${NC}"
  echo -e "${GREEN}연결 모드: $WS_MODE${NC}"
  
  case $WS_MODE in
    "custom")
      echo -e "${GREEN}WebSocket URL: $WS_SERVER_URL${NC}"
      if [ "$NO_SSL_VERIFY" = true ]; then
        echo -e "${GREEN}SSL 검증: 비활성화${NC}"
      else
        echo -e "${GREEN}SSL 검증: 활성화${NC}"
      fi
      ;;
    "ws"|"wss"|"auto")
      echo -e "${GREEN}WebSocket 호스트: $WS_SERVER_HOST${NC}"
      if [ "$WS_MODE" = "ws" ]; then
        echo -e "${GREEN}WebSocket 포트: 8080${NC}"
      elif [ "$WS_MODE" = "wss" ]; then
        echo -e "${GREEN}WebSocket 포트: 8443${NC}"
        if [ "$NO_SSL_VERIFY" = true ]; then
          echo -e "${GREEN}SSL 검증: 비활성화${NC}"
        else
          echo -e "${GREEN}SSL 검증: 활성화${NC}"
        fi
      else
        echo -e "${GREEN}자동 모드: ws(8080) 또는 wss(8443) 자동 선택${NC}"
        if [ "$NO_SSL_VERIFY" = true ]; then
          echo -e "${GREEN}SSL 검증: 비활성화${NC}"
        else
          echo -e "${GREEN}SSL 검증: 활성화${NC}"
        fi
      fi
      ;;
    "local")
      echo -e "${GREEN}로컬 모드: WebSocket 서버 연결 없음${NC}"
      ;;
  esac
  
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
    if [ -z "$WS_SERVER_HOST" ] && [ "$WS_MODE" != "local" ] && [ "$WS_MODE" != "custom" ]; then
      WS_SERVER_HOST=$(detect_external_ip)
    fi
  fi
  
  # 필요한 파일 다운로드
  download_mclient_files
  
  # Dockerfile 생성
  create_dockerfile
  
  # 환경 변수 파일 업데이트
  update_env_file
  
  # docker-compose.yml 파일 업데이트
  update_docker_compose
  
  # 셸 함수 설정
  setup_shell_functions
  
  echo -e "${BLUE}===================================================${NC}"
  echo -e "${GREEN}Creditcoin 모니터링 클라이언트 설정이 완료되었습니다!${NC}"
  
  # 컨테이너 시작 여부 확인
  read -p "모니터링 클라이언트를 지금 시작하시겠습니까? (Y/n): " start_now
  if [[ -z "$start_now" || "$start_now" =~ ^[Yy]$ ]]; then
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
      echo -e "${YELLOW}또는 셸 함수 사용: ${GREEN}mclient-logs${NC}"
    else
      echo -e "${RED}모니터링 클라이언트 시작에 실패했습니다.${NC}"
      echo -e "${YELLOW}로그를 확인하여 문제를 진단하세요.${NC}"
    fi
  else
    echo -e "${YELLOW}모니터링 클라이언트를 시작하지 않았습니다.${NC}"
    echo -e "${YELLOW}나중에 다음 명령어로 시작할 수 있습니다:${NC}"
    echo -e "${GREEN}docker compose -p creditcoin3 up -d mclient${NC}"
    echo -e "${YELLOW}또는 셸 함수 사용: ${GREEN}mclient-start${NC}"
  fi
  
  echo -e "${BLUE}===================================================${NC}"
  echo -e "${YELLOW}사용 가능한 셸 함수:${NC}"
  echo -e "${GREEN}mclient-start${NC}    - 모니터링 클라이언트 시작"
  echo -e "${GREEN}mclient-stop${NC}     - 모니터링 클라이언트 중지"
  echo -e "${GREEN}mclient-restart${NC}  - 모니터링 클라이언트 재시작"
  echo -e "${GREEN}mclient-logs${NC}     - 모니터링 클라이언트 로그 표시"
  echo -e "${GREEN}mclient-status${NC}   - 모니터링 클라이언트 상태 확인"
  echo -e "${GREEN}mclient-local${NC}    - 로컬 모드로 모니터링 클라이언트 실행"
  echo -e "${BLUE}===================================================${NC}"
}

# 스크립트 실행
main "$@"