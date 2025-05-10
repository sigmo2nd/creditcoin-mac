#!/bin/bash
# add3node.sh - macOS용 Creditcoin 3.0 노드 추가 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 도움말 표시 함수
show_help() {
  echo "사용법: $0 <노드번호> [옵션]"
  echo ""
  echo "필수 매개변수:"
  echo "  <노드번호>         생성할 노드의 번호 (예: 0, 1, 2, ...)"
  echo ""
  echo "옵션:"
  echo "  -v, --version      노드 버전 (기본값: 3.39.0-mainnet)"
  echo "  -t, --telemetry    텔레메트리 활성화 (기본값: 비활성화)"
  echo "  -n, --name         노드 이름 (기본값: 3Node<번호>)"
  echo "  -p, --pruning      프루닝 값 설정 (기본값: 0, 0일 경우 옵션 추가 안함)"
  echo ""
  echo "사용 예시:"
  echo "  ./add3node.sh 0                      # 기본 설정으로 노드 생성"
  echo "  ./add3node.sh 1 -v 3.32.0-mainnet    # 안정 버전으로 노드 생성"
  echo "  ./add3node.sh 2 -t                   # 텔레메트리 활성화한 노드 생성"
  echo "  ./add3node.sh 3 -n ValidatorA        # 지정한 이름으로 노드 생성"
  echo "  ./add3node.sh 4 -p 1000              # 프루닝 값 1000으로 설정"
  echo ""
  echo "버전 정보:"
  echo "  3.39.0-mainnet: 최신 메인넷 버전 (기본값)"
  echo "  3.32.0-mainnet: 안정 메인넷 버전"
  echo ""
}

# 매개변수가 없으면 도움말 표시
if [ $# -lt 1 ]; then
  show_help
  exit 1
fi

# Docker 실행 상태 확인
if ! docker info &> /dev/null; then
  echo -e "${RED}오류: Docker Desktop이 실행 중이 아닙니다.${NC}"
  echo -e "${YELLOW}Docker Desktop을 실행한 후 다시 시도하세요.${NC}"
  exit 1
fi

# 첫 번째 매개변수는 노드 번호
NODE_NUM=$1
shift

# 기본값 설정 - 3.39.0-mainnet으로 변경
GIT_TAG="3.39.0-mainnet"
TELEMETRY_ENABLED="false"
NODE_NAME="3Node$NODE_NUM"
PRUNING="0"

# 옵션 파싱
while [ $# -gt 0 ]; do
  case "$1" in
    -v|--version)
      GIT_TAG="$2"
      shift 2
      ;;
    -t|--telemetry)
      TELEMETRY_ENABLED="true"
      shift
      ;;
    -n|--name)
      NODE_NAME="$2"
      shift 2
      ;;
    -p|--pruning)
      PRUNING="$2"
      shift 2
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

echo -e "${BLUE}사용할 설정:${NC}"
echo -e "${GREEN}- 노드 번호: $NODE_NUM${NC}"
echo -e "${GREEN}- 노드 이름: $NODE_NAME${NC}"
echo -e "${GREEN}- 텔레메트리: $([ "$TELEMETRY_ENABLED" == "true" ] && echo "활성화" || echo "비활성화")${NC}"
echo -e "${GREEN}- 버전: $GIT_TAG${NC}"
echo -e "${GREEN}- 프루닝: $PRUNING $([ "$PRUNING" == "0" ] && echo "(비활성화)" || echo "")${NC}"

# 현재 작업 디렉토리 저장
CURRENT_DIR=$(pwd)
SERVER_ID=$(grep SERVER_ID .env 2>/dev/null | cut -d= -f2 || echo "dock")

# 노드 데이터 디렉토리 생성
mkdir -p ./3node${NODE_NUM}/data

# 네트워크 키 디렉토리 생성
mkdir -p ./3node${NODE_NUM}/data/chains/creditcoin3/network

# 버전별 체인스펙 디렉토리 생성
mkdir -p ./data/${GIT_TAG}/chainspecs

# 유효한 Ed25519 네트워크 키 생성 (32바이트 랜덤 데이터)
# macOS 호환 버전으로 수정: urandom -> random
dd if=/dev/random of=./3node${NODE_NUM}/data/chains/creditcoin3/network/secret_ed25519 bs=32 count=1 2>/dev/null

