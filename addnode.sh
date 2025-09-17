#!/bin/bash
# addnode.sh - macOS용 통합 Creditcoin 노드 추가 스크립트 (2.x/3.x 지원, OrbStack 호환)

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

# 도움말 표시 함수
show_help() {
  echo "사용법: $0 <노드번호> [옵션]"
  echo ""
  echo "필수 매개변수:"
  echo "  <노드번호>         생성할 노드의 번호 (예: 0, 1, 2, ...)"
  echo ""
  echo "옵션:"
  echo "  -l, --legacy       Creditcoin 2.x 레거시 버전 사용 (기본값: 3.x)"
  echo "  -v, --version      노드 버전"
  echo "                     - 3.x: 3.52.0-mainnet (기본값)"
  echo "                     - 2.x: 2.230.2-mainnet (기본값)"
  echo "  -t, --telemetry    텔레메트리 활성화 (기본값: 비활성화)"
  echo "  -n, --name         노드 이름"
  echo "                     - 3.x: 3Node<번호> (기본값)"
  echo "                     - 2.x: Node<번호> (기본값)"
  echo "  -p, --pruning      프루닝 값 설정 (3.x만 지원, 기본값: 0)"
  echo "  --upgrade          기존 노드 업그레이드 (세션키 보존)"
  echo ""
  echo "사용 예시:"
  echo "  ./addnode.sh 0                          # 3.x 버전으로 3node0 생성"
  echo "  ./addnode.sh 0 -l                       # 2.x 버전으로 node0 생성 (legacy)"
  echo "  ./addnode.sh 1 -v 3.32.0-mainnet        # 특정 3.x 버전으로 생성"
  echo "  ./addnode.sh 1 -l -v 2.230.2-mainnet    # 특정 2.x 버전으로 생성"
  echo "  ./addnode.sh 2 -t                       # 텔레메트리 활성화하여 생성"
  echo "  ./addnode.sh 3 -n ValidatorA             # 지정한 이름으로 생성"
  echo "  ./addnode.sh 4 -p 1000                  # 프루닝 값 1000으로 설정 (3.x만)"
  echo "  ./addnode.sh 0 --upgrade                # 3node0을 최신 버전으로 업그레이드"
  echo "  ./addnode.sh 1 --upgrade -v 3.52.0-mainnet # 특정 버전으로 업그레이드"
  echo ""
  echo "버전 정보:"
  echo "  3.x 버전 (기본값):"
  echo "    - 3.52.0-mainnet: 최신 메인넷 버전"
  echo "    - 3.32.0-mainnet: 안정 메인넷 버전"
  echo "  2.x 버전 (레거시):"
  echo "    - 2.230.2-mainnet: 레거시 메인넷 버전"
  echo ""
}

# 매개변수가 없거나 첫 번째 매개변수가 도움말이면 도움말 표시
if [ $# -lt 1 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  show_help
  exit 0
fi

# 첫 번째 매개변수는 노드 번호
NODE_NUM=$1
shift

# 버전별 기본값 설정
LEGACY_MODE=false
UPDATE_MODE=false
VERSION_3X="3.52.0-mainnet"
VERSION_2X="2.230.2-mainnet"
TELEMETRY_ENABLED="false"
PRUNING="0"

# 옵션 파싱
while [ $# -gt 0 ]; do
  case "$1" in
    -l|--legacy)
      LEGACY_MODE=true
      shift
      ;;
    -v|--version)
      CUSTOM_VERSION="$2"
      shift 2
      ;;
    -t|--telemetry)
      TELEMETRY_ENABLED="true"
      shift
      ;;
    -n|--name)
      CUSTOM_TELEMETRY_NAME="$2"
      shift 2
      ;;
    -p|--pruning)
      PRUNING="$2"
      shift 2
      ;;
    --upgrade)
      UPDATE_MODE=true
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

# 버전별 설정 적용
if [ "$LEGACY_MODE" = true ]; then
  # Creditcoin 2.x 설정
  GIT_TAG="${CUSTOM_VERSION:-$VERSION_2X}"
  NODE_NAME="node$NODE_NUM"
  TELEMETRY_NAME="${CUSTOM_TELEMETRY_NAME:-}"
  NODE_PREFIX="node"
  IMAGE_NAME="creditcoin2:${GIT_TAG}"
  P2P_PORT_BASE=30240  # 3.x보다 100 낮게 (30240~30339)
  RPC_PORT_BASE=33880  # 3.x보다 100 낮게 (33880~33979)
  ENV_PREFIX="NODE"
  DOCKER_COMPOSE_FILE="docker-compose-legacy.yml"
  NETWORK_NAME="creditnet2"
  DOCKERFILE_NAME="Dockerfile.legacy"
  CHAINSPEC_OPTION="--chain mainnet"
  SUPPORTS_PRUNING=false
  
  # 프루닝은 2.x에서 지원하지 않음
  if [ "$PRUNING" != "0" ]; then
    echo -e "${YELLOW}경고: 프루닝은 Creditcoin 2.x에서 지원되지 않습니다. 무시됩니다.${NC}"
    PRUNING="0"
  fi
else
  # Creditcoin 3.x 설정
  GIT_TAG="${CUSTOM_VERSION:-$VERSION_3X}"
  NODE_NAME="3node$NODE_NUM"
  TELEMETRY_NAME="${CUSTOM_TELEMETRY_NAME:-}"
  NODE_PREFIX="3node"
  IMAGE_NAME="creditcoin3:${GIT_TAG}"
  P2P_PORT_BASE=30340
  RPC_PORT_BASE=33980
  ENV_PREFIX="3NODE"
  DOCKER_COMPOSE_FILE="docker-compose.yml"
  NETWORK_NAME="creditnet"
  DOCKERFILE_NAME="Dockerfile"
  CHAINSPEC_OPTION="--chain /root/data/chainspecs/mainnetSpecRaw.json"
  SUPPORTS_PRUNING=true
fi

