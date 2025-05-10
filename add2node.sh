#!/bin/bash

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
  echo "  -v, --version      노드 버전 (기본값: 2.230.2-mainnet)"
  echo "  -t, --telemetry    텔레메트리 활성화 (기본값: 비활성화)"
  echo "  -n, --name         노드 이름 (기본값: Node<번호>)"
  echo ""
  echo "사용 예시:"
  echo "  ./add2node-mac.sh 0                        # 기본 설정으로 노드 생성"
  echo "  ./add2node-mac.sh 1 -v 2.230.2-mainnet     # 특정 버전으로 노드 생성"
  echo "  ./add2node-mac.sh 2 -t                     # 텔레메트리 활성화한 노드 생성"
  echo "  ./add2node-mac.sh 3 -n MyValidator         # 지정한 이름으로 노드 생성"
  echo "  ./add2node-mac.sh 4 -v 2.230.2-mainnet -t -n MainNode  # 모든 옵션 지정"
  echo ""
  echo "버전 정보:"
  echo "  2.230.2-mainnet: Creditcoin 2.0 레거시"
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

# 기본값 설정
GIT_TAG="2.230.2-mainnet"
TELEMETRY_ENABLED="false"
NODE_NAME="Node$NODE_NUM"

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
echo -e "${GREEN}- 버전: $GIT_TAG (Creditcoin 2.0 레거시)${NC}"
echo -e "${GREEN}- 노드 번호: $NODE_NUM${NC}"
echo -e "${GREEN}- 노드 이름: $NODE_NAME${NC}"
echo -e "${GREEN}- 텔레메트리: $([ "$TELEMETRY_ENABLED" == "true" ] && echo "활성화" || echo "비활성화")${NC}"

# 노드 데이터 디렉토리 생성
mkdir -p ./node${NODE_NUM}/data

# 포트 설정
BASE_P2P_PORT=30333
BASE_WS_PORT=33970
P2P_PORT=$((BASE_P2P_PORT + $NODE_NUM))
WS_PORT=$((BASE_WS_PORT + $NODE_NUM))

# .env 파일 업데이트 또는 생성
SERVER_ID=$(grep SERVER_ID .env 2>/dev/null | cut -d= -f2 || echo "dock")
if [ ! -f ".env" ]; then
  echo "SERVER_ID=${SERVER_ID}" > .env
fi

# 노드 설정 추가 (macOS 호환 방식)
if ! grep -q "P2P_PORT_NODE${NODE_NUM}" .env 2>/dev/null; then
  echo "" >> .env
  echo "# 노드 ${NODE_NUM} 설정 (creditcoin 2.0)" >> .env
  echo "P2P_PORT_NODE${NODE_NUM}=${P2P_PORT}" >> .env
  echo "WS_PORT_NODE${NODE_NUM}=${WS_PORT}" >> .env
  echo "NODE_NAME_${NODE_NUM}=${NODE_NAME}" >> .env
  echo "TELEMETRY_ENABLED_${NODE_NUM}=${TELEMETRY_ENABLED}" >> .env
fi

# 이미지 이름 설정
IMAGE_NAME="creditcoin2:${GIT_TAG}"

# 이미지가 존재하는지 확인
if ! docker images | grep -q "creditcoin2" | grep -q "${GIT_TAG}"; then
  echo -e "${YELLOW}이미지 ${IMAGE_NAME}가 존재하지 않습니다. 새로 빌드합니다...${NC}"

  # 도커파일이 없으면 생성 (최초 한 번만)
  if [ ! -f "Dockerfile.legacy" ]; then
    echo -e "${BLUE}Dockerfile.legacy가 없으므로 생성합니다...${NC}"
    cat > Dockerfile.legacy << 'EODF'
FROM ubuntu:22.04

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