# chainspec 파일 다운로드 (없는 경우에만)
if [ ! -f "./data/${GIT_TAG}/chainspecs/mainnetSpecRaw.json" ]; then
  echo -e "${BLUE}${GIT_TAG} 버전의 체인스펙 파일 다운로드 중...${NC}"
  
  # 임시 디렉토리 생성 (macOS 호환)
  TEMP_DIR=$(mktemp -d -t creditcoin3-chainspec-XXXXXX)
  cd "$TEMP_DIR"
  
  # Git 저장소 클론 및 체인스펙 파일 복사
  echo -e "${YELLOW}Git 저장소 클론 중...${NC}"
  git clone https://github.com/gluwa/creditcoin3.git
  cd creditcoin3
  git checkout ${GIT_TAG}
  
  # git-lfs가 설치되어 있는지 확인
  if command -v git-lfs &> /dev/null; then
    git lfs pull
  else
    echo -e "${RED}경고: git-lfs가 설치되어 있지 않습니다. setup.sh를 먼저 실행하세요.${NC}"
  fi
  
  if [ -f "chainspecs/mainnetSpecRaw.json" ]; then
    mkdir -p "${CURRENT_DIR}/data/${GIT_TAG}/chainspecs/"
    cp "chainspecs/mainnetSpecRaw.json" "${CURRENT_DIR}/data/${GIT_TAG}/chainspecs/"
    echo -e "${GREEN}체인스펙 파일 다운로드 완료${NC}"
  else
    echo -e "${RED}오류: 체인스펙 파일을 찾을 수 없습니다${NC}"
    cd "$CURRENT_DIR"
    rm -rf "$TEMP_DIR"
    exit 1
  fi
  
  # 원래 디렉토리로 복귀 및 정리
  cd "$CURRENT_DIR"
  rm -rf "$TEMP_DIR"
else
  echo -e "${GREEN}체인스펙 파일이 이미 존재합니다${NC}"
fi

# .env 파일에 새 노드 설정 추가
P2P_PORT=$((30340 + $NODE_NUM))
RPC_PORT=$((33980 + $NODE_NUM))

# .env 파일 업데이트 또는 생성
if [ ! -f ".env" ]; then
  echo "SERVER_ID=${SERVER_ID}" > .env
  echo "GIT_TAG=${GIT_TAG}" >> .env
fi

# 노드 설정 추가 (macOS 호환 방식)
grep -q "P2P_PORT_3NODE${NODE_NUM}" .env 2>/dev/null || echo "P2P_PORT_3NODE${NODE_NUM}=${P2P_PORT}" >> .env
grep -q "RPC_PORT_3NODE${NODE_NUM}" .env 2>/dev/null || echo "RPC_PORT_3NODE${NODE_NUM}=${RPC_PORT}" >> .env
grep -q "NODE_NAME_3NODE${NODE_NUM}" .env 2>/dev/null || echo "NODE_NAME_3NODE${NODE_NUM}=${NODE_NAME}" >> .env
grep -q "TELEMETRY_3NODE${NODE_NUM}" .env 2>/dev/null || echo "TELEMETRY_3NODE${NODE_NUM}=${TELEMETRY_ENABLED}" >> .env
grep -q "PRUNING_3NODE${NODE_NUM}" .env 2>/dev/null || echo "PRUNING_3NODE${NODE_NUM}=${PRUNING}" >> .env

# 이미지 이름 설정
IMAGE_NAME="creditcoin3:${GIT_TAG}"

# 이미지가 존재하는지 확인
if ! docker images | grep -q "creditcoin3" | grep -q "${GIT_TAG}"; then
  echo -e "${YELLOW}이미지 ${IMAGE_NAME}가 존재하지 않습니다. 새로 빌드합니다...${NC}"
  
  # Dockerfile 생성 (파일이 없는 경우)
  if [ ! -f "Dockerfile" ]; then
    echo -e "${BLUE}Dockerfile이 없으므로 생성합니다...${NC}"
    cat > Dockerfile << 'EODF'
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
  --name ${NODE_NAME} \
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
    echo -e "${GREEN}Dockerfile 생성 완료${NC}"
  fi
  
  # 이미지 빌드 (버전별로 한 번만)
  echo -e "${BLUE}Creditcoin3 이미지 ${IMAGE_NAME} 빌드 중...${NC}"
  echo -e "${YELLOW}이 과정은 수십 분 정도 소요될 수 있습니다. 기다려 주세요...${NC}"
  docker build --build-arg GIT_TAG=${GIT_TAG} -t ${IMAGE_NAME} .
  
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}이미지 빌드 완료${NC}"
  else
    echo -e "${RED}이미지 빌드 실패${NC}"
    exit 1
  fi
else
  echo -e "${GREEN}이미지 ${IMAGE_NAME}가 이미 존재합니다. 빌드를 건너뜁니다.${NC}"
fi

# docker-compose.yml 파일 생성 (파일이 없는 경우)
if [ ! -f "docker-compose.yml" ]; then
  echo -e "${BLUE}docker-compose.yml 파일이 없으므로 생성합니다...${NC}"
  cat > docker-compose.yml << 'EOSVC'
x-node-defaults: &node-defaults
  restart: unless-stopped