# 계산된 포트
P2P_PORT=$((P2P_PORT_BASE + NODE_NUM))
RPC_PORT=$((RPC_PORT_BASE + NODE_NUM))
# 레거시 모드에서는 WS_PORT가 RPC_PORT와 같음
if [ "$LEGACY_MODE" = true ]; then
  WS_PORT=$RPC_PORT
fi

echo -e "${BLUE}사용할 설정:${NC}"
echo -e "${GREEN}- 모드: $([ "$LEGACY_MODE" = true ] && echo "Creditcoin 2.x (Legacy)" || echo "Creditcoin 3.x (Current)")${NC}"
echo -e "${GREEN}- 노드 번호: $NODE_NUM${NC}"
echo -e "${GREEN}- 노드 이름: $NODE_NAME${NC}"
if [ -n "$TELEMETRY_NAME" ]; then
  echo -e "${GREEN}- 텔레메트리 이름: $TELEMETRY_NAME${NC}"
fi
echo -e "${GREEN}- 텔레메트리: $([ "$TELEMETRY_ENABLED" == "true" ] && echo "활성화" || echo "비활성화")${NC}"
echo -e "${GREEN}- 버전: $GIT_TAG${NC}"
echo -e "${GREEN}- P2P 포트: $P2P_PORT${NC}"
echo -e "${GREEN}- RPC 포트: $RPC_PORT${NC}"
if [ "$SUPPORTS_PRUNING" = true ]; then
  echo -e "${GREEN}- 프루닝: $PRUNING $([ "$PRUNING" == "0" ] && echo "(비활성화)" || echo "")${NC}"
fi

# 현재 작업 디렉토리 저장
CURRENT_DIR=$(pwd)

# UPDATE_MODE일 때 처리
if [ "$UPDATE_MODE" = true ]; then
  echo -e "${BLUE}=== 노드 업그레이드 모드 ===${NC}"
  echo -e "${GREEN}대상: ${NODE_NAME}${NC}"
  echo -e "${GREEN}버전: ${GIT_TAG}${NC}"

  # 노드 존재 확인
  if [ ! -d "${NODE_NAME}" ]; then
    echo -e "${RED}오류: ${NODE_NAME} 디렉토리가 존재하지 않습니다.${NC}"
    echo -e "${YELLOW}먼저 노드를 생성하세요: ./addnode.sh ${NODE_NUM}${NC}"
    exit 1
  fi

  # 세션 키 백업 (있는 경우)
  KEYSTORE_PATH="${NODE_NAME}/data/chains/creditcoin3/keystore"
  if [ "$LEGACY_MODE" = true ]; then
    KEYSTORE_PATH="${NODE_NAME}/data/chains/creditcoin/keystore"
  fi

  if [ -d "$KEYSTORE_PATH" ] && [ "$(ls -A $KEYSTORE_PATH 2>/dev/null)" ]; then
    echo -e "${GREEN}세션 키 발견. 백업 중...${NC}"
    BACKUP_NAME="${NODE_NAME}_keystore_backup_$(date +%Y%m%d_%H%M%S)"
    cp -r "$KEYSTORE_PATH" "$BACKUP_NAME"
    echo -e "${GREEN}백업 완료: $BACKUP_NAME${NC}"
  fi

  # 이미지 준비
  echo -e "${GREEN}Docker 이미지 준비 중...${NC}"
  if docker pull gluwa/creditcoin:${GIT_TAG} 2>/dev/null; then
    docker tag gluwa/creditcoin:${GIT_TAG} ${IMAGE_NAME}
    echo -e "${GREEN}이미지 준비 완료${NC}"
  else
    echo -e "${YELLOW}공식 이미지를 찾을 수 없습니다. 로컬 빌드를 시도합니다.${NC}"
  fi

  # docker-compose.yml 업데이트
  echo -e "${GREEN}docker-compose.yml 업데이트 중...${NC}"

  # 백업
  cp ${DOCKER_COMPOSE_FILE} ${DOCKER_COMPOSE_FILE}.backup_upgrade

  # 해당 노드 섹션만 업데이트
  sed -i.bak "/${NODE_NAME}:/,/^  [a-z]/{
    s|image: creditcoin[23]:[^[:space:]]*|image: ${IMAGE_NAME}|
    s|GIT_TAG=[^[:space:]]*|GIT_TAG=${GIT_TAG}|
  }" ${DOCKER_COMPOSE_FILE}

  # chainspecs 경로 업데이트
  sed -i "/${NODE_NAME}:/,/^  [a-z]/{
    s|./data/[^/]*/chainspecs|./data/${GIT_TAG}/chainspecs|
  }" ${DOCKER_COMPOSE_FILE}

  rm -f ${DOCKER_COMPOSE_FILE}.bak

  # 노드 재시작
  echo -e "${GREEN}노드 재시작 중...${NC}"
  docker-compose stop ${NODE_NAME}
  sleep 5
  docker-compose rm -f ${NODE_NAME}
  docker-compose up -d ${NODE_NAME}

  echo -e "${GREEN}업그레이드 완료!${NC}"
  echo ""
  echo "확인 명령어:"
  echo "  docker logs ${NODE_NAME} --tail 20"
  echo "  curl -s http://localhost:${RPC_PORT}/ -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"system_version\",\"params\":[],\"id\":1}'"
  echo ""
  echo "롤백이 필요한 경우:"
  echo "  cp ${DOCKER_COMPOSE_FILE}.backup_upgrade ${DOCKER_COMPOSE_FILE}"
  echo "  docker-compose up -d ${NODE_NAME}"

  exit 0
fi

