#!/bin/bash
# addmc.sh - Creditcoin 모니터링 클라이언트 추가 스크립트 (단순화 버전)

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 기본 설정
MCLIENT_VERSION="1.0.0"  # mclient 기본 버전
AUTO_AUTH=false
AUTH_USER=""
AUTH_PASS=""
CUSTOM_VERSION=""

# 실행 중인 Docker 노드 자동 감지
detect_nodes() {
  echo -e "${BLUE}실행 중인 Creditcoin 노드 감지 중...${NC}" >&2
  
  # Docker 컨테이너 목록에서 node 또는 3node로 시작하는 컨테이너 찾기
  local nodes=""
  nodes=$(docker ps --format "{{.Names}}" | grep -E '^(node|3node)' | tr '\n' ',' | sed 's/,$//')
  
  if [ -z "$nodes" ]; then
    echo -e "${YELLOW}실행 중인 Creditcoin 노드를 찾을 수 없습니다. 기본값을 사용합니다.${NC}" >&2
    echo "3node0"
    return
  fi
  
  echo -e "${GREEN}감지된 노드: $nodes${NC}" >&2
  echo "$nodes"
}

# MAC 주소 기반 서버 ID 생성
get_server_id() {
  echo -e "${BLUE}서버 ID 생성 중...${NC}" >&2
  
  # MAC 주소 가져오기
  local mac_address=""
  
  # en0 인터페이스에서 MAC 주소 추출
  mac_address=$(ifconfig en0 2>/dev/null | grep ether | awk '{print $2}' | tr -d ':' | tr '[:lower:]' '[:upper:]')
  
  # en0에서 찾지 못한 경우 다른 인터페이스 시도
  if [ -z "$mac_address" ]; then
    mac_address=$(ifconfig 2>/dev/null | grep -o -E '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n 1 | tr -d ':' | tr '[:lower:]' '[:upper:]')
  fi
  
  # 그래도 찾지 못하면 기본값 사용
  if [ -z "$mac_address" ]; then
    mac_address="DEFAULT$(date +%s)"
    echo -e "${YELLOW}MAC 주소를 찾을 수 없습니다. 타임스탬프 기반 ID를 사용합니다: ${mac_address}${NC}" >&2
  else
    echo -e "${GREEN}MAC 주소 기반 서버 ID: ${mac_address}${NC}" >&2
  fi
  
  echo "$mac_address"
}

# 시스템 정보 수집
collect_system_info() {
  echo -e "${BLUE}시스템 정보 수집 중...${NC}"
  
  # 호스트명
  HOST_SYSTEM_NAME=$(hostname)
  
  # macOS 시스템 정보
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # 모델 정보
    HOST_MODEL=$(sysctl -n hw.model 2>/dev/null || echo "Unknown Mac")
    
    # 프로세서 정보
    if [[ $(uname -m) == "arm64" ]]; then
      # Apple Silicon
      HOST_PROCESSOR=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Chip" | awk -F': ' '{print $2}' || echo "Apple Silicon")
    else
      # Intel Mac
      HOST_PROCESSOR=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Intel")
    fi
    
    # CPU 코어 정보
    HOST_CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo "0")
    
    # Apple Silicon의 경우 성능/효율 코어 구분
    if [[ $(uname -m) == "arm64" ]]; then
      HOST_CPU_PERF_CORES=$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || echo "$HOST_CPU_CORES")
      HOST_CPU_EFF_CORES=$(sysctl -n hw.perflevel1.logicalcpu 2>/dev/null || echo "0")
    else
      HOST_CPU_PERF_CORES=$HOST_CPU_CORES
      HOST_CPU_EFF_CORES=0
    fi
    
    # 메모리 정보 (GB)
    local mem_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
    HOST_MEMORY_GB=$((mem_bytes / 1024 / 1024 / 1024))
    
    # 디스크 정보 (GB)
    local disk_info=$(df -h / | tail -1 | awk '{print $2}')
    # G 또는 T 단위 처리
    if [[ $disk_info == *"T"* ]]; then
      HOST_DISK_TOTAL_GB=$(echo $disk_info | sed 's/T//' | awk '{print int($1 * 1024)}')
    elif [[ $disk_info == *"G"* ]]; then
      HOST_DISK_TOTAL_GB=$(echo $disk_info | sed 's/G//' | awk '{print int($1)}')
    else
      HOST_DISK_TOTAL_GB=0
    fi
  else
    # Linux 또는 기타 시스템
    HOST_MODEL=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "Unknown")
    HOST_PROCESSOR=$(cat /proc/cpuinfo | grep "model name" | head -1 | awk -F': ' '{print $2}' || echo "Unknown")
    HOST_CPU_CORES=$(nproc 2>/dev/null || echo "0")
    HOST_CPU_PERF_CORES=$HOST_CPU_CORES
    HOST_CPU_EFF_CORES=0
    HOST_MEMORY_GB=$(free -g | grep Mem | awk '{print $2}')
    HOST_DISK_TOTAL_GB=$(df -BG / | tail -1 | awk '{print $2}' | sed 's/G//')
  fi
  
  echo -e "${GREEN}시스템 정보 수집 완료:${NC}"
  echo -e "  호스트명: $HOST_SYSTEM_NAME"
  echo -e "  모델: $HOST_MODEL"
  echo -e "  프로세서: $HOST_PROCESSOR"
  echo -e "  CPU 코어: $HOST_CPU_CORES (성능: $HOST_CPU_PERF_CORES, 효율: $HOST_CPU_EFF_CORES)"
  echo -e "  메모리: ${HOST_MEMORY_GB}GB"
  echo -e "  디스크: ${HOST_DISK_TOTAL_GB}GB"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -y|--yes|--auto-auth)
      AUTO_AUTH=true
      shift
      ;;
    -u|--user)
      AUTH_USER="$2"
      shift 2
      ;;
    -p|--pass)
      AUTH_PASS="$2"
      shift 2
      ;;
    -v|--version)
      CUSTOM_VERSION="$2"
      shift 2
      ;;
    --user=*)
      AUTH_USER="${1#*=}"
      shift
      ;;
    --pass=*)
      AUTH_PASS="${1#*=}"
      shift
      ;;
    --version=*)
      CUSTOM_VERSION="${1#*=}"
      shift
      ;;
    -h|--help)
      echo "사용법: $0 [옵션]"
      echo "옵션:"
      echo "  -y, --yes, --auto-auth     자동 인증 모드 (대화형 입력 요청)"
      echo "  -u, --user <username>      인증 사용자명"
      echo "  -p, --pass <password>      인증 패스워드"
      echo "  -v, --version <version>    mclient 버전 지정 (기본값: ${MCLIENT_VERSION})"
      echo "  -h, --help                 도움말 표시"
      echo ""
      echo "예시:"
      echo "  $0                         # 기본 버전으로 mclient 생성"
      echo "  $0 -y                      # 대화형으로 인증 정보 입력"
      echo "  $0 -u admin -p password    # 인증 정보를 직접 지정"
      echo "  $0 -v 1.1.0                # 특정 버전으로 생성"
      exit 0
      ;;
    *)
      echo -e "${RED}알 수 없는 옵션: $1${NC}"
      echo "도움말을 보려면: $0 --help"
      exit 1
      ;;
  esac
