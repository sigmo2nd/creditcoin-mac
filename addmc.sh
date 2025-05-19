#!/bin/bash
# addmc.sh - Creditcoin 모니터링 클라이언트 추가 스크립트 (개선 버전)

# .zshrc에서 환경변수 로드
if [ -f "$HOME/.zshrc" ]; then
  source "$HOME/.zshrc" 2>/dev/null || true
fi

# 디버그: 환경변수 확인
echo "환경변수 디버그:"
echo "HOST_PROCESSOR = $HOST_PROCESSOR"
echo "HOST_MODEL = $HOST_MODEL"
echo "HOST_CPU_CORES = $HOST_CPU_CORES"
echo "HOST_MAC_ADDRESS = $HOST_MAC_ADDRESS"
echo "HOST_DISK_TOTAL_GB = $HOST_DISK_TOTAL_GB"

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 기본값 설정
SERVER_ID=""  # 환경 변수에서 로드
MONITOR_INTERVAL="1"  # 기본 간격 1초
WS_MODE="auto"  # 기본값을 auto
WS_SERVER_URL=""
WS_SERVER_HOST=""
NO_SSL_VERIFY=false
CREDITCOIN_DIR=$(pwd)
FORCE=true  # 기본적으로 설정 덮어쓰기
NON_INTERACTIVE=false

# Docker 명령어 및 환경 확인
check_docker_env() {
  echo -e "${BLUE}Docker 환경 확인 중...${NC}" >&2
  
  # Docker 실행 상태만 확인 (환경변수와 PATH는 이미 setup.sh에서 설정됨)
  if ! docker info &> /dev/null; then
    echo -e "${YELLOW}Docker 엔진(OrbStack)이 실행 중이 아닙니다. 시작을 시도합니다...${NC}" >&2
    # OrbStack 시작 시도
    if command -v orb &> /dev/null; then
      orb start
      sleep 5 # 초기화 시간 부여
      
      # 다시 확인
      if ! docker info &> /dev/null; then
        echo -e "${RED}오류: Docker 엔진(OrbStack)을 시작할 수 없습니다.${NC}" >&2
        echo -e "${YELLOW}OrbStack을 수동으로 실행한 후 다시 시도하세요.${NC}" >&2
        exit 1
      fi
    else
      echo -e "${RED}오류: Docker 엔진(OrbStack)이 실행 중이 아닙니다.${NC}" >&2
      echo -e "${YELLOW}OrbStack을 실행한 후 다시 시도하세요.${NC}" >&2
      exit 1
    fi
  fi
  
  echo -e "${GREEN}Docker 환경 확인 완료.${NC}" >&2
}