# 기존 노드 존재 확인 및 처리
if [ -d "./${NODE_PREFIX}${NODE_NUM}" ]; then
  echo -e "${YELLOW}경고: ${NODE_PREFIX}${NODE_NUM}이 이미 존재합니다.${NC}"
  
  # 기존 노드의 버전 정보 확인
  CURRENT_VERSION=""
  if [ "$LEGACY_MODE" = true ]; then
    # 2.x 버전 확인 (환경변수에서)
    CURRENT_VERSION=$(grep "^GIT_TAG=" .env 2>/dev/null | cut -d= -f2)
  else
    # 3.x 버전 확인 (환경변수에서)
    CURRENT_VERSION=$(grep "^GIT_TAG=" .env 2>/dev/null | cut -d= -f2)
  fi
  
  echo -e "${BLUE}기존 노드 정보:${NC}"
  if [ -f ".env" ]; then
    echo -e "${GREEN}현재 설정:${NC}"
    if [ "$LEGACY_MODE" = true ]; then
      grep -E "NODE_NAME_${NODE_NUM}=|TELEMETRY_ENABLED_${NODE_NUM}=|P2P_PORT_NODE${NODE_NUM}=|WS_PORT_NODE${NODE_NUM}=" .env 2>/dev/null || echo "  설정을 찾을 수 없습니다."
    else
      grep -E "NODE_NAME_${ENV_PREFIX}${NODE_NUM}=|TELEMETRY_${ENV_PREFIX}${NODE_NUM}=|P2P_PORT_${ENV_PREFIX}${NODE_NUM}=|RPC_PORT_${ENV_PREFIX}${NODE_NUM}=|PRUNING_${ENV_PREFIX}${NODE_NUM}=" .env 2>/dev/null || echo "  설정을 찾을 수 없습니다."
    fi
    if [ -n "$CURRENT_VERSION" ]; then
      echo -e "${GREEN}현재 버전: ${CURRENT_VERSION}${NC}"
    fi
  fi
  
  # 버전 충돌 체크
  if [ -n "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" != "$GIT_TAG" ]; then
    echo -e "${RED}버전 충돌 감지!${NC}"
    echo -e "${YELLOW}기존 버전: ${CURRENT_VERSION}${NC}"
    echo -e "${YELLOW}새로운 버전: ${GIT_TAG}${NC}"
    echo -e "${RED}경고: 버전이 다르면 블록체인 데이터 호환성 문제가 발생할 수 있습니다!${NC}"
    echo ""
    echo -e "${YELLOW}다음 중 선택하세요:${NC}"
    echo "1) 취소 (권장)"
    echo "2) 완전히 덮어쓰기 (모든 데이터 삭제 후 새 버전으로 재생성)"
    echo ""
    read -p "선택 (1-2): " choice
    
    case $choice in
      1)
        echo -e "${GREEN}취소되었습니다.${NC}"
        exit 0
        ;;
      2)
        echo -e "${BLUE}완전히 덮어쓰기합니다...${NC}"
        UPDATE_MODE=false
        PRESERVE_DATA=false
        # 기존 디렉토리 삭제
        rm -rf "./${NODE_PREFIX}${NODE_NUM}"
        echo -e "${GREEN}기존 데이터가 삭제되었습니다.${NC}"
        ;;
      *)
        echo -e "${RED}잘못된 선택입니다. 취소합니다.${NC}"
        exit 1
        ;;
    esac
  else
    # 같은 버전인 경우 설정 업데이트 허용
    echo ""
    echo -e "${YELLOW}다음 중 선택하세요:${NC}"
    echo "1) 설정만 업데이트 (기존 블록체인 데이터 보존)"
    echo "2) 완전히 덮어쓰기 (모든 데이터 삭제 후 재생성)"
    echo "3) 취소"
    echo ""
    read -p "선택 (1-3): " choice
    
    case $choice in
      1)
        echo -e "${BLUE}설정만 업데이트합니다...${NC}"
        UPDATE_MODE=true
        PRESERVE_DATA=true
        ;;
      2)
        echo -e "${BLUE}완전히 덮어쓰기합니다...${NC}"
        UPDATE_MODE=false
        PRESERVE_DATA=false
        # 기존 디렉토리 삭제
        rm -rf "./${NODE_PREFIX}${NODE_NUM}"
        echo -e "${GREEN}기존 데이터가 삭제되었습니다.${NC}"
        ;;
      3)
        echo -e "${GREEN}취소되었습니다.${NC}"
        exit 0
        ;;
      *)
        echo -e "${RED}잘못된 선택입니다. 취소합니다.${NC}"
        exit 1
        ;;
    esac
  fi
else
  UPDATE_MODE=false
  PRESERVE_DATA=false
fi

# 노드 데이터 디렉토리 생성 (새 노드이거나 덮어쓰기 모드인 경우)
if [ "$PRESERVE_DATA" = false ]; then
  mkdir -p ./${NODE_PREFIX}${NODE_NUM}/data
fi

# 3.x 전용: 네트워크 키 디렉토리 생성 및 키 생성
if [ "$LEGACY_MODE" = false ] && [ "$PRESERVE_DATA" = false ]; then
  mkdir -p ./${NODE_PREFIX}${NODE_NUM}/data/chains/creditcoin3/network
  
  # 유효한 Ed25519 네트워크 키 생성 (32바이트 랜덤 데이터)
  dd if=/dev/random of=./${NODE_PREFIX}${NODE_NUM}/data/chains/creditcoin3/network/secret_ed25519 bs=32 count=1 2>/dev/null
  
  # 버전별 체인스펙 디렉토리 생성
  mkdir -p ./data/${GIT_TAG}/chainspecs
elif [ "$LEGACY_MODE" = false ] && [ "$PRESERVE_DATA" = true ]; then
  # 업데이트 모드에서는 체인스펙 디렉토리만 확인
  mkdir -p ./data/${GIT_TAG}/chainspecs
  echo -e "${GREEN}기존 네트워크 키를 보존합니다.${NC}"
fi

