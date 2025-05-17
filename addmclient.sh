#!/bin/bash
# addmclient.sh - Creditcoin 모니터링 클라이언트 추가 스크립트 (개선된 버전)

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# GitHub 저장소 정보
GITHUB_REPO="sigmo2nd/creditcoin-mac"
GITHUB_BRANCH="monitoring"  # 모니터링 클라이언트 파일이 있는 별도 브랜치
MCLIENT_ORG_DIR="mclient_org"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/${MCLIENT_ORG_DIR}"

# Docker 명령어 및 환경 확인
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
  export DOCKER_HOST="unix://$HOME/.orbstack/run/docker.sock"
  export DOCKER_CLI_NO_CREDENTIAL_STORE=1
  
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

# 기본값 설정
SERVER_ID="server1"
NODE_NAMES="node,3node"
MONITOR_INTERVAL="5"
WS_MODE="local"  # 기본값은 로컬 모드
WS_SERVER_URL=""
WS_SERVER_HOST=""
WS_PROTOCOL="ws"
WS_PORT_WS="8080"
WS_PORT_WSS="8443"
WS_PRESET=""
NO_SSL_VERIFY=false
CREDITCOIN_DIR=$(pwd)
FORCE=false
INTERACTIVE=false

# 도움말 표시 함수
show_help() {
  echo "사용법: $0 [옵션]"
  echo ""
  echo "옵션:"
  echo "  -s, --server-id        서버 ID (기본값: server1)"
  echo "  -n, --node-names       모니터링할 노드 이름 목록 (쉼표로 구분, 기본값: node,3node)"
  echo "  -i, --interval         모니터링 간격(초) (기본값: 5)"
  echo "  --interactive          대화형 모드로 실행"
  echo "  --mode <mode>          연결 모드 (custom, host, local, preset)"
  echo "  --url <url>            WebSocket URL (custom 모드용)"
  echo "  --host <host>          WebSocket 서버 호스트 (host 모드용)"
  echo "  --protocol <protocol>  WebSocket 프로토콜 (ws, wss) (host 모드용)"
  echo "  --port-ws <port>       WS 포트 (기본값: 8080) (host 모드용)"
  echo "  --port-wss <port>      WSS 포트 (기본값: 8443) (host 모드용)"
  echo "  --preset <preset>      프리셋 선택 (gcloud, aws, azure, local) (preset 모드용)"
  echo "  --no-ssl-verify        SSL 인증서 검증 비활성화"
  echo "  -c, --creditcoin       Creditcoin 디렉토리 (기본값: 현재 디렉토리)"
  echo "  -f, --force            기존 설정 덮어쓰기"
  echo "  -h, --help             도움말 표시"
  echo ""
  echo "사용 예시:"
  echo "  ./addmclient.sh --interactive                     # 대화형 모드로 실행"
  echo "  ./addmclient.sh --mode custom --url wss://192.168.0.24:8443/ws --no-ssl-verify  # 커스텀 URL 모드 (IP 주소 지정)"
  echo "  ./addmclient.sh --mode host --host 192.168.0.24 --protocol wss  # 호스트 지정 모드 (IP 주소 지정)"
  echo "  ./addmclient.sh --mode local                      # 로컬 모드 (WebSocket 연결 없음)"
  echo "  ./addmclient.sh --mode preset --preset gcloud     # 프리셋 모드 (미리 정의된 설정 사용)"
  echo ""
}

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
    --interactive)
      INTERACTIVE=true
      shift
      ;;
    --mode)
      WS_MODE="$2"
      shift 2
      ;;
    --url)
      WS_SERVER_URL="$2"
      shift 2
      ;;
    --host)
      WS_SERVER_HOST="$2"
      shift 2
      ;;
    --protocol)
      WS_PROTOCOL="$2"
      shift 2
      ;;
    --port-ws)
      WS_PORT_WS="$2"
      shift 2
      ;;
    --port-wss)
      WS_PORT_WSS="$2"
      shift 2
      ;;
    --preset)
      WS_PRESET="$2"
      shift 2
      ;;
    --no-ssl-verify)
      NO_SSL_VERIFY=true
      shift
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