# 러스트 버전 설정 - 작동 중인 노드와 동일한 버전 사용
RUN rustup toolchain install nightly-2023-04-16
RUN rustup default nightly-2023-04-16
RUN rustup target add wasm32-unknown-unknown --toolchain nightly-2023-04-16

# Git LFS 설치 및 초기화
RUN git lfs install

# 소스코드 클론 및 빌드 (creditcoin 2.0)
WORKDIR /root
RUN git clone https://github.com/gluwa/creditcoin
WORKDIR /root/creditcoin
RUN git fetch --all --tags
ARG GIT_TAG
RUN git checkout ${GIT_TAG}

# Substrate 의존성 해결을 위한 .cargo/config 설정
RUN mkdir -p /root/.cargo
RUN echo '[patch."https://github.com/paritytech/substrate.git"]' > /root/.cargo/config && \
    echo 'pallet-balances = { git = "https://github.com/gluwa/substrate.git", branch = "pos-keep-history-polkadot-v0.9.41" }' >> /root/.cargo/config && \
    echo 'sp-core = { git = "https://github.com/gluwa/substrate.git", branch = "pos-keep-history-polkadot-v0.9.41" }' >> /root/.cargo/config && \
    echo 'sp-runtime = { git = "https://github.com/gluwa/substrate.git", branch = "pos-keep-history-polkadot-v0.9.41" }' >> /root/.cargo/config && \
    echo 'sp-io = { git = "https://github.com/gluwa/substrate.git", branch = "pos-keep-history-polkadot-v0.9.41" }' >> /root/.cargo/config

# 빌드 실행
RUN RUSTFLAGS="-C target-cpu=native" cargo build --release

# 시작 스크립트 생성
RUN echo '#!/bin/bash \n\
# 외부 IP 가져오기 (여러 방법으로 시도) \n\
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
  --name ${NODE_NAME} \
  --prometheus-external \
  --telemetry-url "wss://telemetry.creditcoin.network/submit/ 0" \
  $TELEMETRY_OPTS \
  --bootnodes "/dns4/bootnode.creditcoin.network/tcp/30333/p2p/12D3KooWAEgDL126EUFxFfdQKiUhmx3BJPdszQHu9PsYsLCuavhb" "/dns4/bootnode2.creditcoin.network/tcp/30333/p2p/12D3KooWSQye3uN3bZQRRC4oZbpiAZXkP2o5UZh6S8pqyh24bF3k" "/dns4/bootnode3.creditcoin.network/tcp/30333/p2p/12D3KooWFrsEZ2aSfiigAxs6ir2kU6en4BewotyCXPhrJ7T1AzjN" \
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
    echo -e "${GREEN}Dockerfile.legacy 생성 완료${NC}"
  fi

  # 이미지 빌드 (버전별로 한 번만)
  echo -e "${BLUE}Creditcoin2 이미지 ${IMAGE_NAME} 빌드 중...${NC}"
  echo -e "${YELLOW}이 과정은 수십 분 정도 소요될 수 있습니다. 기다려 주세요...${NC}"
  docker build --build-arg GIT_TAG=${GIT_TAG} -t ${IMAGE_NAME} -f Dockerfile.legacy .
  
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}이미지 빌드 완료${NC}"
  else
    echo -e "${RED}이미지 빌드 실패${NC}"
    exit 1
  fi
else
  echo -e "${GREEN}이미지 ${IMAGE_NAME}가 이미 존재합니다. 빌드를 건너뜁니다.${NC}"
fi

# docker-compose-legacy.yml 파일에 새 노드 추가
if grep -q "node${NODE_NUM}:" docker-compose-legacy.yml 2>/dev/null; then
  echo -e "${YELLOW}node${NODE_NUM}은 이미 docker-compose-legacy.yml에 존재합니다.${NC}"
else
  # 기존 docker-compose-legacy.yml 파일이 없으면 생성
  if [ ! -f "docker-compose-legacy.yml" ]; then
    echo -e "${BLUE}docker-compose-legacy.yml 파일이 없으므로 생성합니다...${NC}"
    cat > docker-compose-legacy.yml << 'EODC'