# 버전별 체인스펙 파일 다운로드
if [ "$LEGACY_MODE" = false ]; then
  # 3.x 체인스펙 다운로드
  if [ ! -f "./data/${GIT_TAG}/chainspecs/mainnetSpecRaw.json" ]; then
    echo -e "${BLUE}${GIT_TAG} 버전의 체인스펙 파일 다운로드 중...${NC}"
    
    # 디렉토리 생성
    mkdir -p "./data/${GIT_TAG}/chainspecs/"
    
    # 임시 디렉토리 생성
    TEMP_DIR=$(mktemp -d -t creditcoin3-chainspec-XXXXXX)
    cd "$TEMP_DIR"
    
    # 저장소 클론
    echo -e "${YELLOW}Git 저장소 클론 중...${NC}"
    git clone https://github.com/gluwa/creditcoin3.git
    cd creditcoin3
    
    # 브랜치 체크아웃
    git checkout ${GIT_TAG}
    
    # git-lfs 명시적 설정
    export GIT_LFS_SKIP_SMUDGE=0
    
    # git-lfs 확인 및 실행
    if command -v git-lfs &> /dev/null; then
      git lfs install --force
      git lfs fetch
      git lfs pull
      
      # 파일이 제대로 다운로드되었는지 확인
      if [ -f "chainspecs/mainnetSpecRaw.json" ]; then
        file_size=$(stat -f%z "chainspecs/mainnetSpecRaw.json" 2>/dev/null || stat -c%s "chainspecs/mainnetSpecRaw.json")
        echo -e "${GREEN}체인스펙 파일 크기: ${file_size} 바이트${NC}"
        
        # 파일 크기 검증 (최소 크기를 확인)
        if [ "$file_size" -lt 1000 ]; then  # 예상보다 작으면 경고
          echo -e "${YELLOW}경고: 체인스펙 파일이 예상보다 작습니다. 직접 다운로드를 시도합니다.${NC}"
          # 백업 방법으로 직접 다운로드 시도
          curl -L -o "chainspecs/mainnetSpecRaw.json.new" "https://raw.githubusercontent.com/gluwa/creditcoin3/${GIT_TAG}/chainspecs/mainnetSpecRaw.json"
          new_size=$(stat -f%z "chainspecs/mainnetSpecRaw.json.new" 2>/dev/null || stat -c%s "chainspecs/mainnetSpecRaw.json.new")
          
          if [ "$new_size" -gt "$file_size" ]; then
            mv "chainspecs/mainnetSpecRaw.json.new" "chainspecs/mainnetSpecRaw.json"
            echo -e "${GREEN}직접 다운로드로 더 큰 파일을 받았습니다: ${new_size} 바이트${NC}"
          else
            rm "chainspecs/mainnetSpecRaw.json.new"
          fi
        fi
        
        # 파일 복사
        cp "chainspecs/mainnetSpecRaw.json" "${CURRENT_DIR}/data/${GIT_TAG}/chainspecs/"
        echo -e "${GREEN}체인스펙 파일 다운로드 완료${NC}"
      else
        echo -e "${RED}오류: 체인스펙 파일을 찾을 수 없습니다. 직접 다운로드를 시도합니다.${NC}"
        # 대체 방법으로 직접 다운로드
        curl -L -o "${CURRENT_DIR}/data/${GIT_TAG}/chainspecs/mainnetSpecRaw.json" "https://raw.githubusercontent.com/gluwa/creditcoin3/${GIT_TAG}/chainspecs/mainnetSpecRaw.json"
        
        if [ -f "${CURRENT_DIR}/data/${GIT_TAG}/chainspecs/mainnetSpecRaw.json" ]; then
          echo -e "${GREEN}체인스펙 파일 직접 다운로드 완료${NC}"
        else
          echo -e "${RED}오류: 체인스펙 파일 다운로드에 실패했습니다.${NC}"
          cd "$CURRENT_DIR"
          rm -rf "$TEMP_DIR"
          exit 1
        fi
      fi
    else
      echo -e "${RED}오류: git-lfs가 설치되어 있지 않습니다. setup.sh를 먼저 실행하세요.${NC}"
      exit 1
    fi
    
    # 원래 디렉토리로 복귀 및 정리
    cd "$CURRENT_DIR"
    rm -rf "$TEMP_DIR"
  else
    echo -e "${GREEN}체인스펙 파일이 이미 존재합니다${NC}"
  fi
else
  # 2.x 체인스펙 다운로드 (Git LFS 방식)
  if [ ! -f "./data/${GIT_TAG}/chainspecs/mainnetSpecRaw.json" ]; then
    echo -e "${BLUE}${GIT_TAG} 버전의 체인스펙 파일 다운로드 중...${NC}"
    
    # 디렉토리 생성
    mkdir -p "./data/${GIT_TAG}/chainspecs/"
    
    # 임시 디렉토리 생성
    TEMP_DIR=$(mktemp -d -t creditcoin2-chainspec-XXXXXX)
    cd "$TEMP_DIR"
    
    # git-lfs 확인
    if command -v git-lfs > /dev/null 2>&1; then
      # 저장소 클론 (2.x)
      echo -e "${YELLOW}Git 저장소 클론 중...${NC}"
      git clone https://github.com/gluwa/creditcoin.git
      cd creditcoin
      
      # 해당 태그로 체크아웃
      git checkout ${GIT_TAG}
      
      # LFS 파일 다운로드
      git lfs pull
      
      # 체인스펙 파일 확인 및 복사
      if [ -f "chainspecs/mainnetSpecRaw.json" ]; then
        file_size=$(stat -f%z "chainspecs/mainnetSpecRaw.json" 2>/dev/null || stat -c%s "chainspecs/mainnetSpecRaw.json")
        if [ "$file_size" -lt 1000 ]; then
          echo -e "${YELLOW}LFS 파일이 제대로 다운로드되지 않았습니다. 직접 다운로드를 시도합니다.${NC}"
          curl -L -o "chainspecs/mainnetSpecRaw.json.new" "https://raw.githubusercontent.com/gluwa/creditcoin/${GIT_TAG}/chainspecs/mainnetSpecRaw.json"
          new_size=$(stat -f%z "chainspecs/mainnetSpecRaw.json.new" 2>/dev/null || stat -c%s "chainspecs/mainnetSpecRaw.json.new")
          
          if [ "$new_size" -gt 1000 ]; then
            mv "chainspecs/mainnetSpecRaw.json.new" "chainspecs/mainnetSpecRaw.json"
          else
            rm "chainspecs/mainnetSpecRaw.json.new"
          fi
        fi
        
        # 파일 복사
        cp "chainspecs/mainnetSpecRaw.json" "${CURRENT_DIR}/data/${GIT_TAG}/chainspecs/"
        echo -e "${GREEN}체인스펙 파일 다운로드 완료${NC}"
      else
        echo -e "${RED}오류: 체인스펙 파일을 찾을 수 없습니다. 직접 다운로드를 시도합니다.${NC}"
        # 대체 방법으로 직접 다운로드
        curl -L -o "${CURRENT_DIR}/data/${GIT_TAG}/chainspecs/mainnetSpecRaw.json" "https://raw.githubusercontent.com/gluwa/creditcoin/${GIT_TAG}/chainspecs/mainnetSpecRaw.json"
        
        if [ -f "${CURRENT_DIR}/data/${GIT_TAG}/chainspecs/mainnetSpecRaw.json" ]; then
          echo -e "${GREEN}체인스펙 파일 직접 다운로드 완료${NC}"
        else
          echo -e "${RED}오류: 체인스펙 파일 다운로드에 실패했습니다.${NC}"
          cd "$CURRENT_DIR"
          rm -rf "$TEMP_DIR"
          exit 1
        fi
      fi
    else
      echo -e "${RED}오류: git-lfs가 설치되어 있지 않습니다. setup.sh를 먼저 실행하세요.${NC}"
      exit 1
    fi
    
    # 원래 디렉토리로 복귀 및 정리
    cd "$CURRENT_DIR"
    rm -rf "$TEMP_DIR"
  else
    echo -e "${GREEN}체인스펙 파일이 이미 존재합니다${NC}"
  fi