# 대화형 모드 처리
if [ "$INTERACTIVE" = true ]; then
  echo -e "${BLUE}Creditcoin 모니터링 클라이언트 설정 (대화형 모드)${NC}"
  
  # 연결 모드 선택
  echo -e "${YELLOW}연결 모드를 선택하세요:${NC}"
  echo "1) 직접 URL 지정 (custom)"
  echo "2) 호스트+프로토콜 지정 (host)"
  echo "3) 로컬 모드 (local)"
  echo "4) 프리셋 사용 (preset)"
  read -p "선택 (1-4): " mode_choice
  
  case $mode_choice in
    1)
      WS_MODE="custom"
      read -p "WebSocket URL을 입력하세요 (예: wss://192.168.0.24:8443/ws): " WS_SERVER_URL
      read -p "SSL 인증서 검증을 건너뛰겠습니까? (y/n): " ssl_verify_choice
      if [[ "$ssl_verify_choice" =~ ^[Yy]$ ]]; then
        NO_SSL_VERIFY=true
      fi
      ;;
    2)
      WS_MODE="host"
      read -p "호스트 주소를 입력하세요 (예: 192.168.0.24): " WS_SERVER_HOST
      read -p "프로토콜을 선택하세요 (ws/wss): " WS_PROTOCOL
      read -p "WS 포트를 입력하세요 (기본값: 8080): " ws_port_input
      if [ ! -z "$ws_port_input" ]; then
        WS_PORT_WS="$ws_port_input"
      fi
      read -p "WSS 포트를 입력하세요 (기본값: 8443): " wss_port_input
      if [ ! -z "$wss_port_input" ]; then
        WS_PORT_WSS="$wss_port_input"
      fi
      ;;
    3)
      WS_MODE="local"
      echo -e "${GREEN}로컬 모드가 선택되었습니다. WebSocket 서버 연결 없이 실행됩니다.${NC}"
      ;;
    4)
      WS_MODE="preset"
      echo "프리셋을 선택하세요:"
      echo "1) Google Cloud"
      echo "2) AWS"
      echo "3) Azure"
      echo "4) 로컬 서버"
      read -p "선택 (1-4): " preset_choice
      
      case $preset_choice in
        1) WS_PRESET="gcloud" ;;
        2) WS_PRESET="aws" ;;
        3) WS_PRESET="azure" ;;
        4) WS_PRESET="local" ;;
        *) echo -e "${RED}유효하지 않은 선택입니다. 로컬 서버를 사용합니다.${NC}"; WS_PRESET="local" ;;
      esac
      ;;
    *)
      echo -e "${RED}유효하지 않은 선택입니다. 기본값(로컬 모드)을 사용합니다.${NC}"
      WS_MODE="local"
      ;;
  esac
  
  # 기본 설정 입력
  read -p "서버 ID를 입력하세요 (기본값: $SERVER_ID): " server_id_input
  if [ ! -z "$server_id_input" ]; then
    SERVER_ID="$server_id_input"
  fi
  
  read -p "모니터링할 노드 이름을 입력하세요 (쉼표로 구분, 기본값: $NODE_NAMES): " node_names_input
  if [ ! -z "$node_names_input" ]; then
    NODE_NAMES="$node_names_input"
  fi
  
  read -p "모니터링 간격(초)을 입력하세요 (기본값: $MONITOR_INTERVAL): " interval_input
  if [ ! -z "$interval_input" ]; then
    MONITOR_INTERVAL="$interval_input"
  fi
fi

# 모드 검증
if [ "$WS_MODE" = "custom" ] && [ -z "$WS_SERVER_URL" ]; then
  echo -e "${RED}오류: custom 모드에서는 WebSocket URL이 필요합니다.${NC}"
  exit 1
fi

if [ "$WS_MODE" = "host" ] && [ -z "$WS_SERVER_HOST" ]; then
  echo -e "${RED}오류: host 모드에서는 WebSocket 서버 호스트가 필요합니다.${NC}"
  exit 1
fi

if [ "$WS_MODE" = "preset" ] && [ -z "$WS_PRESET" ]; then
  echo -e "${RED}오류: preset 모드에서는 프리셋 선택이 필요합니다.${NC}"
  exit 1
fi

# 설정 요약 표시
echo -e "${BLUE}Creditcoin 파이썬 모니터링 설정:${NC}"
echo -e "${GREEN}- 서버 ID: $SERVER_ID${NC}"
echo -e "${GREEN}- 모니터링 노드: $NODE_NAMES${NC}"
echo -e "${GREEN}- 모니터링 간격: ${MONITOR_INTERVAL}초${NC}"
echo -e "${GREEN}- 연결 모드: $WS_MODE${NC}"