done

# 버전 설정
MCLIENT_VERSION="${CUSTOM_VERSION:-$MCLIENT_VERSION}"
IMAGE_NAME="mclient:${MCLIENT_VERSION}"

echo -e "${BLUE}=====================================================${NC}"
echo -e "${GREEN}     Creditcoin 모니터링 클라이언트 추가 도구${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo ""
echo -e "${BLUE}사용할 설정:${NC}"
echo -e "${GREEN}- mclient 버전: ${MCLIENT_VERSION}${NC}"
echo -e "${GREEN}- 이미지 이름: ${IMAGE_NAME}${NC}"
echo ""

# mclient가 이미 실행 중인지 확인
if docker ps | grep -q "mclient"; then
  echo -e "${YELLOW}mclient가 이미 실행 중입니다.${NC}"
  echo -e "${YELLOW}기존 mclient를 중지하고 다시 시작하시겠습니까? (y/N)${NC}"
  read -r response
  if [[ "$response" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}기존 mclient 중지 중...${NC}"
    # docker-compose로 시작된 mclient 중지
    docker compose -f docker-compose-mclient.yml down 2>/dev/null || true
    # 이름에 mclient가 포함된 모든 컨테이너 중지 및 제거
    for container in $(docker ps -a | grep "mclient" | awk '{print $1}'); do
      docker stop "$container" 2>/dev/null || true
      docker rm "$container" 2>/dev/null || true
    done
    echo -e "${GREEN}모든 mclient 컨테이너가 중지되었습니다.${NC}"
  else
    echo -e "${GREEN}작업을 취소합니다.${NC}"
    exit 0
  fi
fi

# 시스템 정보를 먼저 수집
collect_system_info

# 서버 ID 생성
SERVER_ID=$(get_server_id)

# 노드 자동 감지
NODE_NAMES=$(detect_nodes)

# 환경변수 생성/업데이트 함수
update_env_file() {
  local env_file=".env.mclient"
  
  echo -e "${BLUE}$env_file 파일을 생성/업데이트합니다...${NC}"
  
  # 전체 파일을 다시 작성
  cat > "$env_file" << EOF
# mclient 모니터링 설정
SERVER_ID=${SERVER_ID}
NODE_NAMES=${NODE_NAMES}
MONITOR_INTERVAL=${MONITOR_INTERVAL}

# WebSocket 설정
WS_MODE=${WS_MODE}
WS_SERVER_HOST=${WS_SERVER_HOST}
WS_SERVER_PORT=${WS_SERVER_PORT}

# 경로 설정
CREDITCOIN_DIR=${PWD}

# 인증 설정
REQUIRE_AUTH=${REQUIRE_AUTH}
AUTH_ALLOW_HTTP=${AUTH_ALLOW_HTTP}
AUTH_API_URL=$([[ "$WS_MODE" == "wss" ]] && echo "https" || echo "http")://${WS_SERVER_HOST}:${WS_SERVER_PORT}/api/auth

# SSL 설정
SSL_VERIFY=${SSL_VERIFY}

# 호스트 정보 변수
HOST_SYSTEM_NAME=${HOST_SYSTEM_NAME}
HOST_MODEL=${HOST_MODEL}
HOST_PROCESSOR=${HOST_PROCESSOR}
HOST_CPU_CORES=${HOST_CPU_CORES}
HOST_CPU_PERF_CORES=${HOST_CPU_PERF_CORES}
HOST_CPU_EFF_CORES=${HOST_CPU_EFF_CORES}
HOST_MEMORY_GB=${HOST_MEMORY_GB}
HOST_DISK_TOTAL_GB=${HOST_DISK_TOTAL_GB}

# 추가 설정
MAX_RETRIES=${MAX_RETRIES}
RETRY_INTERVAL=${RETRY_INTERVAL}
DEBUG_MODE=${DEBUG_MODE}
RUN_MODE=${RUN_MODE}
NO_DOCKER=${NO_DOCKER}

# mclient 버전
MCLIENT_VERSION=${MCLIENT_VERSION}
EOF

  echo -e "${GREEN}$env_file 파일이 생성/업데이트되었습니다.${NC}"
  echo -e "${GREEN}감지된 노드: ${NODE_NAMES}${NC}"
  echo -e "${GREEN}서버 ID: ${SERVER_ID}${NC}"
}

# 대화형 설정 함수
interactive_setup() {
  echo -e "${BLUE}=====================================================${NC}"
  echo -e "${GREEN}     모니터링 클라이언트 대화형 설정${NC}"
  echo -e "${BLUE}=====================================================${NC}"
  echo ""
  
  # 1단계: 프로토콜 선택
  echo -e "${YELLOW}[1단계] 모니터링 서버 연결 방식을 선택하세요:${NC}"
  echo "1) WS (일반 WebSocket)"
  echo "2) WSS (보안 WebSocket)"
  echo ""
  read -p "선택 (1): " protocol_choice
  
  # 엔터만 누르면 기본값 선택
  if [ -z "$protocol_choice" ]; then
    protocol_choice="1"
  fi
  
  case $protocol_choice in
    2)
      WS_PROTOCOL="wss"
      WS_MODE="wss"
      echo -e "${GREEN}WSS (보안 WebSocket)가 선택되었습니다.${NC}"
      
      # SSL 검증 옵션 (WSS 선택시만)
      echo ""
      echo -e "${YELLOW}[1-1단계] SSL 인증서 검증을 수행하시겠습니까?${NC}"
      echo "1) 예 (프로덕션 환경 권장)"
      echo "2) 아니오 (개발/테스트 환경)"
      echo ""
      read -p "선택 (2): " ssl_choice
      
      if [ -z "$ssl_choice" ]; then
        ssl_choice="2"
      fi
      
      case $ssl_choice in
        1)
          SSL_VERIFY="true"
          echo -e "${GREEN}SSL 인증서 검증이 활성화됩니다.${NC}"
          ;;
        2)
          SSL_VERIFY="false"
          echo -e "${YELLOW}SSL 인증서 검증이 비활성화됩니다.${NC}"
          ;;
        *)
          echo -e "${YELLOW}잘못된 선택입니다. 기본값(검증 활성화)을 사용합니다.${NC}"
          SSL_VERIFY="true"
          ;;
      esac
      ;;
    1)
      WS_PROTOCOL="ws"
      WS_MODE="ws"
      SSL_VERIFY="false"
      echo -e "${GREEN}WS (일반 WebSocket)가 선택되었습니다.${NC}"
      ;;
    *)
      echo -e "${YELLOW}잘못된 선택입니다. 기본값(WS)을 사용합니다.${NC}"
      WS_PROTOCOL="ws"
      WS_MODE="ws"
      SSL_VERIFY="false"
      ;;
  esac
  
  # 2단계: 서버 주소 선택
  echo ""
  echo -e "${YELLOW}[2단계] 모니터링 서버 주소를 선택하세요:${NC}"
  echo "1) creditcoin.info (공식 서버)"
  echo "2) 외부 IP (퍼블릭 IP)"
  echo "3) 내부 IP (로컬 네트워크)"
  echo "4) localhost (로컬 테스트)"
  echo "5) 커스텀 (직접 입력)"
  echo ""
  read -p "선택 (2): " host_choice
  
  if [ -z "$host_choice" ]; then
    host_choice="2"
  fi
  
  case $host_choice in
    1)
      WS_SERVER_HOST="creditcoin.info"
      echo -e "${GREEN}공식 서버(creditcoin.info)가 선택되었습니다.${NC}"
      ;;
    2)
      # 외부 IP 자동 감지
      echo -e "${BLUE}외부 IP를 감지하는 중...${NC}"
      EXTERNAL_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || curl -s https://icanhazip.com)
      if [ -n "$EXTERNAL_IP" ]; then
        WS_SERVER_HOST="$EXTERNAL_IP"
        echo -e "${GREEN}외부 IP($EXTERNAL_IP)가 선택되었습니다.${NC}"
      else
        echo -e "${RED}외부 IP를 감지할 수 없습니다. 직접 입력해주세요.${NC}"
        read -p "외부 IP 주소: " WS_SERVER_HOST
      fi
      ;;
    3)
      # 내부 IP 자동 감지
      echo -e "${BLUE}내부 IP를 감지하는 중...${NC}"
      INTERNAL_IP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1)
      if [ -n "$INTERNAL_IP" ]; then
        WS_SERVER_HOST="$INTERNAL_IP"
        echo -e "${GREEN}내부 IP($INTERNAL_IP)가 선택되었습니다.${NC}"
      else
        echo -e "${RED}내부 IP를 감지할 수 없습니다. 직접 입력해주세요.${NC}"
        read -p "내부 IP 주소: " WS_SERVER_HOST
      fi
      ;;
    4)
      WS_SERVER_HOST="localhost"
      echo -e "${GREEN}localhost가 선택되었습니다.${NC}"
      ;;
    5)
      read -p "서버 주소를 입력하세요: " WS_SERVER_HOST
      echo -e "${GREEN}커스텀 주소($WS_SERVER_HOST)가 선택되었습니다.${NC}"
      ;;
    *)
      echo -e "${YELLOW}잘못된 선택입니다. 기본값(외부 IP)을 사용합니다.${NC}"
      # 외부 IP 자동 감지
      EXTERNAL_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || curl -s https://icanhazip.com)
      if [ -n "$EXTERNAL_IP" ]; then
        WS_SERVER_HOST="$EXTERNAL_IP"
      else
        WS_SERVER_HOST="localhost"
      fi
      ;;
  esac
  
  # 3단계: 모니터링 간격 설정
  echo ""
  echo -e "${YELLOW}[3단계] 모니터링 데이터 수집 간격을 설정하세요:${NC}"
  echo -e "${GREEN}권장: 5초, 기본값: 1초${NC}"
  echo ""
  read -p "간격(초)을 입력하세요 (1): " MONITOR_INTERVAL
  
  # 엔터만 누르면 기본값 사용
  if [ -z "$MONITOR_INTERVAL" ]; then
    MONITOR_INTERVAL="1"
  fi
  
  # 숫자인지 확인
  if ! [[ "$MONITOR_INTERVAL" =~ ^[0-9]+$ ]] || [ "$MONITOR_INTERVAL" -lt 1 ]; then
    echo -e "${YELLOW}잘못된 입력입니다. 기본값(1초)을 사용합니다.${NC}"
    MONITOR_INTERVAL="1"
  fi
  
  echo -e "${GREEN}${MONITOR_INTERVAL}초 간격이 선택되었습니다.${NC}"
  
  # 4단계: 포트 선택
  echo ""
  if [ "$WS_PROTOCOL" = "wss" ]; then
    echo -e "${YELLOW}[4단계] WSS 포트를 입력하세요:${NC}"
    read -p "포트 번호 (4443): " WS_SERVER_PORT
    
    # 엔터만 누르면 기본값 사용
    if [ -z "$WS_SERVER_PORT" ]; then
      WS_SERVER_PORT="4443"
    fi
    
    # 숫자인지 확인
    if ! [[ "$WS_SERVER_PORT" =~ ^[0-9]+$ ]] || [ "$WS_SERVER_PORT" -lt 1 ] || [ "$WS_SERVER_PORT" -gt 65535 ]; then
      echo -e "${YELLOW}잘못된 포트 번호입니다. 기본값(4443)을 사용합니다.${NC}"
      WS_SERVER_PORT="4443"
    fi
    
    echo -e "${GREEN}포트 ${WS_SERVER_PORT}가 선택되었습니다.${NC}"
  else
    echo -e "${YELLOW}[4단계] WS 포트를 입력하세요:${NC}"
    read -p "포트 번호 (8080): " WS_SERVER_PORT
    
    # 엔터만 누르면 기본값 사용
    if [ -z "$WS_SERVER_PORT" ]; then
      WS_SERVER_PORT="8080"
    fi
    
    # 숫자인지 확인
    if ! [[ "$WS_SERVER_PORT" =~ ^[0-9]+$ ]] || [ "$WS_SERVER_PORT" -lt 1 ] || [ "$WS_SERVER_PORT" -gt 65535 ]; then
      echo -e "${YELLOW}잘못된 포트 번호입니다. 기본값(8080)을 사용합니다.${NC}"
      WS_SERVER_PORT="8080"
    fi
    
    echo -e "${GREEN}포트 ${WS_SERVER_PORT}가 선택되었습니다.${NC}"
  fi
  
  # 5단계: 디버그 모드 설정
  echo ""
  echo -e "${YELLOW}[5단계] 디버그 모드를 활성화하시겠습니까?${NC}"
  echo "1) 아니오 (일반 모드)"
  echo "2) 예 (상세 로그 출력)"
  echo ""
  read -p "선택 (2): " debug_choice
  
  if [ -z "$debug_choice" ]; then
    debug_choice="2"
  fi
  
  case $debug_choice in
    1)
      DEBUG_MODE="false"
      echo -e "${GREEN}일반 모드가 선택되었습니다.${NC}"
      ;;
    2)
      DEBUG_MODE="true"
      echo -e "${GREEN}디버그 모드가 활성화됩니다.${NC}"
      ;;
    *)
      echo -e "${YELLOW}잘못된 선택입니다. 기본값(디버그 모드)을 사용합니다.${NC}"
      DEBUG_MODE="true"
      ;;
  esac
  
  # 6단계: 인증 필요 여부 (정보 제공만)
  echo ""
  echo -e "${YELLOW}[6단계] 인증 설정${NC}"
  echo -e "${GREEN}모니터링 서버에 인증이 필요한 경우, mclient 실행 시 자동으로 로그인 화면이 표시됩니다.${NC}"
  echo ""
  
  # 설정 요약
  echo ""
  echo -e "${BLUE}=====================================================${NC}"
  echo -e "${GREEN}설정 요약:${NC}"
  echo -e "${GREEN}- 프로토콜: $(echo $WS_PROTOCOL | tr '[:lower:]' '[:upper:]')${NC}"
  echo -e "${GREEN}- 서버 주소: ${WS_SERVER_HOST}${NC}"
  echo -e "${GREEN}- 포트: ${WS_SERVER_PORT}${NC}"
  echo -e "${GREEN}- 모니터링 간격: ${MONITOR_INTERVAL}초${NC}"
  echo -e "${GREEN}- 디버그 모드: $([ "$DEBUG_MODE" = "true" ] && echo "활성화" || echo "비활성화")${NC}"
  if [ "$WS_PROTOCOL" = "wss" ]; then
    echo -e "${GREEN}- SSL 검증: $([ "$SSL_VERIFY" = "true" ] && echo "활성화" || echo "비활성화")${NC}"
  fi
  echo -e "${BLUE}=====================================================${NC}"
  echo ""
  
  # 인증은 나중에 처리
  REQUIRE_AUTH="true"  # 기본값으로 설정
}