fi

# 공통 .env 파일 생성/업데이트
if [ ! -f ".env" ]; then
  touch .env
fi

# 버전별 환경변수 파일 설정
if [ "$LEGACY_MODE" = true ]; then
  ENV_FILE=".env.legacy"
else
  ENV_FILE=".env"
fi

# 버전별 .env 파일 생성/업데이트
if [ ! -f "$ENV_FILE" ]; then
  if [ "$LEGACY_MODE" = true ]; then
    echo "# Creditcoin 2.x Legacy 노드 설정" > "$ENV_FILE"
    echo "GIT_TAG=${GIT_TAG}" >> "$ENV_FILE"
  else
    echo "# Creditcoin 3.x 노드 설정" > "$ENV_FILE"
  fi
fi

# 노드 설정 추가 (버전별 환경 변수 파일 사용)
if [ "$UPDATE_MODE" = true ]; then
  # 업데이트 모드: 기존 값 덮어쓰기
  echo -e "${BLUE}환경 변수 업데이트 중... (${ENV_FILE})${NC}"
  
  if [ "$LEGACY_MODE" = true ]; then
    # 2.x 환경 변수 업데이트
    sed -i.bak "s/^P2P_PORT_${ENV_PREFIX}${NODE_NUM}=.*/P2P_PORT_${ENV_PREFIX}${NODE_NUM}=${P2P_PORT}/" "$ENV_FILE"
    sed -i.bak "s/^WS_PORT_${ENV_PREFIX}${NODE_NUM}=.*/WS_PORT_${ENV_PREFIX}${NODE_NUM}=${RPC_PORT}/" "$ENV_FILE"
    if [ -n "$TELEMETRY_NAME" ]; then
      sed -i.bak "s/^TELEMETRY_NAME_${NODE_NUM}=.*/TELEMETRY_NAME_${NODE_NUM}=${TELEMETRY_NAME}/" "$ENV_FILE"
    else
      sed -i.bak "/^TELEMETRY_NAME_${NODE_NUM}=/d" "$ENV_FILE"
    fi
    sed -i.bak "s/^TELEMETRY_ENABLED_${NODE_NUM}=.*/TELEMETRY_ENABLED_${NODE_NUM}=${TELEMETRY_ENABLED}/" "$ENV_FILE"
  else
    # 3.x 환경 변수 업데이트
    sed -i.bak "s/^P2P_PORT_${ENV_PREFIX}${NODE_NUM}=.*/P2P_PORT_${ENV_PREFIX}${NODE_NUM}=${P2P_PORT}/" "$ENV_FILE"
    sed -i.bak "s/^RPC_PORT_${ENV_PREFIX}${NODE_NUM}=.*/RPC_PORT_${ENV_PREFIX}${NODE_NUM}=${RPC_PORT}/" "$ENV_FILE"
    if [ -n "$TELEMETRY_NAME" ]; then
      sed -i.bak "s/^TELEMETRY_NAME_${ENV_PREFIX}${NODE_NUM}=.*/TELEMETRY_NAME_${ENV_PREFIX}${NODE_NUM}=${TELEMETRY_NAME}/" "$ENV_FILE"
    else
      sed -i.bak "/^TELEMETRY_NAME_${ENV_PREFIX}${NODE_NUM}=/d" "$ENV_FILE"
    fi
    sed -i.bak "s/^TELEMETRY_${ENV_PREFIX}${NODE_NUM}=.*/TELEMETRY_${ENV_PREFIX}${NODE_NUM}=${TELEMETRY_ENABLED}/" "$ENV_FILE"
    sed -i.bak "s/^PRUNING_${ENV_PREFIX}${NODE_NUM}=.*/PRUNING_${ENV_PREFIX}${NODE_NUM}=${PRUNING}/" "$ENV_FILE"
  fi
  
  # 백업 파일 삭제
  rm -f "${ENV_FILE}.bak"