# MAC 주소 가져오기 - 환경 변수 사용
get_server_id() {
  echo -e "${BLUE}서버 ID 설정 중...${NC}" >&2
  
  # HOST_MAC_ADDRESS 환경 변수에서 가져오기
  local mac_address="$HOST_MAC_ADDRESS"
  
  # 환경 변수가 없으면 시스템에서 직접 추출
  if [ -z "$mac_address" ]; then
    echo -e "${YELLOW}환경 변수에서 MAC 주소를 찾을 수 없습니다. 시스템에서 직접 추출합니다.${NC}" >&2
    
    # en0 인터페이스에서 MAC 주소 직접 추출
    mac_address=$(ifconfig en0 2>/dev/null | grep ether | awk '{print $2}' | tr -d ':' | tr '[:lower:]' '[:upper:]')
    
    # en0에서 찾지 못한 경우 다른 인터페이스 시도
    if [ -z "$mac_address" ]; then
      mac_address=$(ifconfig 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1 | tr -d ':' | tr '[:lower:]' '[:upper:]')
    fi
    
    # 그래도 찾지 못하면 기본값 사용
    if [ -z "$mac_address" ]; then
      mac_address="server1"
      echo -e "${YELLOW}MAC 주소를 찾을 수 없습니다. 기본값(${mac_address})을 사용합니다.${NC}" >&2
    else
      echo -e "${GREEN}시스템에서 MAC 주소(${mac_address})를 추출했습니다.${NC}" >&2
    fi
  else
    echo -e "${GREEN}환경 변수에서 MAC 주소(${mac_address})를 로드했습니다.${NC}" >&2
  fi
  
  echo "$mac_address"
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

# 외부 IP 주소 감지
detect_external_ip() {
  echo -e "${BLUE}외부 IP 주소 감지 중...${NC}" >&2
  
  # 여러 서비스를 시도하여 외부 IP 주소 찾기
  local external_ip=""
  external_ip=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || curl -s https://icanhazip.com)
  
  if [ -n "$external_ip" ]; then
    echo -e "${GREEN}외부 IP 주소: $external_ip${NC}" >&2
    echo "$external_ip"
    return
  fi
  
  # 외부 IP를 찾지 못하면 로컬 네트워크 IP 시도
  echo -e "${YELLOW}외부 IP 주소를 찾을 수 없습니다. 로컬 네트워크 IP 감지를 시도합니다.${NC}" >&2
  
  # 다양한 플랫폼에서 작동하는 IP 감지 방법
  if command -v ifconfig &> /dev/null; then
    local local_ip=""
    # Linux/macOS
    local_ip=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | sed 's/addr://')
    if [ -n "$local_ip" ]; then
      echo -e "${GREEN}로컬 네트워크 IP: $local_ip${NC}" >&2
      echo "$local_ip"
      return
    fi
  elif command -v ip &> /dev/null; then
    # 새로운 Linux 배포판
    local local_ip=""
    local_ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
    if [ -n "$local_ip" ]; then
      echo -e "${GREEN}로컬 네트워크 IP: $local_ip${NC}" >&2
      echo "$local_ip"
      return
    fi
  fi
  
  echo -e "${YELLOW}IP 주소를 자동으로 감지할 수 없습니다. 기본값 'localhost'를 사용합니다.${NC}" >&2
  echo "localhost"
}

# Docker 소켓 경로 찾기
find_docker_sock_path() {
  echo -e "${BLUE}Docker 소켓 경로 감지 중...${NC}" >&2
  
  # 기본 OrbStack Docker 소켓 경로 (환경변수에 이미 설정됨)
  local docker_sock_path="$HOME/.orbstack/run/docker.sock"
  
  if [ -S "$docker_sock_path" ]; then
    echo -e "${GREEN}Docker 소켓 발견: $docker_sock_path${NC}" >&2
    echo "$docker_sock_path"
    return
  fi
  
  echo -e "${YELLOW}OrbStack Docker 소켓을 찾을 수 없습니다. 다른 경로를 시도합니다...${NC}" >&2
  
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
  
  echo -e "${RED}Docker 소켓을 찾을 수 없습니다. 기본 경로를 사용합니다.${NC}" >&2
  echo "/var/run/docker.sock"
}

# 모니터링 클라이언트 디렉토리 설정 (mclient 직접 사용)
setup_mclient_dir() {
  echo -e "${BLUE}모니터링 클라이언트 디렉토리 설정 중...${NC}" >&2
  
  # mclient 디렉토리가 있는지 확인
  if [ ! -d "./mclient" ]; then
    echo -e "${RED}오류: mclient 디렉토리가 존재하지 않습니다.${NC}" >&2
    echo -e "${YELLOW}Creditcoin 저장소가 올바르게 클론되었는지 확인하세요.${NC}" >&2
    exit 1
  else
    echo -e "${GREEN}mclient 디렉토리를 사용합니다.${NC}" >&2
    
    # 실행 파일에 권한 부여
    if [ -f "./mclient/start.sh" ]; then
      chmod +x "./mclient/start.sh"
      echo -e "${GREEN}start.sh 파일에 실행 권한을 부여했습니다.${NC}" >&2
    fi
    
    if [ -f "./mclient/main.py" ]; then
      chmod +x "./mclient/main.py"
      echo -e "${GREEN}main.py 파일에 실행 권한을 부여했습니다.${NC}" >&2
    fi
  fi
}