services:
  # 서비스들이 여기에 추가됩니다

networks:
  creditnet:
    driver: bridge
EOSVC
  echo -e "${GREEN}docker-compose.yml 생성 완료${NC}"
fi

# 노드 이름 생성
node="3node${NODE_NUM}"

# docker-compose.yml 파일에 새 노드 추가
if grep -q "${node}:" docker-compose.yml 2>/dev/null; then
  echo -e "${YELLOW}${node}은 이미 docker-compose.yml에 존재합니다.${NC}"
else
  echo -e "${BLUE}docker-compose.yml에 ${node} 추가 중...${NC}"
  
  # 수정된 부분: docker-compose.yml 파일 수정 (중복 networks 문제 해결)
  # networks 부분을 임시로 저장
  NETWORKS_BLOCK=$(sed -n '/^networks:/,$p' docker-compose.yml)
  
  # networks 부분 제거한 파일 생성
  sed '/^networks:/,$d' docker-compose.yml > docker-compose.yml.tmp
  
  # 노드 설정 추가
  cat >> docker-compose.yml.tmp << EOF
  ${node}:
    <<: *node-defaults
    image: ${IMAGE_NAME}
    container_name: ${node}
    volumes:
      - ./data/${GIT_TAG}/chainspecs:/root/data/chainspecs
      - ./${node}/data:/root/data
    ports:
      - "\${P2P_PORT_3NODE${NODE_NUM}:-${P2P_PORT}}:\${P2P_PORT_3NODE${NODE_NUM}:-${P2P_PORT}}"
      - "\${RPC_PORT_3NODE${NODE_NUM}:-${RPC_PORT}}:\${RPC_PORT_3NODE${NODE_NUM}:-${RPC_PORT}}"
    environment:
      - SERVER_ID=\${SERVER_ID:-dock}
      - NODE_ID=${NODE_NUM}
      - NODE_NAME=\${NODE_NAME_3NODE${NODE_NUM}:-${NODE_NAME}}
      - P2P_PORT=\${P2P_PORT_3NODE${NODE_NUM}:-${P2P_PORT}}
      - RPC_PORT=\${RPC_PORT_3NODE${NODE_NUM}:-${RPC_PORT}}
      - TELEMETRY_ENABLED=\${TELEMETRY_3NODE${NODE_NUM}:-${TELEMETRY_ENABLED}}
      - PRUNING=\${PRUNING_3NODE${NODE_NUM}:-${PRUNING}}
      - GIT_TAG=${GIT_TAG}
    networks:
      creditnet:

EOF
  
  # networks 부분 다시 추가
  echo "$NETWORKS_BLOCK" >> docker-compose.yml.tmp
  
  # 임시 파일을 원래 파일로 이동
  mv docker-compose.yml.tmp docker-compose.yml
  
  echo -e "${GREEN}${node} 추가 완료${NC}"
fi

echo -e "${BLUE}----------------------------------------------------${NC}"
echo -e "${GREEN}다음 설정으로 ${node}이 생성되었습니다:${NC}"
echo -e "${GREEN}- 노드 이름: ${NODE_NAME}${NC}"
echo -e "${GREEN}- 텔레메트리: $([ "$TELEMETRY_ENABLED" == "true" ] && echo "활성화" || echo "비활성화")${NC}"
echo -e "${GREEN}- 버전: ${GIT_TAG}${NC}"
echo -e "${GREEN}- 프루닝: ${PRUNING} $([ "$PRUNING" == "0" ] && echo "(비활성화)" || echo "")${NC}"
echo -e "${BLUE}----------------------------------------------------${NC}"
echo ""
echo -e "${YELLOW}사용 가능한 버전:${NC}"
echo -e "${GREEN}  - 3.39.0-mainnet (최신 버전) - 기본 설정, 보다 많은 기능 및 업데이트 포함${NC}"
echo -e "${GREEN}  - 3.32.0-mainnet (안정 버전) - 안정성 중시, 메모리 사용 최적화${NC}"
echo ""
echo -e "${BLUE}노드를 시작합니다...${NC}"
docker compose -p creditcoin3 up -d ${node}

if [ $? -eq 0 ]; then
  echo -e "${GREEN}노드가 성공적으로 시작되었습니다.${NC}"
  echo ""
  echo -e "${YELLOW}실행 중인 노드 확인: ${GREEN}docker ps${NC}"
  echo -e "${YELLOW}로그 확인: ${GREEN}docker logs -f ${node}${NC}"
  echo -e "${YELLOW}노드 상태 요약: ${GREEN}status${NC} (유틸리티 스크립트 로드 후)${NC}"
else
  echo -e "${RED}노드 시작에 실패했습니다. 로그를 확인하세요.${NC}"
fi
echo -e "${BLUE}----------------------------------------------------${NC}"