else
  # 새 노드 생성 모드: 없는 경우에만 추가
  if [ "$LEGACY_MODE" = true ]; then
    # 2.x 환경 변수
    grep -q "P2P_PORT_${ENV_PREFIX}${NODE_NUM}" "$ENV_FILE" 2>/dev/null || echo "P2P_PORT_${ENV_PREFIX}${NODE_NUM}=${P2P_PORT}" >> "$ENV_FILE"
    grep -q "WS_PORT_${ENV_PREFIX}${NODE_NUM}" "$ENV_FILE" 2>/dev/null || echo "WS_PORT_${ENV_PREFIX}${NODE_NUM}=${RPC_PORT}" >> "$ENV_FILE"
    if [ -n "$TELEMETRY_NAME" ]; then
      grep -q "TELEMETRY_NAME_${NODE_NUM}" "$ENV_FILE" 2>/dev/null || echo "TELEMETRY_NAME_${NODE_NUM}=${TELEMETRY_NAME}" >> "$ENV_FILE"
    fi
    grep -q "TELEMETRY_ENABLED_${NODE_NUM}" "$ENV_FILE" 2>/dev/null || echo "TELEMETRY_ENABLED_${NODE_NUM}=${TELEMETRY_ENABLED}" >> "$ENV_FILE"
  else
    # 3.x 환경 변수
    grep -q "P2P_PORT_${ENV_PREFIX}${NODE_NUM}" "$ENV_FILE" 2>/dev/null || echo "P2P_PORT_${ENV_PREFIX}${NODE_NUM}=${P2P_PORT}" >> "$ENV_FILE"
    grep -q "RPC_PORT_${ENV_PREFIX}${NODE_NUM}" "$ENV_FILE" 2>/dev/null || echo "RPC_PORT_${ENV_PREFIX}${NODE_NUM}=${RPC_PORT}" >> "$ENV_FILE"
    if [ -n "$TELEMETRY_NAME" ]; then
      grep -q "TELEMETRY_NAME_${ENV_PREFIX}${NODE_NUM}" "$ENV_FILE" 2>/dev/null || echo "TELEMETRY_NAME_${ENV_PREFIX}${NODE_NUM}=${TELEMETRY_NAME}" >> "$ENV_FILE"
    fi
    grep -q "TELEMETRY_${ENV_PREFIX}${NODE_NUM}" "$ENV_FILE" 2>/dev/null || echo "TELEMETRY_${ENV_PREFIX}${NODE_NUM}=${TELEMETRY_ENABLED}" >> "$ENV_FILE"
    grep -q "PRUNING_${ENV_PREFIX}${NODE_NUM}" "$ENV_FILE" 2>/dev/null || echo "PRUNING_${ENV_PREFIX}${NODE_NUM}=${PRUNING}" >> "$ENV_FILE"
  fi
fi

# Docker 이미지 빌드 (버전별 통합 로직)
if [ "$UPDATE_MODE" = false ]; then
  # 이미지가 존재하는지 확인
  if [ "$LEGACY_MODE" = true ]; then
    IMAGE_CHECK_NAME="creditcoin2"
  else
    IMAGE_CHECK_NAME="creditcoin3"
  fi
  
  if ! docker images | grep -q "$IMAGE_CHECK_NAME" | grep -q "${GIT_TAG}"; then
    echo -e "${YELLOW}이미지 ${IMAGE_NAME}가 존재하지 않습니다. 새로 빌드합니다...${NC}"
    
    # Dockerfile 생성 (파일이 없는 경우)
    if [ ! -f "$DOCKERFILE_NAME" ]; then
      echo -e "${BLUE}${DOCKERFILE_NAME}이 없으므로 생성합니다...${NC}"
      
      if [ "$LEGACY_MODE" = true ]; then
        # 2.x Dockerfile.legacy 생성
        cat > $DOCKERFILE_NAME << 'EODF'
FROM ubuntu:24.04

# 필요한 패키지 설치
RUN apt update && apt install -y \
    cmake \
    pkg-config \
    libssl-dev \
    git \
    build-essential \
    clang \
    libclang-dev \
    curl \
    protobuf-compiler

# 러스트 설치
RUN curl https://sh.rustup.rs/ -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# 러스트 업데이트 (nightly-2023-05-23)
RUN rustup update nightly-2023-05-23
RUN rustup default nightly-2023-05-23

# substrate-contracts-node 패치 적용
RUN rustup target add wasm32-unknown-unknown --toolchain nightly-2023-05-23

# 소스코드 클론 및 빌드
WORKDIR /root
RUN git clone https://github.com/gluwa/creditcoin.git
WORKDIR /root/creditcoin
RUN git fetch --all --tags
ARG GIT_TAG
RUN git checkout ${GIT_TAG}
RUN cargo build --release

# 시작 스크립트 생성
RUN echo '#!/bin/bash \n\
PUBLIC_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || curl -s https://icanhazip.com) \n\
echo "Using IP address: $PUBLIC_IP" \n\
\n\
# 텔레메트리 설정 결정 \n\
if [ "${TELEMETRY_ENABLED}" == "true" ]; then \n\
  TELEMETRY_OPTS="" \n\
else \n\
  TELEMETRY_OPTS="--no-telemetry" \n\
fi \n\
\n\
/root/creditcoin/target/release/creditcoin-node \
  --validator \
  ${TELEMETRY_NAME:+--name \"$TELEMETRY_NAME\"} \
  --telemetry-url "wss://telemetry.creditcoin.network/submit/ 0" \
  $TELEMETRY_OPTS \
  --bootnodes "/dns4/cc-bootnode.creditcoin.network/tcp/30333/p2p/12D3KooWAEgDL4ufKjWesaErtJZmcqrJAkUvjUJbJmSCCuH4uGjp" \
  --public-addr "/dns4/$PUBLIC_IP/tcp/${P2P_PORT}" \
  --chain mainnet \
  --base-path /root/data \
  --port ${P2P_PORT} \
  --ws-port ${WS_PORT}' > /start.sh

RUN chmod +x /start.sh

# 데이터 디렉토리 생성
RUN mkdir -p /root/data
VOLUME ["/root/data"]

# 시작 명령어
ENTRYPOINT ["/start.sh"]
EODF
      else
        # 3.x Dockerfile 생성 (기존 로직)
        cat > $DOCKERFILE_NAME << 'EODF'
FROM ubuntu:24.04

# 필요한 패키지 설치
RUN apt update && apt install -y \
    cmake \
    pkg-config \
    libssl-dev \
    git \
    git-lfs \
    build-essential \
    clang \
    libclang-dev \
    curl \
    protobuf-compiler