# 모드별 추가 정보 표시
case $WS_MODE in
  "custom")
    echo -e "${GREEN}- WebSocket URL: $WS_SERVER_URL${NC}"
    if [ "$NO_SSL_VERIFY" = true ]; then
      echo -e "${GREEN}- SSL 검증: 비활성화${NC}"
    fi
    ;;
  "host")
    echo -e "${GREEN}- WebSocket 호스트: $WS_SERVER_HOST${NC}"
    echo -e "${GREEN}- WebSocket 프로토콜: $WS_PROTOCOL${NC}"
    echo -e "${GREEN}- WS 포트: $WS_PORT_WS${NC}"
    echo -e "${GREEN}- WSS 포트: $WS_PORT_WSS${NC}"
    ;;
  "preset")
    echo -e "${GREEN}- 프리셋: $WS_PRESET${NC}"
    ;;
  "local")
    echo -e "${GREEN}- 로컬 모드: WebSocket 서버 연결 없음${NC}"
    ;;
esac

echo -e "${GREEN}- Creditcoin 디렉토리: $CREDITCOIN_DIR${NC}"

# 현재 디렉토리
CURRENT_DIR=$(pwd)

# mclient 디렉토리 확인 및 생성
if [ ! -d "./mclient" ]; then
  mkdir -p ./mclient
  echo -e "${BLUE}mclient 디렉토리를 생성했습니다.${NC}"
else
  echo -e "${BLUE}기존 mclient 디렉토리를 사용합니다.${NC}"
fi

# 필요한 파일 다운로드
download_mclient_files() {
  echo -e "${BLUE}모니터링 클라이언트 필수 파일 다운로드 중...${NC}"
  
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
# 시스템 패키지 설치 (빌드 도구 포함)
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
# 타임존은 /etc/localtime 볼륨 마운트를 통해 호스트 시스템의 타임존을 사용합니다
# pip 업그레이드 및 wheel 패키지 설치
RUN pip install --no-cache-dir --upgrade pip setuptools wheel
# 파이썬 패키지 설치 - 기본 패키지 먼저 설치
RUN pip install --no-cache-dir psutil==5.9.6 docker==6.1.3
# 소스 코드 복사
COPY . /app/
# 나머지 요구사항 파일 복사 및 설치
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt
# 권한 설정
RUN chmod +x /app/main.py
# 스타트업 스크립트 생성
RUN echo '#!/bin/bash' > /app/start.sh && \
    echo 'echo "== Creditcoin Python 모니터링 클라이언트 ==" ' >> /app/start.sh && \
    echo 'echo "서버 ID: ${SERVER_ID}"' >> /app/start.sh && \
    echo 'echo "모니터링 노드: ${NODE_NAMES}"' >> /app/start.sh && \
    echo 'echo "모니터링 간격: ${MONITOR_INTERVAL}초"' >> /app/start.sh && \
    echo 'echo "WebSocket 모드: ${WS_MODE}"' >> /app/start.sh && \
    echo 'echo "시작 중..."' >> /app/start.sh && \
    echo 'export PROCFS_PATH=/host/proc' >> /app/start.sh && \
    echo 'python /app/main.py' >> /app/start.sh && \
    chmod +x /app/start.sh
# 시작 명령어
ENTRYPOINT ["/app/start.sh"]
# 헬스체크
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD ps aux | grep python | grep main.py || exit 1
EOF

  echo -e "${GREEN}Dockerfile이 생성되었습니다.${NC}"
}