# 기본값 설정
# WebSocket 설정 기본값
WS_MODE="ws"
WS_SERVER_HOST="localhost"
WS_SERVER_PORT="8080"

# 모니터링 설정 기본값  
MONITOR_INTERVAL="1"
DEBUG_MODE="false"

# SSL 설정 기본값
SSL_VERIFY="false"

# 인증 설정 기본값
REQUIRE_AUTH="true"
AUTH_ALLOW_HTTP="true"

# 기타 설정 기본값
MAX_RETRIES="10"
RETRY_INTERVAL="5"
RUN_MODE="normal"
NO_DOCKER="false"

# 대화형 설정 실행
interactive_setup

# .env.mclient 파일 업데이트
update_env_file

# mclient_data 디렉토리 생성
if [ ! -d "mclient_data" ]; then
  echo -e "${BLUE}mclient_data 디렉토리를 생성합니다...${NC}"
  mkdir -p mclient_data
  echo -e "${GREEN}mclient_data 디렉토리가 생성되었습니다.${NC}"
fi

# docker-compose-mclient.yml 파일 확인 및 생성
if [ ! -f "docker-compose-mclient.yml" ]; then
  echo -e "${BLUE}docker-compose-mclient.yml 파일을 생성합니다...${NC}"
  cat > docker-compose-mclient.yml << 'EOF'