# 진입점 스크립트 생성
create_entrypoint_script() {
  echo -e "${BLUE}Docker 진입점 스크립트 생성 중...${NC}" >&2
  
  cat > ./mclient/docker-entrypoint.sh << 'EOF'
#!/bin/bash
echo "== Creditcoin 모니터링 클라이언트 =="
echo "서버 ID: ${SERVER_ID}"
echo "모니터링 노드: ${NODE_NAMES}"
echo "모니터링 간격: ${MONITOR_INTERVAL}초"
echo "WebSocket 모드: ${WS_MODE}"
if [ "${WS_SERVER_HOST}" != "" ]; then echo "WebSocket 호스트: ${WS_SERVER_HOST}"; fi
if [ "${WS_SERVER_URL}" != "" ]; then echo "WebSocket URL: ${WS_SERVER_URL}"; fi
echo "시작 중..."
export PROCFS_PATH=/host/proc
python /app/main.py "$@"
EOF

  chmod +x ./mclient/docker-entrypoint.sh
  echo -e "${GREEN}Docker 진입점 스크립트가 생성되었습니다.${NC}" >&2
}

# 도움말 출력
show_help() {
  echo "사용법: $0 [옵션]"
  echo ""
  echo "옵션:"
  echo "  --non-interactive   대화형 모드 비활성화"
  echo "  --server-id ID      서버 ID 설정 (기본값: MAC 주소)"
  echo "  --interval SEC      모니터링 간격(초) 설정 (기본값: 1)"
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
  echo "  $0 --mode local                    # 로컬 모드 (WebSocket 서버 연결 없음)"
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
        echo -e "${RED}알 수 없는 옵션: $1${NC}" >&2
        show_help
        exit 1
        ;;
    esac
  done
}

# Dockerfile 생성
create_dockerfile() {
  echo -e "${BLUE}Dockerfile 생성 중...${NC}" >&2
  
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
RUN chmod +x /app/docker-entrypoint.sh

# 시작 명령어
ENTRYPOINT ["/app/docker-entrypoint.sh"]

# 헬스체크
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD ps aux | grep python | grep main.py || exit 1
EOF

  echo -e "${GREEN}Dockerfile이 생성되었습니다.${NC}" >&2
}

# .env 파일 업데이트 (mclient_org 디렉토리에 직접 생성)
update_env_file() {
  echo -e "${BLUE}.env 파일 업데이트 중...${NC}" >&2
  
  # mclient/.env 파일 생성
  cat > ./mclient/.env << EOF
# 기존 노드 설정 유지 (있는 경우)
$(grep -E "^P2P_PORT_3NODE|^RPC_PORT_3NODE|^NODE_NAME_3NODE|^TELEMETRY_3NODE|^PRUNING_3NODE" .env 2>/dev/null || true)

# 모니터링 클라이언트 기본 설정
SERVER_ID=${SERVER_ID}
NODE_NAMES=${NODE_NAMES}
MONITOR_INTERVAL=${MONITOR_INTERVAL}

# WebSocket 설정
WS_MODE=${WS_MODE}
EOF

  # WebSocket 모드에 따른 추가 설정
  if [ "$WS_MODE" = "custom" ] && [ ! -z "$WS_SERVER_URL" ]; then
    echo "WS_SERVER_URL=${WS_SERVER_URL}" >> ./mclient_org/.env
  fi
  
  if [ ! -z "$WS_SERVER_HOST" ]; then
    echo "WS_SERVER_HOST=${WS_SERVER_HOST}" >> ./mclient_org/.env
  fi
  
  # SSL 검증 설정
  if [ "$NO_SSL_VERIFY" = true ]; then
    echo "NO_SSL_VERIFY=true" >> ./mclient_org/.env
  fi
  
  # Docker 관련 설정
  echo "WS_PORT_WS=8080" >> ./mclient_org/.env
  echo "WS_PORT_WSS=8443" >> ./mclient_org/.env
  
  # 디렉토리 설정
  echo "CREDITCOIN_DIR=${CREDITCOIN_DIR}" >> ./mclient_org/.env
  
  # 실행 모드 설정 (기본값은 local 모드 아님)
  echo "RUN_MODE=${RUN_MODE:-normal}" >> ./mclient_org/.env
  
  # 디버그 및 기타 설정
  echo "LOCAL_MODE=${LOCAL_MODE:-false}" >> ./mclient_org/.env
  echo "DEBUG_MODE=${DEBUG_MODE:-false}" >> ./mclient_org/.env
  echo "NO_DOCKER=${NO_DOCKER:-false}" >> ./mclient_org/.env
  echo "MAX_RETRIES=${MAX_RETRIES:-10}" >> ./mclient_org/.env
  echo "RETRY_INTERVAL=${RETRY_INTERVAL:-5}" >> ./mclient_org/.env
  
  # 호스트 정보 변수 추가 (환경 변수에서 가져옴)
  echo "HOST_SYSTEM_NAME=\"${HOST_SYSTEM_NAME:-$(hostname)}\"" >> ./mclient_org/.env
  echo "HOST_MODEL=\"${HOST_MODEL:-Unknown}\"" >> ./mclient_org/.env
  echo "HOST_PROCESSOR=\"${HOST_PROCESSOR:-Unknown}\"" >> ./mclient_org/.env
  echo "HOST_CPU_CORES=${HOST_CPU_CORES:-0}" >> ./mclient_org/.env
  echo "HOST_CPU_PERF_CORES=${HOST_CPU_PERF_CORES:-0}" >> ./mclient_org/.env
  echo "HOST_CPU_EFF_CORES=${HOST_CPU_EFF_CORES:-0}" >> ./mclient_org/.env
  echo "HOST_MEMORY_GB=${HOST_MEMORY_GB:-0}" >> ./mclient_org/.env
  echo "HOST_DISK_TOTAL_GB=${HOST_DISK_TOTAL_GB:-0}" >> ./mclient_org/.env
  
  echo -e "${GREEN}.env 파일이 업데이트되었습니다.${NC}" >&2
}