# 러스트 설치
RUN curl https://sh.rustup.rs/ -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# 러스트 업데이트 (nightly)
RUN rustup update nightly
RUN rustup default nightly

# Git LFS 설치 및 초기화
RUN git lfs install

# 소스코드 클론 및 빌드
WORKDIR /root
RUN git clone https://github.com/gluwa/creditcoin3
WORKDIR /root/creditcoin3
RUN git fetch --all --tags
ARG GIT_TAG
RUN git checkout ${GIT_TAG}
RUN git lfs pull
RUN cargo build --release

# 시작 스크립트 생성
RUN echo '#!/bin/bash \n\
PUBLIC_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || curl -s https://icanhazip.com) \n\
echo "Using IP address: $PUBLIC_IP" \n\
# Ed25519 키 확인 \n\
mkdir -p /root/data/chains/creditcoin3/network \n\
if [ ! -s /root/data/chains/creditcoin3/network/secret_ed25519 ]; then \n\
  echo "Ed25519 키가 없거나 비어있어서 새로 생성합니다." \n\
  dd if=/dev/urandom of=/root/data/chains/creditcoin3/network/secret_ed25519 bs=32 count=1 \n\
fi \n\
\n\
# 텔레메트리 설정 결정 \n\
if [ "${TELEMETRY_ENABLED}" == "true" ]; then \n\
  TELEMETRY_OPTS="" \n\
else \n\
  TELEMETRY_OPTS="--no-telemetry" \n\
fi \n\
\n\
/root/creditcoin3/target/release/creditcoin3-node \
  --validator \
  ${TELEMETRY_NAME:+--name \"$TELEMETRY_NAME\"} \
  --prometheus-external \
  --telemetry-url "wss://telemetry.creditcoin.network/submit/ 0" \
  $TELEMETRY_OPTS \
  --bootnodes "/dns4/cc3-bootnode.creditcoin.network/tcp/30333/p2p/12D3KooWLGyvbdQ3wTGjRAEueFsDnstZnV8fN3iyPTmHeyswSPGy" \
  --public-addr "/dns4/$PUBLIC_IP/tcp/${P2P_PORT}" \
  --chain /root/data/chainspecs/mainnetSpecRaw.json \
  --base-path /root/data \
  --port ${P2P_PORT} \
  --rpc-port ${RPC_PORT} \
  $([ "${PRUNING}" != "0" ] && echo "--pruning=${PRUNING}" || echo "")' > /start.sh

RUN chmod +x /start.sh

# 데이터 디렉토리 생성
RUN mkdir -p /root/data/chainspecs
VOLUME ["/root/data"]

# 시작 명령어
ENTRYPOINT ["/start.sh"]
EODF
      fi
      echo -e "${GREEN}${DOCKERFILE_NAME} 생성 완료${NC}"
    fi
    
    # 이미지 빌드 (버전별로 한 번만)
    echo -e "${BLUE}$([ "$LEGACY_MODE" = true ] && echo "Creditcoin2" || echo "Creditcoin3") 이미지 ${IMAGE_NAME} 빌드 중...${NC}"
    echo -e "${YELLOW}이 과정은 수십 분 정도 소요될 수 있습니다. 기다려 주세요...${NC}"
    docker build --build-arg GIT_TAG=${GIT_TAG} -t ${IMAGE_NAME} -f ${DOCKERFILE_NAME} .
    
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}이미지 빌드 완료${NC}"
    else
      echo -e "${RED}이미지 빌드 실패${NC}"
      exit 1
    fi
  else
    echo -e "${GREEN}이미지 ${IMAGE_NAME}가 이미 존재합니다. 빌드를 건너뜁니다.${NC}"
  fi
fi

# Docker Compose 파일 생성/업데이트
if [ "$LEGACY_MODE" = true ]; then
  # 2.x: docker-compose-legacy.yml 파일 처리
  if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
    echo -e "${BLUE}${DOCKER_COMPOSE_FILE} 파일이 없으므로 생성합니다...${NC}"
    cat > "$DOCKER_COMPOSE_FILE" << 'EODC'
name: creditcoin-legacy

x-node-defaults: &node-defaults
  restart: unless-stopped
  env_file:
    - .env
    - .env.legacy

services:
  # 2.x 레거시 노드들이 여기에 추가됩니다

networks:
  creditnet2:
    driver: bridge
EODC
    echo -e "${GREEN}${DOCKER_COMPOSE_FILE} 생성 완료${NC}"
  fi
else
  # 3.x: docker-compose.yml 파일 처리
  if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
    echo -e "${BLUE}${DOCKER_COMPOSE_FILE} 파일이 없으므로 생성합니다...${NC}"
    cat > "$DOCKER_COMPOSE_FILE" << 'EOSVC'
name: creditcoin-nodes

x-node-defaults: &node-defaults
  restart: unless-stopped
  env_file:
    - .env

services:
  # 서비스들이 여기에 추가됩니다

networks:
  creditnet:
    driver: bridge
EOSVC
    echo -e "${GREEN}${DOCKER_COMPOSE_FILE} 생성 완료${NC}"
  fi
fi

# 노드 설정을 Docker Compose 파일에 추가
NODE_SERVICE="${NODE_PREFIX}${NODE_NUM}"
if grep -q "${NODE_SERVICE}:" "$DOCKER_COMPOSE_FILE" 2>/dev/null; then
  echo -e "${YELLOW}${NODE_SERVICE}은 이미 ${DOCKER_COMPOSE_FILE}에 존재합니다.${NC}"