# 환경 변수 안전하게 업데이트 함수
update_env_file() {
  # .env 파일이 존재하는지 확인
  if [ -f ".env" ]; then
    # 백업 생성
    echo -e "${BLUE}기존 .env 파일 백업 중...${NC}"
    cp .env ".env.bak.$(date +%Y%m%d%H%M%S)"
  fi
  
  # 새 .env 파일 생성
  echo -e "${BLUE}새 .env 파일 생성 중...${NC}"
  
  # 기존 .env 파일에서 mclient 관련 변수를 제외한 내용 추출
  if [ -f ".env" ]; then
    # macOS 호환성을 위해 grep에 -v 옵션 사용
    grep -v "^SERVER_ID=\|^NODE_NAMES=\|^MONITOR_INTERVAL=\|^WS_MODE=\|^WS_SERVER_URL=\|^WS_SERVER_HOST=\|^CREDITCOIN_DIR=" .env > .env.tmp
  else
    touch .env.tmp
  fi
  
  # 모니터링 변수 추가
  echo "SERVER_ID=${SERVER_ID}" >> .env.tmp
  echo "NODE_NAMES=${NODE_NAMES}" >> .env.tmp
  echo "MONITOR_INTERVAL=${MONITOR_INTERVAL}" >> .env.tmp
  
  # WebSocket 모드에 따른 설정 추가
  case $WS_MODE in
    "custom")
      echo "WS_MODE=custom" >> .env.tmp
      echo "WS_SERVER_URL=${WS_SERVER_URL}" >> .env.tmp
      if [ "$NO_SSL_VERIFY" = true ]; then
        echo "NO_SSL_VERIFY=true" >> .env.tmp
      fi
      ;;
    "host")
      echo "WS_MODE=${WS_PROTOCOL}" >> .env.tmp
      echo "WS_SERVER_HOST=${WS_SERVER_HOST}" >> .env.tmp
      echo "WS_PORT_WS=${WS_PORT_WS}" >> .env.tmp
      echo "WS_PORT_WSS=${WS_PORT_WSS}" >> .env.tmp
      ;;
    "preset")
      echo "WS_MODE=preset" >> .env.tmp
      echo "WS_PRESET=${WS_PRESET}" >> .env.tmp
      ;;
    "local")
      echo "WS_MODE=local" >> .env.tmp
      echo "RUN_MODE=local" >> .env.tmp
      ;;
  esac
  
  echo "CREDITCOIN_DIR=${CREDITCOIN_DIR}" >> .env.tmp
  
  # 임시 파일을 .env로 이동
  mv .env.tmp .env
  
  echo -e "${GREEN}.env 파일이 성공적으로 업데이트되었습니다.${NC}"
}

# mclient/.env 파일 업데이트
update_mclient_env() {
  # mclient/.env 파일 생성
  cat > ./mclient/.env << EOF
# 모니터링 클라이언트 기본 설정
SERVER_ID=${SERVER_ID}
NODE_NAMES=${NODE_NAMES}
MONITOR_INTERVAL=${MONITOR_INTERVAL}

# WebSocket 설정
EOF

  # WebSocket 모드에 따른 설정 추가
  case $WS_MODE in
    "custom")
      cat >> ./mclient/.env << EOF
WS_MODE=custom
WS_SERVER_URL=${WS_SERVER_URL}
EOF
      if [ "$NO_SSL_VERIFY" = true ]; then
        echo "NO_SSL_VERIFY=true" >> ./mclient/.env
      fi
      ;;
    "host")
      cat >> ./mclient/.env << EOF
WS_MODE=${WS_PROTOCOL}
WS_SERVER_HOST=${WS_SERVER_HOST}
WS_PORT_WS=${WS_PORT_WS}
WS_PORT_WSS=${WS_PORT_WSS}
EOF
      ;;
    "preset")
      cat >> ./mclient/.env << EOF
WS_MODE=preset
WS_PRESET=${WS_PRESET}
EOF
      ;;
    "local")
      cat >> ./mclient/.env << EOF
WS_MODE=local
RUN_MODE=local
EOF
      ;;
  esac

  # 디렉토리 설정 추가
  echo -e "\n# 디렉토리 설정\nCREDITCOIN_DIR=${CREDITCOIN_DIR}" >> ./mclient/.env

  echo -e "${GREEN}mclient/.env 파일이 업데이트되었습니다.${NC}"
}

# OrbStack 환경에서 Docker 소켓 경로 확인
find_docker_sock_path() {
  # 기본 OrbStack Docker 소켓 경로
  DOCKER_SOCK_PATH="$HOME/.orbstack/run/docker.sock"
  
  if [ ! -S "$DOCKER_SOCK_PATH" ]; then
    echo -e "${YELLOW}OrbStack Docker 소켓을 찾을 수 없습니다. 대체 경로를 시도합니다...${NC}"
    
    # 대체 가능한 Docker 소켓 경로 목록
    POSSIBLE_PATHS=(
      "/var/run/docker.sock"
      "/var/run/orbstack/docker.sock"
      "$HOME/Library/Containers/com.orbstack.Orbstack/Data/run/docker.sock"
    )
    
    for path in "${POSSIBLE_PATHS[@]}"; do
      if [ -S "$path" ]; then
        DOCKER_SOCK_PATH="$path"
        echo -e "${GREEN}Docker 소켓 발견: $DOCKER_SOCK_PATH${NC}"
        break
      fi
    done
  fi
  
  echo $DOCKER_SOCK_PATH
}