services:

networks:
  creditnet2:
    driver: bridge
EODC
    echo -e "${GREEN}docker-compose-legacy.yml 생성 완료${NC}"
  fi

  # 수정된 부분: docker-compose-legacy.yml 파일 수정 (중복 networks 문제 해결)
  echo -e "${BLUE}node${NODE_NUM} 설정 추가 중...${NC}"
  
  # networks 부분을 임시로 저장
  NETWORKS_BLOCK=$(sed -n '/^networks:/,$p' docker-compose-legacy.yml)
  
  # networks 부분 제거한 파일 생성
  sed '/^networks:/,$d' docker-compose-legacy.yml > docker-compose-legacy.yml.tmp
  
  # 노드 설정 추가
  cat >> docker-compose-legacy.yml.tmp << EOF
  node${NODE_NUM}:
    image: ${IMAGE_NAME}
    container_name: node${NODE_NUM}
    volumes:
      - ./node${NODE_NUM}/data:/root/data
    ports:
      - "\${P2P_PORT_NODE${NODE_NUM}:-${P2P_PORT}}:\${P2P_PORT_NODE${NODE_NUM}:-${P2P_PORT}}"
      - "\${WS_PORT_NODE${NODE_NUM}:-${WS_PORT}}:\${WS_PORT_NODE${NODE_NUM}:-${WS_PORT}}"
    environment:
      - SERVER_ID=\${SERVER_ID:-dock}
      - NODE_NAME=\${NODE_NAME_${NODE_NUM}:-${NODE_NAME}}
      - P2P_PORT=\${P2P_PORT_NODE${NODE_NUM}:-${P2P_PORT}}
      - WS_PORT=\${WS_PORT_NODE${NODE_NUM}:-${WS_PORT}}
      - TELEMETRY_ENABLED=\${TELEMETRY_ENABLED_${NODE_NUM}:-${TELEMETRY_ENABLED}}
    restart: unless-stopped
    networks:
      creditnet2:

EOF
  
  # networks 부분 다시 추가
  echo "$NETWORKS_BLOCK" >> docker-compose-legacy.yml.tmp
  
  # 임시 파일을 원래 파일로 이동
  mv docker-compose-legacy.yml.tmp docker-compose-legacy.yml
  
  echo -e "${GREEN}node${NODE_NUM} 설정 추가 완료${NC}"
fi

echo -e "${BLUE}----------------------------------------------------${NC}"
echo -e "${GREEN}Creditcoin 2.0 레거시 노드 ${NODE_NUM}이 '${NODE_NAME}' 이름으로 설정되었습니다.${NC}"
echo -e "${BLUE}----------------------------------------------------${NC}"
echo ""
echo -e "${YELLOW}사용 가능한 버전:${NC}"
echo -e "${GREEN}  - 2.230.2-mainnet (레거시 버전) - Creditcoin 2.0 안정화 버전${NC}"
echo ""
echo -e "${BLUE}노드를 시작합니다...${NC}"
docker compose -p creditcoin2 -f docker-compose-legacy.yml up -d node${NODE_NUM}

if [ $? -eq 0 ]; then
  echo -e "${GREEN}노드가 성공적으로 시작되었습니다.${NC}"
  echo ""
  echo -e "${YELLOW}실행 중인 노드 확인: ${GREEN}docker ps${NC}"
  echo -e "${YELLOW}로그 확인: ${GREEN}docker logs -f node${NODE_NUM}${NC}"
  echo -e "${YELLOW}노드 상태 요약: ${GREEN}status${NC} (유틸리티 스크립트 로드 후)${NC}"
else
  echo -e "${RED}노드 시작에 실패했습니다. 로그를 확인하세요.${NC}"
fi
echo -e "${BLUE}----------------------------------------------------${NC}"