# docker-compose.yml 파일 업데이트
update_docker_compose() {
  echo -e "${BLUE}docker-compose.yml 파일 업데이트 중...${NC}" >&2
  
  # docker-compose.yml 파일 확인
  if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}오류: docker-compose.yml 파일이 없습니다.${NC}" >&2
    echo -e "${YELLOW}먼저 기본 docker-compose.yml 파일을 생성하세요.${NC}" >&2
    exit 1
  fi
  
  # docker-compose.yml 파일 백업
  cp docker-compose.yml docker-compose.yml.bak.$(date +%Y%m%d%H%M%S)
  echo -e "${GREEN}docker-compose.yml 파일이 백업되었습니다.${NC}" >&2
  
  # Docker 소켓 경로 찾기
  DOCKER_SOCK_PATH=$(find_docker_sock_path)
  
  # mclient 서비스가 이미 있는지 확인
  if grep -q "  mclient:" docker-compose.yml; then
    if [ "$FORCE" = "true" ]; then
      echo -e "${YELLOW}mclient 서비스가 이미 존재합니다. 업데이트합니다...${NC}" >&2
      
      # networks 섹션 추출
      NETWORKS_BLOCK=$(sed -n '/^networks:/,$p' docker-compose.yml)
      
      # mclient 서비스 라인 찾기
      mclient_line=$(grep -n "  mclient:" docker-compose.yml | cut -d: -f1)
      
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
        echo -e "${RED}오류: docker-compose.yml 파일 구조를 이해할 수 없습니다.${NC}" >&2
        exit 1
      fi
    else
      echo -e "${YELLOW}mclient 서비스가 이미 존재합니다. FORCE 옵션이 꺼져 있어 업데이트를 건너뜁니다.${NC}" >&2
      return
    fi
  fi
  
  # networks 섹션 위치 찾기
  networks_line=$(grep -n "^networks:" docker-compose.yml | cut -d: -f1)
  
  if [ -n "$networks_line" ]; then
    # mclient 서비스 블록 생성 - 빈줄 없이 깔끔하게 작성
    cat << EOF > mclient_service.tmp
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
      - SERVER_ID=${SERVER_ID}
      - NODE_NAMES=${NODE_NAMES}
      - MONITOR_INTERVAL=${MONITOR_INTERVAL}
      - WS_MODE=${WS_MODE}