# docker-compose.yml 파일 업데이트
update_docker_compose() {
  # docker-compose.yml 파일 확인
  if [ ! -f "docker-compose.yml" ]; then
    echo -e "${RED}오류: docker-compose.yml 파일이 없습니다.${NC}"
    echo -e "${YELLOW}먼저 add3node.sh를 실행하여 기본 환경을 구성한 후 다시 시도하세요.${NC}"
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
      echo -e "${YELLOW}mclient 서비스가 이미 존재하지만, 강제 옵션이 지정되어 업데이트합니다.${NC}"
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
      echo -e "${YELLOW}mclient 서비스가 이미 존재합니다. --force 또는 -f 옵션을 사용하여 덮어쓸 수 있습니다.${NC}"
      echo -e "${GREEN}기존 mclient 서비스를 계속 사용합니다.${NC}"
      return
    fi
  fi
  
  # networks 섹션 위치 찾기
  networks_line=$(grep -n "^networks:" docker-compose.yml | cut -d: -f1)
  
  if [ -n "$networks_line" ]; then
    # 모드별 환경 변수 설정
    mclient_environment=""
    
    # 기본 환경 변수
    mclient_environment+="      - SERVER_ID=${SERVER_ID}\n"
    mclient_environment+="      - NODE_NAMES=${NODE_NAMES}\n"
    mclient_environment+="      - MONITOR_INTERVAL=${MONITOR_INTERVAL}\n"
    
    # 모드별 환경 변수 추가
    case $WS_MODE in
      "custom")
        mclient_environment+="      - WS_MODE=custom\n"
        mclient_environment+="      - WS_SERVER_URL=${WS_SERVER_URL}\n"
        if [ "$NO_SSL_VERIFY" = true ]; then
          mclient_environment+="      - NO_SSL_VERIFY=true\n"
        fi
        ;;
      "host")
        mclient_environment+="      - WS_MODE=${WS_PROTOCOL}\n"
        mclient_environment+="      - WS_SERVER_HOST=${WS_SERVER_HOST}\n"
        mclient_environment+="      - WS_PORT_WS=${WS_PORT_WS}\n"
        mclient_environment+="      - WS_PORT_WSS=${WS_PORT_WSS}\n"
        ;;
      "preset")
        mclient_environment+="      - WS_MODE=preset\n"
        mclient_environment+="      - WS_PRESET=${WS_PRESET}\n"
        
        # 프리셋별 추가 환경 변수
        case $WS_PRESET in
          "gcloud")
            mclient_environment+="      - WS_SERVER_HOST=gcloud.example.com\n"
            mclient_environment+="      - WS_MODE=wss\n"
            ;;
          "aws")
            mclient_environment+="      - WS_SERVER_HOST=aws.example.com\n"
            mclient_environment+="      - WS_MODE=wss\n"
            ;;
          "azure")
            mclient_environment+="      - WS_SERVER_HOST=azure.example.com\n"
            mclient_environment+="      - WS_MODE=wss\n"
            ;;
          "local")
            mclient_environment+="      - WS_SERVER_HOST=localhost\n"
            mclient_environment+="      - WS_MODE=ws\n"
            ;;
        esac
        ;;
      "local")
        mclient_environment+="      - WS_MODE=local\n"
        mclient_environment+="      - RUN_MODE=local\n"
        ;;
    esac
    
    # 공통 환경 변수
    mclient_environment+="      - CREDITCOIN_DIR=/creditcoin-mac\n"
    mclient_environment+="      # Docker 접근을 위한 환경 변수\n"
    mclient_environment+="      - DOCKER_HOST=unix:///var/run/docker.sock\n"
    mclient_environment+="      - DOCKER_API_VERSION=1.41\n"
    mclient_environment+="      # 호스트 시스템 정보 접근을 위한 환경 변수\n"
    mclient_environment+="      - HOST_PROC=/host/proc\n"
    mclient_environment+="      - HOST_SYS=/host/sys\n"
    
    # networks 섹션 앞에 mclient 서비스 삽입
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

# 필요한 파일 다운로드
download_mclient_files

# Dockerfile 생성
create_dockerfile

# .env 파일 업데이트
update_env_file