else
  echo -e "${BLUE}${DOCKER_COMPOSE_FILE}에 ${NODE_SERVICE} 추가 중...${NC}"
  
  # networks 부분을 임시로 저장
  NETWORKS_BLOCK=$(sed -n '/^networks:/,$p' "$DOCKER_COMPOSE_FILE")
  
  # networks 부분 제거한 파일 생성
  sed '/^networks:/,$d' "$DOCKER_COMPOSE_FILE" > "${DOCKER_COMPOSE_FILE}.tmp"
  
  if [ "$LEGACY_MODE" = true ]; then
    # 2.x 노드 설정 추가
    cat >> "${DOCKER_COMPOSE_FILE}.tmp" << EOF
  ${NODE_SERVICE}:
    <<: *node-defaults
    image: ${IMAGE_NAME}
    container_name: ${NODE_SERVICE}
    volumes:
      - ./data/${GIT_TAG}/chainspecs:/root/data/chainspecs
      - ./${NODE_SERVICE}/data:/root/data
    ports:
      - "\${P2P_PORT_NODE${NODE_NUM}:-${P2P_PORT}}:\${P2P_PORT_NODE${NODE_NUM}:-${P2P_PORT}}"
      - "\${WS_PORT_NODE${NODE_NUM}:-${WS_PORT}}:\${WS_PORT_NODE${NODE_NUM}:-${WS_PORT}}"
    environment:
      - TELEMETRY_NAME=\${TELEMETRY_NAME_NODE${NODE_NUM}:-}
      - P2P_PORT=\${P2P_PORT_NODE${NODE_NUM}:-${P2P_PORT}}
      - WS_PORT=\${WS_PORT_NODE${NODE_NUM}:-${WS_PORT}}
      - TELEMETRY_ENABLED=\${TELEMETRY_NODE${NODE_NUM}:-${TELEMETRY_ENABLED}}
    networks:
      ${NETWORK_NAME}:

EOF
  else
    # 3.x 노드 설정 추가
    cat >> "${DOCKER_COMPOSE_FILE}.tmp" << EOF
  ${NODE_SERVICE}:
    <<: *node-defaults
    image: ${IMAGE_NAME}
    container_name: ${NODE_SERVICE}
    volumes:
      - ./data/${GIT_TAG}/chainspecs:/root/data/chainspecs
      - ./${NODE_SERVICE}/data:/root/data
    ports:
      - "\${P2P_PORT_${ENV_PREFIX}${NODE_NUM}}:\${P2P_PORT_${ENV_PREFIX}${NODE_NUM}}"
      - "\${RPC_PORT_${ENV_PREFIX}${NODE_NUM}}:\${RPC_PORT_${ENV_PREFIX}${NODE_NUM}}"
    environment:
      - NODE_ID=${NODE_NUM}
      - TELEMETRY_NAME=\${TELEMETRY_NAME_${ENV_PREFIX}${NODE_NUM}:-}
      - P2P_PORT=\${P2P_PORT_${ENV_PREFIX}${NODE_NUM}}
      - RPC_PORT=\${RPC_PORT_${ENV_PREFIX}${NODE_NUM}}
      - TELEMETRY_ENABLED=\${TELEMETRY_${ENV_PREFIX}${NODE_NUM}}
      - PRUNING=\${PRUNING_${ENV_PREFIX}${NODE_NUM}}
      - GIT_TAG=${GIT_TAG}
    networks:
      ${NETWORK_NAME}:

EOF
  fi
  
  # networks 부분 다시 추가
  echo "$NETWORKS_BLOCK" >> "${DOCKER_COMPOSE_FILE}.tmp"
  
  # 임시 파일을 원래 파일로 이동
  mv "${DOCKER_COMPOSE_FILE}.tmp" "$DOCKER_COMPOSE_FILE"
  
  echo -e "${GREEN}${NODE_SERVICE} 설정 추가 완료${NC}"
fi

echo -e "${BLUE}환경 변수가 ${ENV_FILE} 파일에 추가되었습니다.${NC}"
if [ -n "$TELEMETRY_NAME" ]; then
  echo -e "${GREEN}노드 ${NODE_PREFIX}${NODE_NUM} (텔레메트리: ${TELEMETRY_NAME}) 설정이 완료되었습니다!${NC}"
else
  echo -e "${GREEN}노드 ${NODE_PREFIX}${NODE_NUM} 설정이 완료되었습니다!${NC}"
fi
echo ""

if [ "$UPDATE_MODE" = true ]; then
  echo -e "${YELLOW}업데이트 완료! 다음 단계:${NC}"
  echo -e "${GREEN}변경된 설정을 적용하려면 컨테이너를 재시작하세요:${NC}"
  echo -e "${BLUE}docker compose -p creditcoin$([ "$LEGACY_MODE" = true ] && echo "2" || echo "3") restart ${NODE_PREFIX}${NODE_NUM}${NC}"
else
  echo -e "${YELLOW}다음 단계:${NC}"
  echo -e "${GREEN}1. Docker 이미지 빌드: 완료 ✅${NC}"
  echo -e "${GREEN}2. Docker Compose 설정: 완료 ✅${NC}"
  echo ""
  echo -e "${BLUE}노드를 시작합니다...${NC}"
  
  # 프로젝트 이름 설정
  PROJECT_NAME="creditcoin$([ "$LEGACY_MODE" = true ] && echo "2" || echo "3")"
  
  # 버전별 docker-compose 파일 지정
  if [ "$LEGACY_MODE" = true ]; then
    COMPOSE_FILE_FLAG="-f docker-compose-legacy.yml"
  else
    COMPOSE_FILE_FLAG="-f docker-compose.yml"
  fi
  
  # 노드 시작
  docker compose $COMPOSE_FILE_FLAG -p $PROJECT_NAME up -d ${NODE_PREFIX}${NODE_NUM}

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}노드가 성공적으로 시작되었습니다.${NC}"
    echo ""
    echo -e "${YELLOW}실행 중인 노드 확인: ${GREEN}docker ps${NC}"
    echo -e "${YELLOW}로그 확인: ${GREEN}docker logs -f ${NODE_PREFIX}${NODE_NUM}${NC}"
    echo -e "${YELLOW}노드 상태 요약: ${GREEN}status${NC} (유틸리티 스크립트 로드 후)${NC}"
    echo ""
    echo -e "${BLUE}💡 mclient가 새 노드를 인지하도록 재시작: ${GREEN}mrestart${NC}"
  else
    echo -e "${RED}노드 시작에 실패했습니다. 로그를 확인하세요.${NC}"
  fi
fi

echo -e "${BLUE}----------------------------------------------------${NC}"