EOF

    # WebSocket 모드에 따른 추가 설정
    if [ "$WS_MODE" = "custom" ] && [ ! -z "$WS_SERVER_URL" ]; then
      echo "      - WS_SERVER_URL=${WS_SERVER_URL}" >> mclient_service.tmp
    fi
    
    if [ ! -z "$WS_SERVER_HOST" ]; then
      echo "      - WS_SERVER_HOST=${WS_SERVER_HOST}" >> mclient_service.tmp
    fi
    
    # SSL 검증 설정
    if [ "$NO_SSL_VERIFY" = true ]; then
      echo "      - NO_SSL_VERIFY=true" >> mclient_service.tmp
    fi
    
    # 포트 및 디렉토리 설정
    cat << EOF >> mclient_service.tmp
      - WS_PORT_WS=8080
      - WS_PORT_WSS=8443
      - CREDITCOIN_DIR=/creditcoin-mac
      - RUN_MODE=${RUN_MODE:-normal}
      # Docker 접근을 위한 환경 변수
      - DOCKER_HOST=unix:///var/run/docker.sock
      - DOCKER_API_VERSION=1.41
      # 호스트 시스템 정보 접근을 위한 환경 변수
      - HOST_PROC=/host/proc
      - HOST_SYS=/host/sys
      # 호스트 정보 변수
      - HOST_SYSTEM_NAME=${HOST_SYSTEM_NAME:-$(hostname)}
      - HOST_MODEL=${HOST_MODEL:-Unknown}
      - HOST_PROCESSOR=${HOST_PROCESSOR:-Unknown}
      - HOST_CPU_CORES=${HOST_CPU_CORES:-0}
      - HOST_CPU_PERF_CORES=${HOST_CPU_PERF_CORES:-0}
      - HOST_CPU_EFF_CORES=${HOST_CPU_EFF_CORES:-0}
      - HOST_MEMORY_GB=${HOST_MEMORY_GB:-0}
      - HOST_DISK_TOTAL_GB=${HOST_DISK_TOTAL_GB:-0}
EOF
    
    # networks 섹션 앞에 mclient 서비스 삽입
    head -n $((networks_line-1)) docker-compose.yml > docker-compose.yml.new
    cat mclient_service.tmp >> docker-compose.yml.new
    echo "" >> docker-compose.yml.new  # 한 줄 공백 추가
    tail -n +$((networks_line)) docker-compose.yml >> docker-compose.yml.new
    mv docker-compose.yml.new docker-compose.yml
    rm mclient_service.tmp
    
    echo -e "${GREEN}mclient 서비스가 docker-compose.yml에 추가되었습니다.${NC}" >&2
  else
    echo -e "${RED}오류: docker-compose.yml 파일에서 networks 섹션을 찾을 수 없습니다.${NC}" >&2
    exit 1
  fi
}

# 연결 테스트 함수
test_connection() {
  local ws_host=$1
  local ws_port=$2
  local protocol=$3
  
  echo -e "${BLUE}WebSocket 서버 연결 테스트 중... (${protocol}://${ws_host}:${ws_port})${NC}" >&2
  
  # 먼저 호스트에 ping 테스트
  if ping -c 1 -W 2 "$ws_host" &>/dev/null; then
    echo -e "${GREEN}호스트 ${ws_host}에 접속 가능합니다.${NC}" >&2
  else
    echo -e "${YELLOW}경고: 호스트 ${ws_host}에 ping할 수 없습니다. 방화벽이 활성화되어 있거나 호스트가 다운되었을 수 있습니다.${NC}" >&2
  fi
  
  # 포트 연결 테스트
  if command -v nc &>/dev/null; then
    if nc -z -w 2 "$ws_host" "$ws_port" 2>/dev/null; then
      echo -e "${GREEN}${ws_host}:${ws_port} 포트에 접속 가능합니다.${NC}" >&2
      return 0
    else
      echo -e "${YELLOW}경고: ${ws_host}:${ws_port} 포트에 접속할 수 없습니다. 방화벽이 차단하거나 해당 포트에 서비스가 실행되지 않을 수 있습니다.${NC}" >&2
    fi
  elif command -v telnet &>/dev/null; then
    if echo -n | telnet "$ws_host" "$ws_port" 2>/dev/null >/dev/null; then
      echo -e "${GREEN}${ws_host}:${ws_port} 포트에 접속 가능합니다.${NC}" >&2
      return 0
    else
      echo -e "${YELLOW}경고: ${ws_host}:${ws_port} 포트에 접속할 수 없습니다. 방화벽이 차단하거나 해당 포트에 서비스가 실행되지 않을 수 있습니다.${NC}" >&2
    fi
  else
    echo -e "${YELLOW}경고: 포트 연결을 테스트할 도구(nc 또는 telnet)가 없습니다.${NC}" >&2
  fi
  
  return 1
}