# mclient/.env 파일 업데이트
update_mclient_env

# docker-compose.yml 파일 업데이트
update_docker_compose

echo -e "${BLUE}----------------------------------------------------${NC}"
echo -e "${GREEN}Creditcoin 모니터링 클라이언트 설정이 완료되었습니다!${NC}"
echo -e "${GREEN}다음 설정으로 모니터링 클라이언트가 구성되었습니다:${NC}"
echo -e "${GREEN}- 서버 ID: ${SERVER_ID}${NC}"
echo -e "${GREEN}- 모니터링 노드: ${NODE_NAMES}${NC}"
echo -e "${GREEN}- 모니터링 간격: ${MONITOR_INTERVAL}초${NC}"
echo -e "${GREEN}- 연결 모드: ${WS_MODE}${NC}"

# 모드별 추가 정보 표시
case $WS_MODE in
  "custom")
    echo -e "${GREEN}- WebSocket URL: ${WS_SERVER_URL}${NC}"
    if [ "$NO_SSL_VERIFY" = true ]; then
      echo -e "${GREEN}- SSL 검증: 비활성화${NC}"
    fi
    ;;
  "host")
    echo -e "${GREEN}- WebSocket 호스트: ${WS_SERVER_HOST}${NC}"
    echo -e "${GREEN}- WebSocket 프로토콜: ${WS_PROTOCOL}${NC}"
    echo -e "${GREEN}- WS 포트: ${WS_PORT_WS}${NC}"
    echo -e "${GREEN}- WSS 포트: ${WS_PORT_WSS}${NC}"
    ;;
  "preset")
    echo -e "${GREEN}- 프리셋: ${WS_PRESET}${NC}"
    ;;
  "local")
    echo -e "${GREEN}- 로컬 모드: WebSocket 서버 연결 없음${NC}"
    ;;
esac

echo -e "${GREEN}- Creditcoin 디렉토리: ${CREDITCOIN_DIR}${NC}"
echo -e "${GREEN}- Docker 소켓 경로: ${DOCKER_SOCK_PATH}${NC}"
echo -e "${BLUE}----------------------------------------------------${NC}"

# 모니터링 클라이언트 시작 여부 확인
echo -e "${YELLOW}모니터링 클라이언트를 시작하시겠습니까? (Y/n) ${NC}"
read -r response
if [[ "$response" =~ ^([nN][oO]|[nN])$ ]]; then
  echo -e "${YELLOW}모니터링 클라이언트를 시작하지 않습니다.${NC}"
  echo -e "${YELLOW}나중에 다음 명령어로 시작할 수 있습니다:${NC}"
  echo -e "${GREEN}docker compose -p creditcoin3 up -d mclient${NC}"
  echo -e "${YELLOW}또는 shell 함수를 사용하여 시작:${NC}"
  echo -e "${GREEN}mclient-start${NC}"
else
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
    echo -e "${YELLOW}로그 확인:${NC} ${GREEN}docker compose -p creditcoin3 logs -f mclient${NC}"
    echo -e "${YELLOW}또는 shell 함수를 사용하여 로그 확인:${NC} ${GREEN}mclient-logs${NC}"
  else
    echo -e "${RED}모니터링 클라이언트 시작에 실패했습니다.${NC}"
    echo -e "${YELLOW}로그를 확인하여 문제를 진단하세요.${NC}"
  fi
fi

echo -e "${YELLOW}유틸리티 함수를 사용하려면 다음 명령어를 실행하세요:${NC}"
echo -e "${GREEN}source ~/.bash_profile${NC} ${YELLOW}또는${NC} ${GREEN}source ~/.zshrc${NC}"
echo -e "${YELLOW}(사용 중인 셸에 따라 다름)${NC}"
echo -e ""
echo -e "${YELLOW}사용 가능한 명령어:${NC}"
echo -e "${GREEN}mclient-start${NC}    - 모니터링 클라이언트 시작"
echo -e "${GREEN}mclient-stop${NC}     - 모니터링 클라이언트 중지"
echo -e "${GREEN}mclient-restart${NC}  - 모니터링 클라이언트 재시작"
echo -e "${GREEN}mclient-logs${NC}     - 모니터링 클라이언트 로그 표시"
echo -e "${GREEN}mclient-status${NC}   - 모니터링 클라이언트 상태 확인"
echo -e "${GREEN}mclient-local${NC}    - 로컬 모드로 모니터링 클라이언트 실행"