services:
  mclient:
    image: mclient:${MCLIENT_VERSION:-1.0.0}
    container_name: mclient
    pid: "host"
    network_mode: host
    tty: true
    stdin_open: true
    env_file:
      - .env.mclient
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./mclient:/app
      - ./mclient_data:/app/data
      - /:/hostfs:ro
      - /proc:/proc:ro
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
  echo -e "${GREEN}docker-compose-mclient.yml 파일이 생성되었습니다.${NC}"
fi

# Docker 이미지 빌드 체크
if ! docker images | grep -q "mclient" | grep -q "${MCLIENT_VERSION}"; then
  echo -e "${YELLOW}이미지 ${IMAGE_NAME}가 존재하지 않습니다. 새로 빌드합니다...${NC}"
  
  # mclient 디렉토리 확인
  if [ ! -d "mclient" ]; then
    echo -e "${RED}mclient 디렉토리가 없습니다.${NC}"
    exit 1
  fi
  
  echo -e "${BLUE}mclient 이미지 ${IMAGE_NAME} 빌드 중...${NC}"
  docker build -t "${IMAGE_NAME}" ./mclient
  
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}이미지 빌드 완료${NC}"
  else
    echo -e "${RED}이미지 빌드 실패${NC}"
    exit 1
  fi
else
  echo -e "${GREEN}이미지 ${IMAGE_NAME}가 이미 존재합니다. 빌드를 건너뜁니다.${NC}"
fi

# mauth 실행 (인증)
echo -e "${BLUE}mclient 인증을 시작합니다...${NC}"
docker compose -f docker-compose-mclient.yml run --rm mclient python3 /app/mauth.py

if [ $? -eq 0 ]; then
  echo -e "${GREEN}인증이 완료되었습니다!${NC}"
  echo ""
  
  # mstart 실행 (백그라운드)
  echo -e "${BLUE}모니터링을 백그라운드로 시작합니다...${NC}"
  docker compose -f docker-compose-mclient.yml up -d mclient
  
  echo ""
  echo -e "${YELLOW}mclient 모니터링 명령어:${NC}"
  echo -e "${GREEN}mstatus${NC}  - mclient 상태 확인"
  echo -e "${GREEN}mlog${NC}     - mclient 로그 확인"
  echo -e "${GREEN}mstop${NC}    - 모니터링 중지"
  echo -e "${GREEN}mrestart${NC} - 모니터링 재시작"
else
  echo -e "${RED}mclient 인증에 실패했습니다.${NC}"
  exit 1
fi

echo -e "${BLUE}=====================================================${NC}"