# 대화형 모드 실행
run_interactive_mode() {
  echo -e "${BLUE}=== Creditcoin 모니터링 클라이언트 설정 ====${NC}" >&2
  
  # 노드 자동 감지
  NODE_NAMES=$(detect_nodes)
  
  # 안내 메시지 추가
  echo -e "${YELLOW}엔터를 입력하면 괄호안에 기본값이 입력됩니다.${NC}" >&2
  
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
  
  # 연결 모드 선택
  echo -e "${YELLOW}연결 모드를 선택하세요:${NC}" >&2
  echo "1) 자동 모드 (auto) - 자동으로 적절한 연결 방식 선택" >&2
  echo "2) 사용자 지정 URL (custom) - WebSocket URL 직접 지정" >&2
  echo "3) WS 프로토콜 (ws) - 암호화되지 않은 WebSocket 사용" >&2
  echo "4) WSS 프로토콜 (wss) - 암호화된 WebSocket 사용" >&2
  echo "5) 로컬 모드 (local) - WebSocket 서버 연결 없이 실행" >&2
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
      read -p "WebSocket 서버 호스트를 입력하세요 ($default_host): " input
      WS_SERVER_HOST=${input:-$default_host}
      
      # 연결 테스트
      test_connection "$WS_SERVER_HOST" "8080" "ws"
      ;;
    4)
      WS_MODE="wss"
      # 외부 IP 주소 감지
      default_host=$(detect_external_ip)
      read -p "WebSocket 서버 호스트를 입력하세요 ($default_host): " input
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
      echo -e "${GREEN}로컬 모드가 선택되었습니다. WebSocket 서버 연결 없이 실행됩니다.${NC}" >&2
      ;;
    *)
      WS_MODE="auto"
      # 외부 IP 주소 감지
      default_host=$(detect_external_ip)
      read -p "WebSocket 서버 호스트를 입력하세요 ($default_host): " input
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
  echo -e "${BLUE}\n=== 설정 요약 ===${NC}" >&2
  echo -e "${GREEN}서버 ID: $SERVER_ID${NC}" >&2
  echo -e "${GREEN}모니터링 노드: $NODE_NAMES${NC}" >&2
  echo -e "${GREEN}모니터링 간격: ${MONITOR_INTERVAL}초${NC}" >&2
  echo -e "${GREEN}연결 모드: $WS_MODE${NC}" >&2
  
  case $WS_MODE in
    "custom")
      echo -e "${GREEN}WebSocket URL: $WS_SERVER_URL${NC}" >&2
      if [ "$NO_SSL_VERIFY" = true ]; then
        echo -e "${GREEN}SSL 검증: 비활성화${NC}" >&2
      else
        echo -e "${GREEN}SSL 검증: 활성화${NC}" >&2
      fi
      ;;
    "ws")
      echo -e "${GREEN}WebSocket 호스트: $WS_SERVER_HOST${NC}" >&2
      echo -e "${GREEN}WebSocket 포트: 8080${NC}" >&2
      ;;
    "wss")
      echo -e "${GREEN}WebSocket 호스트: $WS_SERVER_HOST${NC}" >&2
      echo -e "${GREEN}WebSocket 포트: 8443${NC}" >&2
      if [ "$NO_SSL_VERIFY" = true ]; then
        echo -e "${GREEN}SSL 검증: 비활성화${NC}" >&2
      else
        echo -e "${GREEN}SSL 검증: 활성화${NC}" >&2
      fi
      ;;
    "auto")
      echo -e "${GREEN}WebSocket 호스트: $WS_SERVER_HOST${NC}" >&2
      echo -e "${GREEN}자동 모드: ws(8080) 또는 wss(8443) 자동 선택${NC}" >&2
      if [ "$NO_SSL_VERIFY" = true ]; then
        echo -e "${GREEN}SSL 검증: 비활성화${NC}" >&2
      else
        echo -e "${GREEN}SSL 검증: 활성화${NC}" >&2
      fi
      ;;
    "local")
      echo -e "${GREEN}로컬 모드: WebSocket 서버 연결 없음${NC}" >&2
      ;;
  esac
  
  # 확인 및 진행
  read -p "위 설정으로 진행하시겠습니까? (Y/n): " confirm
  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo -e "${RED}설치가 취소되었습니다.${NC}" >&2
    exit 0
  fi
}

# 메인 실행 함수
main() {
  # Docker 환경 확인
  check_docker_env
  
  # 명령줄 인자 처리
  parse_args "$@"
  
  # MAC 주소/서버 ID 설정
  if [ -z "$SERVER_ID" ]; then
    SERVER_ID=$(get_server_id)
  fi
  
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
  
  # mclient_org 디렉토리 설정
  setup_mclient_dir
  
  # 진입점 스크립트 생성
  create_entrypoint_script
  
  # Dockerfile 생성
  create_dockerfile
  
  # 환경 변수 파일 업데이트
  update_env_file
  
  # docker-compose.yml 파일 업데이트
  update_docker_compose
  
  echo -e "${BLUE}===================================================${NC}" >&2
  echo -e "${GREEN}Creditcoin 모니터링 클라이언트 설정이 완료되었습니다!${NC}" >&2
  
  # 컨테이너 시작 여부 확인
  read -p "모니터링 클라이언트를 지금 시작하시겠습니까? (Y/n): " start_now
  if [[ -z "$start_now" || "$start_now" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}이전 mclient 컨테이너 확인 및 제거 중...${NC}" >&2
    # 기존 mclient 컨테이너 제거
    if docker ps -a --format "{{.Names}}" | grep -q "mclient$"; then
      echo -e "${YELLOW}기존 mclient 컨테이너가 발견되었습니다. 제거합니다...${NC}" >&2
      docker stop mclient 2>/dev/null || true
      docker rm mclient 2>/dev/null || true
      echo -e "${GREEN}기존 컨테이너가 제거되었습니다.${NC}" >&2
    fi
    
    echo -e "${BLUE}모니터링 클라이언트를 시작합니다...${NC}" >&2
    docker compose -p creditcoin3 up -d mclient
    
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}모니터링 클라이언트가 성공적으로 시작되었습니다.${NC}" >&2
      echo -e "${YELLOW}로그 확인: ${GREEN}docker compose -p creditcoin3 logs -f mclient${NC}" >&2
      echo -e "${YELLOW}또는 셸 함수 사용: ${GREEN}mlog${NC}" >&2
    else
      echo -e "${RED}모니터링 클라이언트 시작에 실패했습니다.${NC}" >&2
      echo -e "${YELLOW}로그를 확인하여 문제를 진단하세요.${NC}" >&2
    fi
  else
    echo -e "${YELLOW}모니터링 클라이언트를 시작하지 않았습니다.${NC}" >&2
    echo -e "${YELLOW}나중에 다음 명령어로 시작할 수 있습니다:${NC}" >&2
    echo -e "${GREEN}docker compose -p creditcoin3 up -d mclient${NC}" >&2
    echo -e "${YELLOW}또는 셸 함수 사용: ${GREEN}mstart${NC}" >&2
  fi
  
  echo -e "${BLUE}===================================================${NC}" >&2
  echo -e "${YELLOW}사용 가능한 명령어:${NC}" >&2
  echo -e "${GREEN}mstart${NC}     - 모니터링 클라이언트 시작" >&2
  echo -e "${GREEN}mstop${NC}      - 모니터링 클라이언트 중지" >&2
  echo -e "${GREEN}mrestart${NC}   - 모니터링 클라이언트 재시작" >&2
  echo -e "${GREEN}mlog${NC}       - 모니터링 클라이언트 로그 표시" >&2
  echo -e "${GREEN}mstatus${NC}    - 모니터링 클라이언트 상태 확인" >&2
  echo -e "${GREEN}mlocal${NC}     - 로컬 모드로 모니터링 클라이언트 실행" >&2
  echo -e "${GREEN}cleanupbak${NC}  - 백업 파일 정리" >&2
  echo -e "${BLUE}===================================================${NC}" >&2
}

# 스크립트 실행
main "$@"