#!/bin/bash
# Creditcoin Docker 유틸리티 함수 (macOS + OrbStack 호환)

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Creditcoin Docker 디렉토리로 이동
cdcd() { cd "$CREDITCOIN_DIR"; }

# Docker Compose 관련 함수들
dcup() {
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: dcup <노드명>${NC}"
    echo -e "${YELLOW}예시: dcup 3node0 또는 dcup node0${NC}"
    return 1
  fi
  
  cd "$CREDITCOIN_DIR"
  
  # 2.x 또는 3.x 노드 구분
  if [[ "$1" =~ ^node[0-9]+$ ]]; then
    echo -e "${BLUE}2.x 레거시 노드 시작: $1${NC}"
    docker compose -f docker-compose-legacy.yml up -d $1
  else
    echo -e "${BLUE}3.x 노드 시작: $1${NC}"
    docker compose up -d $1
  fi
}

dcdown() {
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: dcdown <노드명>${NC}"
    echo -e "${YELLOW}예시: dcdown 3node0 또는 dcdown node0${NC}"
    return 1
  fi
  
  cd "$CREDITCOIN_DIR"
  
  # 2.x 또는 3.x 노드 구분
  if [[ "$1" =~ ^node[0-9]+$ ]]; then
    echo -e "${BLUE}2.x 레거시 노드 중지: $1${NC}"
    docker compose -f docker-compose-legacy.yml down $1
  else
    echo -e "${BLUE}3.x 노드 중지: $1${NC}"
    docker compose down $1
  fi
}

dcrestart() {
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: dcrestart <노드명>${NC}"
    echo -e "${YELLOW}예시: dcrestart 3node0 또는 dcrestart node0${NC}"
    return 1
  fi
  
  cd "$CREDITCOIN_DIR"
  
  # 2.x 또는 3.x 노드 구분
  if [[ "$1" =~ ^node[0-9]+$ ]]; then
    echo -e "${BLUE}2.x 레거시 노드 재시작: $1${NC}"
    docker compose -f docker-compose-legacy.yml restart $1
  else
    echo -e "${BLUE}3.x 노드 재시작: $1${NC}"
    docker compose restart $1
  fi
}

# 기본 Docker 별칭들
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dstats='docker stats'
alias dip='docker ps -q | xargs -n 1 docker inspect --format "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}} => {{.Name}}" | sort'
alias dvols='docker volume ls'
alias dnets='docker network ls'
alias dprune='docker system prune -f'

# OrbStack 특화 별칭들
alias orbui='open -a OrbStack'
alias orbstatus='orb status'
alias orbls='orb ls'
alias orbinfo='orb info'

# 쉘 관련 별칭
if [[ "$SHELL" == *"zsh"* ]]; then
  alias updatesh='source ~/.zshrc'
  alias editsh='open -e ~/.zshrc'
else
  alias updatesh='source ~/.bash_profile'
  alias editsh='open -e ~/.bash_profile'
fi

# Docker 파일 열기 
alias editdc='open -e ${CREDITCOIN_DIR}/docker-compose.yml'
alias editdcl='open -e ${CREDITCOIN_DIR}/docker-compose-legacy.yml'
alias editdcmc='open -e ${CREDITCOIN_DIR}/docker-compose-mclient.yml'
alias editdf='open -e ${CREDITCOIN_DIR}/Dockerfile'
alias editdfl='open -e ${CREDITCOIN_DIR}/Dockerfile.legacy'
alias editenv='open -e ${CREDITCOIN_DIR}/.env'
alias editenvl='open -e ${CREDITCOIN_DIR}/.env.legacy'
alias editenvmc='open -e ${CREDITCOIN_DIR}/.env.mclient'

# Docker 컨테이너 관리
drestart() { 
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: drestart <컨테이너명>${NC}"
    return 1
  fi
  
  # 2.x와 3.x 노드 구분하여 docker-compose로 재생성
  if [[ "$1" =~ ^node[0-9]+$ ]]; then
    echo -e "${BLUE}2.x 레거시 노드 재생성 중: $1${NC}"
    echo -e "${YELLOW}환경변수 변경사항을 반영하기 위해 컨테이너를 재생성합니다...${NC}"
    docker compose -f docker-compose-legacy.yml stop $1
    docker compose -f docker-compose-legacy.yml rm -f $1
    docker compose -f docker-compose-legacy.yml up -d $1
    echo -e "${GREEN}노드가 재생성되었습니다: $1${NC}"
  elif [[ "$1" =~ ^3node[0-9]+$ ]]; then
    echo -e "${BLUE}3.x 노드 재생성 중: $1${NC}"
    echo -e "${YELLOW}환경변수 변경사항을 반영하기 위해 컨테이너를 재생성합니다...${NC}"
    docker compose stop $1
    docker compose rm -f $1
    docker compose up -d $1
    echo -e "${GREEN}노드가 재생성되었습니다: $1${NC}"
  else
    # 일반 컨테이너는 기존 방식 사용
    echo -e "${BLUE}컨테이너 재시작 중: $1${NC}"
    docker restart $1
    echo -e "${GREEN}컨테이너가 재시작되었습니다: $1${NC}"
  fi
}

dstop() { 
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: dstop <컨테이너명>${NC}"
    return 1
  fi
  echo -e "${BLUE}컨테이너 중지 중: $1${NC}"
  docker stop $1
  echo -e "${GREEN}컨테이너가 중지되었습니다: $1${NC}"
}

dstart() { 
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: dstart <컨테이너명>${NC}"
    return 1
  fi
  echo -e "${BLUE}컨테이너 시작 중: $1${NC}"
  docker start $1
  echo -e "${GREEN}컨테이너가 시작되었습니다: $1${NC}"
}

# Docker 로그 확인
dlog() { 
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: dlog <컨테이너명> [줄 수]${NC}"
    return 1
  fi
  
  # 기본값 설정
  local lines=100
  
  # 두 번째 매개변수가 있으면 줄 수 설정
  if [ ! -z "$2" ]; then
    lines=$2
  fi
  
  echo -e "${BLUE}$1 컨테이너의 마지막 $lines줄 로그를 표시합니다...${NC}"
  docker logs --tail $lines -f $1
}

# 노드 상태 요약
status() {
  echo -e "${BLUE}===== Creditcoin 노드 상태 요약 =====${NC}"
  
  # 모든 노드 검색
  local all_nodes=$(docker ps -a --format "{{.Names}}" | grep -E "^(3node|node)[0-9]+" | sort)
  
  if [ -z "$all_nodes" ]; then
    echo -e "${RED}Creditcoin 노드가 없습니다.${NC}"
    return 1
  fi
  
  # 실행 중인 노드 검색
  local running_nodes=$(docker ps --format "{{.Names}}" | grep -E "^(3node|node)[0-9]+" | sort)
  
  echo -e "${GREEN}실행 중인 노드:${NC}"
  if [ -z "$running_nodes" ]; then
    echo -e "  ${YELLOW}없음${NC}"
  else
    for node in $running_nodes; do
      local uptime=$(docker ps --format "{{.Status}}" --filter "name=$node" | sed -E 's/Up ([0-9]+) (seconds|minutes|hours|days).*/\1 \2/')
      if [[ "$node" == 3node* ]]; then
        echo -e "  ${GREEN}$node${NC} (Creditcoin 3.0) - 가동 시간: $uptime"
      else
        echo -e "  ${GREEN}$node${NC} (Creditcoin 2.0) - 가동 시간: $uptime"
      fi
    done
  fi
  
  # 중지된 노드 검색
  local stopped_nodes=$(comm -23 <(echo "$all_nodes") <(echo "$running_nodes" | sort 2>/dev/null) 2>/dev/null)
  
  echo -e "\n${RED}중지된 노드:${NC}"
  if [ -z "$stopped_nodes" ]; then
    echo -e "  ${YELLOW}없음${NC}"
  else
    for node in $stopped_nodes; do
      if [[ "$node" == 3node* ]]; then
        echo -e "  ${RED}$node${NC} (Creditcoin 3.0)"
      else
        echo -e "  ${RED}$node${NC} (Creditcoin 2.0)"
      fi
    done
  fi

  # 모니터링 상태 확인
  echo -e "\n${BLUE}모니터링 상태:${NC}"
  if docker ps | grep -q "creditcoin-monitor"; then
    local monitor_uptime=$(docker ps --format "{{.Status}}" --filter "name=creditcoin-monitor" | sed -E 's/Up ([0-9]+) (seconds|minutes|hours|days).*/\1 \2/')
    echo -e "  ${GREEN}모니터링 서비스 실행 중${NC} - 가동 시간: $monitor_uptime"
  else
    echo -e "  ${RED}모니터링 서비스 중지됨${NC}"
  fi
}

# Creditcoin CLI 키 생성
genkey() {
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: genkey <노드명>${NC}"
    echo -e "${YELLOW}예시: genkey 3node0, genkey node1${NC}"
    return 1
  fi
  
  local node=$1
  
  # 노드 실행 중인지 확인
  if ! docker ps | grep -q "$node"; then
    echo -e "${RED}오류: $node 노드가 실행 중이 아닙니다. 먼저 노드를 시작하세요.${NC}"
    return 1
  fi
  
  if [[ $node == 3node* ]]; then
    echo -e "${BLUE}Creditcoin 3.0 노드 키 생성 중: $node${NC}"
    docker exec -it $node /root/creditcoin3/target/release/creditcoin3-node key generate --scheme Sr25519
  elif [[ $node == node* ]]; then
    echo -e "${BLUE}Creditcoin 2.0 노드 키 생성 중: $node${NC}"
    docker exec -it $node /root/creditcoin/target/release/creditcoin-node key generate --scheme Sr25519
  else
    echo -e "${RED}유효하지 않은 노드 형식입니다. '3nodeX' 또는 'nodeX' 형식을 사용하세요.${NC}"
    return 1
  fi
}

# 세션 키 교체 (컨테이너 내부에서 실행)
rotatekey() { 
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: rotatekey <노드명>${NC}"
    echo -e "${YELLOW}예시: rotatekey 3node0, rotatekey node1${NC}"
    return 1
  fi
  
  local node=$1
  
  # 노드 실행 중인지 확인
  if ! docker ps | grep -q "$node"; then
    echo -e "${RED}오류: $node 노드가 실행 중이 아닙니다. 먼저 노드를 시작하세요.${NC}"
    return 1
  fi
  
  # 노드 타입 확인
  if [[ $node == 3node* ]]; then
    local num=$(echo $node | sed 's/3node//g')
    local port=$((33980 + $num))
    echo -e "${BLUE}$node 노드의 세션 키 교체 중...${NC}"
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "author_rotateKeys", "params":[]}'"'"' http://localhost:'$port'/' | jq
  elif [[ $node == node* ]]; then
    local num=$(echo $node | sed 's/node//g')
    local port=$((33970 + $num))
    echo -e "${BLUE}$node 노드의 세션 키 교체 중...${NC}"
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "author_rotateKeys", "params":[]}'"'"' http://localhost:'$port'/' | jq
  else
    echo -e "${RED}지원되지 않는 노드 형식입니다: $node${NC}"
    echo -e "${YELLOW}형식은 '3nodeX' 또는 'nodeX'여야 합니다.${NC}"
    return 1
  fi
}

# 노드 건강 상태 확인
checkHealth() {
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: checkHealth <노드명>${NC}"
    echo -e "${YELLOW}예시: checkHealth 3node0, checkHealth node1${NC}"
    return 1
  fi
  
  local node=$1
  
  # 노드 실행 중인지 확인
  if ! docker ps | grep -q "$node"; then
    echo -e "${RED}오류: $node 노드가 실행 중이 아닙니다. 먼저 노드를 시작하세요.${NC}"
    return 1
  fi
  
  # 노드 타입 확인
  if [[ $node == 3node* ]]; then
    local num=$(echo $node | sed 's/3node//g')
    local port=$((33980 + $num))
    echo -e "${BLUE}$node 노드의 건강 상태 확인 중...${NC}"
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "system_health", "params":[]}'"'"' http://localhost:'$port'/' | jq
  elif [[ $node == node* ]]; then
    local num=$(echo $node | sed 's/node//g')
    local port=$((33970 + $num))
    echo -e "${BLUE}$node 노드의 건강 상태 확인 중...${NC}"
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "system_health", "params":[]}'"'"' http://localhost:'$port'/' | jq
  else
    echo -e "${RED}지원되지 않는 노드 형식입니다: $node${NC}"
    echo -e "${YELLOW}형식은 '3nodeX' 또는 'nodeX'여야 합니다.${NC}"
    return 1
  fi
}

# 노드 피어 정보 확인
checkPeers() {
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: checkPeers <노드명>${NC}"
    echo -e "${YELLOW}예시: checkPeers 3node0, checkPeers node1${NC}"
    return 1
  fi
  
  local node=$1
  
  # 노드 실행 중인지 확인
  if ! docker ps | grep -q "$node"; then
    echo -e "${RED}오류: $node 노드가 실행 중이 아닙니다. 먼저 노드를 시작하세요.${NC}"
    return 1
  fi
  
  # 노드 타입 확인
  if [[ $node == 3node* ]]; then
    local num=$(echo $node | sed 's/3node//g')
    local port=$((33980 + $num))
    echo -e "${BLUE}$node 노드의 피어 정보 확인 중...${NC}"
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "system_peers", "params":[]}'"'"' http://localhost:'$port'/' | jq
  elif [[ $node == node* ]]; then
    local num=$(echo $node | sed 's/node//g')
    local port=$((33970 + $num))
    echo -e "${BLUE}$node 노드의 피어 정보 확인 중...${NC}"
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "system_peers", "params":[]}'"'"' http://localhost:'$port'/' | jq
  else
    echo -e "${RED}지원되지 않는 노드 형식입니다: $node${NC}"
    echo -e "${YELLOW}형식은 '3nodeX' 또는 'nodeX'여야 합니다.${NC}"
    return 1
  fi
}

# 노드 이름 확인
checkName() {
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: checkName <노드명>${NC}"
    echo -e "${YELLOW}예시: checkName 3node0, checkName node1${NC}"
    return 1
  fi
  
  local node=$1
  
  # 노드 실행 중인지 확인
  if ! docker ps | grep -q "$node"; then
    echo -e "${RED}오류: $node 노드가 실행 중이 아닙니다. 먼저 노드를 시작하세요.${NC}"
    return 1
  fi
  
  # 노드 타입 확인
  if [[ $node == 3node* ]]; then
    local num=$(echo $node | sed 's/3node//g')
    local port=$((33980 + $num))
    echo -e "${BLUE}$node 노드의 이름 확인 중...${NC}"
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "system_name", "params":[]}'"'"' http://localhost:'$port'/' | jq
  elif [[ $node == node* ]]; then
    local num=$(echo $node | sed 's/node//g')
    local port=$((33970 + $num))
    echo -e "${BLUE}$node 노드의 이름 확인 중...${NC}"
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "system_name", "params":[]}'"'"' http://localhost:'$port'/' | jq
  else
    echo -e "${RED}지원되지 않는 노드 형식입니다: $node${NC}"
    echo -e "${YELLOW}형식은 '3nodeX' 또는 'nodeX'여야 합니다.${NC}"
    return 1
  fi
}

# 노드 버전 확인
checkVersion() {
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: checkVersion <노드명>${NC}"
    echo -e "${YELLOW}예시: checkVersion 3node0, checkVersion node1${NC}"
    return 1
  fi
  
  local node=$1
  
  # 노드 실행 중인지 확인
  if ! docker ps | grep -q "$node"; then
    echo -e "${RED}오류: $node 노드가 실행 중이 아닙니다. 먼저 노드를 시작하세요.${NC}"
    return 1
  fi
  
  # 노드 타입 확인
  if [[ $node == 3node* ]]; then
    local num=$(echo $node | sed 's/3node//g')
    local port=$((33980 + $num))
    echo -e "${BLUE}$node 노드의 버전 확인 중...${NC}"
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "system_version", "params":[]}'"'"' http://localhost:'$port'/' | jq
  elif [[ $node == node* ]]; then
    local num=$(echo $node | sed 's/node//g')
    local port=$((33970 + $num))
    echo -e "${BLUE}$node 노드의 버전 확인 중...${NC}"
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "system_version", "params":[]}'"'"' http://localhost:'$port'/' | jq
  else
    echo -e "${RED}지원되지 않는 노드 형식입니다: $node${NC}"
    echo -e "${YELLOW}형식은 '3nodeX' 또는 'nodeX'여야 합니다.${NC}"
    return 1
  fi
}

# 체인 상태 확인
checkChain() {
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: checkChain <노드명>${NC}"
    echo -e "${YELLOW}예시: checkChain 3node0, checkChain node1${NC}"
    return 1
  fi
  
  local node=$1
  
  # 노드 실행 중인지 확인
  if ! docker ps | grep -q "$node"; then
    echo -e "${RED}오류: $node 노드가 실행 중이 아닙니다. 먼저 노드를 시작하세요.${NC}"
    return 1
  fi
  
  # 노드 타입 확인
  if [[ $node == 3node* ]]; then
    local num=$(echo $node | sed 's/3node//g')
    local port=$((33980 + $num))
    echo -e "${BLUE}$node 노드의 체인 상태 확인 중...${NC}"
    echo -e "${GREEN}현재 블록 헤더 가져오는 중...${NC}"
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "chain_getHeader", "params":[]}'"'"' http://localhost:'$port'/' | jq
    echo -e "${GREEN}마지막 완료된 라운드 가져오는 중...${NC}"
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "chain_getFinalisedHead", "params":[]}'"'"' http://localhost:'$port'/' | jq
  elif [[ $node == node* ]]; then
    local num=$(echo $node | sed 's/node//g')
    local port=$((33970 + $num))
    echo -e "${BLUE}$node 노드의 체인 상태 확인 중...${NC}"
    echo -e "${GREEN}현재 블록 헤더 가져오는 중...${NC}"
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "chain_getHeader", "params":[]}'"'"' http://localhost:'$port'/' | jq
    echo -e "${GREEN}마지막 완료된 라운드 가져오는 중...${NC}"
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "chain_getFinalisedHead", "params":[]}'"'"' http://localhost:'$port'/' | jq
  else
    echo -e "${RED}지원되지 않는 노드 형식입니다: $node${NC}"
    echo -e "${YELLOW}형식은 '3nodeX' 또는 'nodeX'여야 합니다.${NC}"
    return 1
  fi
}

# 최신 블록 정보 확인
getLatestBlock() {
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: getLatestBlock <노드명>${NC}"
    echo -e "${YELLOW}예시: getLatestBlock 3node0, getLatestBlock node1${NC}"
    return 1
  fi
  
  local node=$1
  
  # 노드 실행 중인지 확인
  if ! docker ps | grep -q "$node"; then
    echo -e "${RED}오류: $node 노드가 실행 중이 아닙니다. 먼저 노드를 시작하세요.${NC}"
    return 1
  fi
  
  # 노드 타입 확인
  if [[ $node == 3node* ]]; then
    local num=$(echo $node | sed 's/3node//g')
    local port=$((33980 + $num))
    echo -e "${BLUE}$node 노드의 최신 블록 정보 가져오는 중...${NC}"
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "chain_getBlock", "params":[]}'"'"' http://localhost:'$port'/' | jq
  elif [[ $node == node* ]]; then
    local num=$(echo $node | sed 's/node//g')
    local port=$((33970 + $num))
    echo -e "${BLUE}$node 노드의 최신 블록 정보 가져오는 중...${NC}"
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "chain_getBlock", "params":[]}'"'"' http://localhost:'$port'/' | jq
  else
    echo -e "${RED}지원되지 않는 노드 형식입니다: $node${NC}"
    echo -e "${YELLOW}형식은 '3nodeX' 또는 'nodeX'여야 합니다.${NC}"
    return 1
  fi
}

# 단일 노드에 대한 페이아웃 실행
payout() {
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: payout <노드명>${NC}"
    echo -e "${YELLOW}예시: payout 3node0, payout node1${NC}"
    return 1
  fi
  
  local node=$1
  
  # 노드 실행 중인지 확인
  if ! docker ps | grep -q "$node"; then
    echo -e "${RED}오류: $node 노드가 실행 중이 아닙니다. 먼저 노드를 시작하세요.${NC}"
    return 1
  fi
  
  # 노드 타입 확인
  if [[ $node == 3node* ]]; then
    local num=$(echo $node | sed 's/3node//g')
    local port=$((33980 + $num))
    echo -e "${BLUE}노드 $node 페이아웃 실행 중...${NC}"
    echo -e "${GREEN}RPC 포트: $port (내부)${NC}"
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "staking_payoutStakers","params":["ACCOUNT_ADDRESS", ERA_NUMBER]}'"'"' http://localhost:'$port'/' | jq
  elif [[ $node == node* ]]; then
    local num=$(echo $node | sed 's/node//g')
    local port=$((33970 + $num))
    echo -e "${BLUE}노드 $node 페이아웃 실행 중...${NC}"
    echo -e "${GREEN}RPC 포트: $port (내부)${NC}"
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "staking_payoutStakers","params":["ACCOUNT_ADDRESS", ERA_NUMBER]}'"'"' http://localhost:'$port'/' | jq
  else
    echo -e "${RED}지원되지 않는 노드 형식입니다: $node${NC}"
    echo -e "${YELLOW}형식은 '3nodeX' 또는 'nodeX'여야 합니다.${NC}"
    return 1
  fi
}

# Creditcoin 3.0 노드만 대상으로 페이아웃 실행
payoutAll() {
  echo -e "${BLUE}모든 Creditcoin 3.0 노드에 대해 페이아웃을 순차적으로 실행합니다...${NC}"
  
  # 실행 중인 3.0 노드 찾기
  local nodes3=$(docker ps --format "{{.Names}}" | grep "^3node[0-9]")
  
  # 노드가 없으면 종료
  if [ -z "$nodes3" ]; then
    echo -e "${RED}실행 중인 Creditcoin 3.0 노드가 없습니다.${NC}"
    return 1
  fi
  
  # 3.0 노드 페이아웃
  for node in $nodes3; do
    echo -e "${BLUE}노드 $node 페이아웃 실행 중...${NC}"
    # 노드 번호 추출
    local num=$(echo $node | sed 's/3node//g')
    local port=$((33980 + $num))
    echo -e "${GREEN}RPC 포트: $port (내부)${NC}"
    # 페이아웃 명령 실행 (컨테이너 내부에서)
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "staking_payoutStakers","params":["ACCOUNT_ADDRESS", ERA_NUMBER]}'"'"' http://localhost:'$port'/' | jq
    echo ""
    sleep 2
  done
  
  echo -e "${GREEN}모든 Creditcoin 3.0 노드의 페이아웃이 완료되었습니다.${NC}"
}

# Creditcoin 2.0 (레거시) 노드만 대상으로 페이아웃 실행
payoutAllLegacy() {
  echo -e "${BLUE}모든 Creditcoin 2.0 레거시 노드에 대해 페이아웃을 순차적으로 실행합니다...${NC}"
  
  # 실행 중인 2.0 노드 찾기
  local nodes2=$(docker ps --format "{{.Names}}" | grep "^node[0-9]")
  
  # 노드가 없으면 종료
  if [ -z "$nodes2" ]; then
    echo -e "${RED}실행 중인 Creditcoin 2.0 레거시 노드가 없습니다.${NC}"
    return 1
  fi
  
  # 2.0 노드 페이아웃
  for node in $nodes2; do
    echo -e "${BLUE}노드 $node 페이아웃 실행 중...${NC}"
    # 노드 번호 추출
    local num=$(echo $node | sed 's/node//g')
    local port=$((33970 + $num))
    echo -e "${GREEN}RPC 포트: $port (내부)${NC}"
    # 페이아웃 명령 실행 (컨테이너 내부에서)
    docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "staking_payoutStakers","params":["ACCOUNT_ADDRESS", ERA_NUMBER]}'"'"' http://localhost:'$port'/' | jq
    echo ""
    sleep 2
  done
  
  echo -e "${GREEN}모든 Creditcoin 2.0 레거시 노드의 페이아웃이 완료되었습니다.${NC}"
}

# 모든 노드 재시작 함수
restartAll() {
  echo -e "${BLUE}모든 Creditcoin 노드 재시작 중...${NC}"
  
  # 실행 중인 노드 검색 (개별 라인으로 저장)
  local nodes=$(docker ps --format "{{.Names}}" | grep -E "^(3node|node)[0-9]+")
  
  if [ -z "$nodes" ]; then
    echo -e "${RED}실행 중인 Creditcoin 노드가 없습니다.${NC}"
    return 1
  fi
  
  # 재시작 확인
  echo -e "${YELLOW}다음 노드들을 재시작합니다:${NC}"
  echo "$nodes" | while read node; do
    echo -e "  ${GREEN}$node${NC}"
  done
  
  # zsh 호환 방식으로 확인
  echo -e "${YELLOW}계속하시겠습니까? (y/N)${NC}"
  read response
  if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "${RED}작업이 취소되었습니다.${NC}"
    return 1
  fi
  
  # 노드 재시작
  echo "$nodes" | while read node; do
    echo -e "${BLUE}$node 재시작 중...${NC}"
    if docker ps --format "{{.Names}}" | grep -q "^$node$"; then
      docker restart $node
      echo -e "${GREEN}$node 재시작 완료${NC}"
    else
      echo -e "${RED}노드 $node를 찾을 수 없습니다.${NC}"
    fi
  done
  
  echo -e "${GREEN}모든 노드 재시작이 완료되었습니다.${NC}"
}

# 모든 노드 중지 함수
stopAll() {
  echo -e "${BLUE}모든 Creditcoin 노드 중지 중...${NC}"
  
  # 실행 중인 노드 검색
  local nodes=$(docker ps --format "{{.Names}}" | grep -E "^(3node|node)[0-9]+")
  
  if [ -z "$nodes" ]; then
    echo -e "${RED}실행 중인 Creditcoin 노드가 없습니다.${NC}"
    return 1
  fi
  
  # 중지 확인
  echo -e "${YELLOW}다음 노드들을 중지합니다:${NC}"
  for node in $nodes; do
    echo -e "  ${GREEN}$node${NC}"
  done
  
  # zsh 호환 방식으로 확인
  echo -e "${YELLOW}계속하시겠습니까? (y/N)${NC}"
  read response
  if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "${RED}작업이 취소되었습니다.${NC}"
    return 1
  fi
  
  # 노드 중지
  for node in $nodes; do
    echo -e "${BLUE}$node 중지 중...${NC}"
    docker stop $node
    echo -e "${GREEN}$node 중지 완료${NC}"
  done
  
  echo -e "${GREEN}모든 노드 중지가 완료되었습니다.${NC}"
}

# 모든 노드 시작 함수
startAll() {
  echo -e "${BLUE}중지된 모든 Creditcoin 노드 시작 중...${NC}"
  
  # 중지된 노드 검색
  local nodes=$(docker ps -a --format "{{.Names}}" | grep -E "^(3node|node)[0-9]+" | grep -v "$(docker ps --format "{{.Names}}" | grep -E "^(3node|node)[0-9]+")")
  
  if [ -z "$nodes" ]; then
    echo -e "${RED}중지된 Creditcoin 노드가 없습니다.${NC}"
    return 1
  fi
  
  # 시작 확인
  echo -e "${YELLOW}다음 노드들을 시작합니다:${NC}"
  for node in $nodes; do
    echo -e "  ${GREEN}$node${NC}"
  done
  
  # zsh 호환 방식으로 확인
  echo -e "${YELLOW}계속하시겠습니까? (y/N)${NC}"
  read response
  if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "${RED}작업이 취소되었습니다.${NC}"
    return 1
  fi
  
  # 노드 시작
  for node in $nodes; do
    echo -e "${BLUE}$node 시작 중...${NC}"
    docker start $node
    echo -e "${GREEN}$node 시작 완료${NC}"
  done
  
  echo -e "${GREEN}모든 노드 시작이 완료되었습니다.${NC}"
}

# 노드 완전히 삭제하는 함수
dkill() {
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: dkill <노드명>${NC}"
    echo -e "${YELLOW}예시: dkill 3node1 또는 dkill node0${NC}"
    return 1
  fi
  
  local node=$1
  
  # 유효성 검사
  if [[ ! $node == 3node* ]] && [[ ! $node == node* ]]; then
    echo -e "${RED}지원되지 않는 노드 형식입니다: $node${NC}"
    echo -e "${YELLOW}형식은 '3nodeX' 또는 'nodeX'여야 합니다.${NC}"
    return 1
  fi
  
  # 노드 존재 확인
  if ! docker ps -a | grep -q "$node"; then
    echo -e "${RED}오류: $node 노드가 존재하지 않습니다.${NC}"
    return 1
  fi
  
  # 확인 메시지 표시
  echo -e "${RED}!!! 경고 !!!${NC}"
  echo -e "${RED}노드 '$node'를 완전히 삭제하려고 합니다.${NC}"
  echo -e "${YELLOW}이 작업은 다음을 포함합니다:${NC}"
  echo -e "${YELLOW} - 노드 컨테이너 중지 및 삭제${NC}"
  echo -e "${YELLOW} - 노드 데이터 디렉토리 삭제${NC}"
  echo -e "${YELLOW} - 설정 파일에서 노드 항목 제거${NC}"
  echo ""
  echo -e "${RED}이 작업은 되돌릴 수 없습니다.${NC}"
  echo ""
  
  # zsh 호환 방식으로 확인
  echo -e "${YELLOW}정말로 '$node'를 완전히 삭제하시겠습니까? (y/N)${NC}"
  read response
  
  if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "${BLUE}작업이 취소되었습니다.${NC}"
    return 0
  fi
  
  echo -e "${BLUE}노드 $node 완전히 삭제 중...${NC}"
  
  # 1. 노드 중지
  echo -e "${YELLOW}1. 노드 중지 중...${NC}"
  docker stop $node >/dev/null 2>&1
  
  # 2. 노드 컨테이너 삭제
  echo -e "${YELLOW}2. 컨테이너 삭제 중...${NC}"
  docker rm $node >/dev/null 2>&1
  
  # 3. 관련 데이터 디렉토리 삭제
  echo -e "${YELLOW}3. 데이터 디렉토리 삭제 중...${NC}"
  # 노드 타입 확인
  if [[ $node == 3node* ]]; then
    rm -rf ./$node
    # .env 파일에서 해당 노드 설정 삭제
    local num=$(echo $node | sed 's/3node//g')
    sed -i '' "/P2P_PORT_3NODE${num}/d" .env
    sed -i '' "/RPC_PORT_3NODE${num}/d" .env
    sed -i '' "/NODE_NAME_3NODE${num}/d" .env
    sed -i '' "/TELEMETRY_3NODE${num}/d" .env
    sed -i '' "/PRUNING_3NODE${num}/d" .env
    
    # docker-compose.yml에서 노드 설정 삭제
    if [ -f "docker-compose.yml" ]; then
      # 백업 파일 생성
      cp docker-compose.yml docker-compose.yml.bak
      
      # 노드 설정 블록 제거 (macOS 호환 방식)
      awk -v node="$node:" 'BEGIN {p=1} /^  '$node':/,/^  [^[:space:]]+:/ {if (/^  [^[:space:]]+:/ && !/^  '$node':/) p=1; else p=0} p' docker-compose.yml > docker-compose.yml.tmp
      mv docker-compose.yml.tmp docker-compose.yml
      
      echo -e "${GREEN}docker-compose.yml 파일이 수정되었습니다. 백업: docker-compose.yml.bak${NC}"
    fi
    
  elif [[ $node == node* ]]; then
    rm -rf ./$node
    # .env 파일에서 해당 노드 설정 삭제
    local num=$(echo $node | sed 's/node//g')
    sed -i '' "/P2P_PORT_NODE${num}/d" .env
    sed -i '' "/WS_PORT_NODE${num}/d" .env
    sed -i '' "/NODE_NAME_${num}/d" .env
    sed -i '' "/TELEMETRY_ENABLED_${num}/d" .env
    
    # docker-compose-legacy.yml에서 노드 설정 삭제
    if [ -f "docker-compose-legacy.yml" ]; then
      # 백업 파일 생성
      cp docker-compose-legacy.yml docker-compose-legacy.yml.bak
      
      # 노드 설정 블록 제거 (macOS 호환 방식)
      awk -v node="$node:" 'BEGIN {p=1} /^  '$node':/,/^  [^[:space:]]+:/ {if (/^  [^[:space:]]+:/ && !/^  '$node':/) p=1; else p=0} p' docker-compose-legacy.yml > docker-compose-legacy.yml.tmp
      mv docker-compose-legacy.yml.tmp docker-compose-legacy.yml
      
      echo -e "${GREEN}docker-compose-legacy.yml 파일이 수정되었습니다. 백업: docker-compose-legacy.yml.bak${NC}"
    fi
  fi
  
  # 4. Docker 캐시 정리 (선택 사항)
  echo -e "${YELLOW}4. Docker 캐시 정리 중...${NC}"
  docker container prune -f >/dev/null 2>&1
  
  echo -e "${GREEN}노드 $node가 완전히 삭제되었습니다.${NC}"
}

# 모든 실행 중인 노드 정보 요약
infoAll() {
  echo -e "${BLUE}===== Creditcoin 노드 정보 요약 =====${NC}"
  
  # 실행 중인 노드 검색
  local nodes=$(docker ps --format "{{.Names}}" | grep -E "^(3node|node)[0-9]+" | sort)
  
  if [ -z "$nodes" ]; then
    echo -e "${RED}실행 중인 Creditcoin 노드가 없습니다.${NC}"
    return 1
  fi
  
  echo -e "${GREEN}실행 중인 노드 정보:${NC}\n"
  
  for node in $nodes; do
    echo -e "${BLUE}---------- $node 정보 ----------${NC}"
    
    # 노드 타입에 따른 포트 계산
    if [[ $node == 3node* ]]; then
      local num=$(echo $node | sed 's/3node//g')
      local p2p_port=$((30340 + $num))
      local rpc_port=$((33980 + $num))
      
      # 노드 상태 정보 수집
      echo -e "${YELLOW}노드 버전:${NC}"
      docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "system_version", "params":[]}'"'"' http://localhost:'$rpc_port'/' | jq '.result' 2>/dev/null || echo "응답 없음"
      
      echo -e "${YELLOW}노드 이름:${NC}"
      docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "system_name", "params":[]}'"'"' http://localhost:'$rpc_port'/' | jq '.result' 2>/dev/null || echo "응답 없음"
      
      echo -e "${YELLOW}건강 상태:${NC}"
      docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "system_health", "params":[]}'"'"' http://localhost:'$rpc_port'/' | jq '.result' 2>/dev/null || echo "응답 없음"
      
      echo -e "${YELLOW}피어 수:${NC}"
      peers_count=$(docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "system_peers", "params":[]}'"'"' http://localhost:'$rpc_port'/' | jq '.result | length' 2>/dev/null)
      echo -e "${peers_count:-"응답 없음"}"
      
    elif [[ $node == node* ]]; then
      local num=$(echo $node | sed 's/node//g')
      local p2p_port=$((30333 + $num))
      local ws_port=$((33970 + $num))
      
      # 노드 상태 정보 수집
      echo -e "${YELLOW}노드 버전:${NC}"
      docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "system_version", "params":[]}'"'"' http://localhost:'$ws_port'/' | jq '.result' 2>/dev/null || echo "응답 없음"
      
      echo -e "${YELLOW}노드 이름:${NC}"
      docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "system_name", "params":[]}'"'"' http://localhost:'$ws_port'/' | jq '.result' 2>/dev/null || echo "응답 없음"
      
      echo -e "${YELLOW}건강 상태:${NC}"
      docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "system_health", "params":[]}'"'"' http://localhost:'$ws_port'/' | jq '.result' 2>/dev/null || echo "응답 없음"
      
      echo -e "${YELLOW}피어 수:${NC}"
      peers_count=$(docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "system_peers", "params":[]}'"'"' http://localhost:'$ws_port'/' | jq '.result | length' 2>/dev/null)
      echo -e "${peers_count:-"응답 없음"}"
    fi
    
    # 리소스 사용량
    echo -e "${YELLOW}리소스 사용량:${NC}"
    docker stats --no-stream --format "CPU: {{.CPUPerc}}, 메모리: {{.MemUsage}}" $node
    
    echo ""
  done
}

# 세션키 백업 함수
backupkeys() {
  # 사용법 표시
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: backupkeys <노드명>${NC}"
    echo -e "예시: backupkeys 3node0"
    return 1
  fi

  NODE_NAME=$1
  BACKUP_DATE=$(date +%Y%m%d-%H%M)
  BACKUP_FILE="./${NODE_NAME}-keys-${BACKUP_DATE}.tar.gz"

  # 노드 디렉토리 확인
  if [ ! -d "./${NODE_NAME}" ]; then
    echo -e "${RED}오류: ${NODE_NAME} 디렉토리가 현재 위치에 존재하지 않습니다.${NC}"
    return 1
  fi

  # 노드 실행 중인지 확인
  if docker ps | grep -q "${NODE_NAME}"; then
    echo -e "${YELLOW}세션키를 복사하기 위해 서버를 중지합니다. (y/N)${NC}"
    read STOP_CONFIRM
    if [[ ! "$STOP_CONFIRM" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      echo -e "${RED}작업이 취소되었습니다.${NC}"
      return 1
    fi
    
    echo -e "${BLUE}노드 중지 중...${NC}"
    docker stop ${NODE_NAME}
    echo -e "${GREEN}노드가 중지되었습니다.${NC}"
    
    # 노드 중지 상태 저장 (나중에 재시작하기 위해)
    NODE_WAS_RUNNING=true
  else
    NODE_WAS_RUNNING=false
  fi

  # 노드 타입 확인
  if [[ "${NODE_NAME}" == 3node* ]]; then
    CHAIN_DIR="creditcoin3"
    echo -e "${BLUE}Creditcoin 3.0 노드로 감지되었습니다.${NC}"
  elif [[ "${NODE_NAME}" == node* ]]; then
    CHAIN_DIR="creditcoin"
    echo -e "${BLUE}Creditcoin 2.0 노드로 감지되었습니다.${NC}"
  else
    echo -e "${RED}지원되지 않는 노드 형식입니다: ${NODE_NAME}${NC}"
    echo -e "${YELLOW}노드 이름은 '3node*' 또는 'node*' 형식이어야 합니다.${NC}"
    
    # 노드 재시작 (필요한 경우)
    if [ "$NODE_WAS_RUNNING" = true ]; then
      echo -e "${BLUE}노드를 다시 시작합니다...${NC}"
      docker start ${NODE_NAME}
      echo -e "${GREEN}노드가 재시작되었습니다.${NC}"
    fi
    
    return 1
  fi

  # 세션키 디렉토리 경로
  KEYSTORE_DIR="./${NODE_NAME}/data/chains/${CHAIN_DIR}/keystore"
  NETWORK_DIR="./${NODE_NAME}/data/chains/${CHAIN_DIR}/network"

  # 키스토어 또는 네트워크 디렉토리가 존재하는지 확인
  if [ ! -d "$KEYSTORE_DIR" ] && [ ! -d "$NETWORK_DIR" ]; then
    echo -e "${RED}오류: 키스토어 및 네트워크 디렉토리가 모두 존재하지 않습니다.${NC}"
    
    # 노드 재시작 (필요한 경우)
    if [ "$NODE_WAS_RUNNING" = true ]; then
      echo -e "${BLUE}노드를 다시 시작합니다...${NC}"
      docker start ${NODE_NAME}
      echo -e "${GREEN}노드가 재시작되었습니다.${NC}"
    fi
    
    return 1
  fi

  # 임시 디렉토리 생성
  TEMP_DIR=$(mktemp -d)
  echo -e "${BLUE}임시 디렉토리 생성: ${TEMP_DIR}${NC}"

  # 백업 구조 생성
  mkdir -p "${TEMP_DIR}/keystore"
  mkdir -p "${TEMP_DIR}/network"

  # 세션키 디렉토리 복사
  if [ -d "$KEYSTORE_DIR" ]; then
    echo -e "${BLUE}키스토어 디렉토리 복사 중...${NC}"
    cp -r "${KEYSTORE_DIR}"/* "${TEMP_DIR}/keystore/" 2>/dev/null
  fi

  if [ -d "$NETWORK_DIR" ]; then
    echo -e "${BLUE}네트워크 디렉토리 복사 중...${NC}"
    cp -r "${NETWORK_DIR}"/* "${TEMP_DIR}/network/" 2>/dev/null
  fi

  # 메타데이터 파일 생성
  echo "노드명: ${NODE_NAME}" > "${TEMP_DIR}/metadata.txt"
  echo "백업날짜: $(date)" >> "${TEMP_DIR}/metadata.txt"
  echo "체인: ${CHAIN_DIR}" >> "${TEMP_DIR}/metadata.txt"

  # 아카이브 생성
  echo -e "${BLUE}세션키 아카이브 생성 중...${NC}"
  tar -czf "${BACKUP_FILE}" -C "${TEMP_DIR}" .

  # 임시 디렉토리 삭제
  rm -rf "${TEMP_DIR}"

  # 백업 파일 권한 설정
  chmod 600 "${BACKUP_FILE}"

  echo -e "${GREEN}백업이 완료되었습니다: ${BACKUP_FILE}${NC}"
  echo -e "${YELLOW}중요: 이 파일은 보안을 위해 안전한 곳에 보관하세요.${NC}"

  # 노드 재시작 (필요한 경우)
  if [ "$NODE_WAS_RUNNING" = true ]; then
    echo -e "${BLUE}노드를 다시 시작합니다...${NC}"
    docker start ${NODE_NAME}
    echo -e "${GREEN}노드가 재시작되었습니다.${NC}"
  fi
}

# 세션키 복원 함수
restorekeys() {
  # 사용법 표시
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo -e "${YELLOW}사용법: restorekeys <백업파일> <대상노드명>${NC}"
    echo -e "예시: restorekeys ./3node0-keys-20250507-1234.tar.gz 3node1"
    return 1
  fi

  BACKUP_FILE=$1
  TARGET_NODE=$2

  # 백업 파일 존재 확인
  if [ ! -f "$BACKUP_FILE" ]; then
    echo -e "${RED}오류: 백업 파일 '${BACKUP_FILE}'이 존재하지 않습니다.${NC}"
    return 1
  fi

  # 대상 노드 디렉토리 존재 확인
  if [ ! -d "./${TARGET_NODE}" ]; then
    echo -e "${RED}오류: 대상 노드 디렉토리 './${TARGET_NODE}'가 존재하지 않습니다.${NC}"
    return 1
  fi

  # 노드 실행 중인지 확인
  if docker ps | grep -q "${TARGET_NODE}"; then
    echo -e "${YELLOW}세션키를 복원하기 위해 서버를 중지합니다. 이 작업은 복구할 수 없습니다. (y/N)${NC}"
    read STOP_CONFIRM
    if [[ ! "$STOP_CONFIRM" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      echo -e "${RED}작업이 취소되었습니다.${NC}"
      return 1
    fi
    
    echo -e "${BLUE}노드 중지 중...${NC}"
    docker stop ${TARGET_NODE}
    echo -e "${GREEN}노드가 중지되었습니다.${NC}"
    
    # 노드 중지 상태 저장 (나중에 재시작하기 위해)
    NODE_WAS_RUNNING=true
  else
    NODE_WAS_RUNNING=false
  fi

  # 임시 디렉토리 생성
  TEMP_DIR=$(mktemp -d)
  echo -e "${BLUE}임시 디렉토리 생성: ${TEMP_DIR}${NC}"

  # 백업 파일 압축 해제
  echo -e "${BLUE}백업 파일 압축 해제 중...${NC}"
  tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"

  # 메타데이터 파일 확인
  if [ -f "${TEMP_DIR}/metadata.txt" ]; then
    echo -e "${BLUE}백업 메타데이터:${NC}"
    cat "${TEMP_DIR}/metadata.txt"
    
    # 메타데이터에서 체인 정보 추출
    CHAIN_DIR=$(grep "체인:" "${TEMP_DIR}/metadata.txt" | cut -d' ' -f2)
    if [ -z "$CHAIN_DIR" ]; then
      echo -e "${YELLOW}경고: 메타데이터에서 체인 정보를 찾을 수 없습니다. 대상 노드의 디렉토리 구조를 검사합니다...${NC}"
      CHAIN_DIR=""
    fi
  else
    echo -e "${YELLOW}경고: 메타데이터 파일이 없습니다. 대상 노드의 디렉토리 구조를 검사합니다...${NC}"
    CHAIN_DIR=""
  fi

  # 체인 디렉토리 확인
  if [ -z "$CHAIN_DIR" ]; then
    if [[ "${TARGET_NODE}" == 3node* ]]; then
      CHAIN_DIR="creditcoin3"
      echo -e "${BLUE}대상 노드는 Creditcoin 3.0으로 감지되었습니다.${NC}"
    elif [[ "${TARGET_NODE}" == node* ]]; then
      CHAIN_DIR="creditcoin"
      echo -e "${BLUE}대상 노드는 Creditcoin 2.0으로 감지되었습니다.${NC}"
    else
      echo -e "${RED}오류: 노드 이름 형식을 인식할 수 없습니다: ${TARGET_NODE}${NC}"
      echo -e "${YELLOW}노드 이름은 '3node*' 또는 'node*' 형식이어야 합니다.${NC}"
      rm -rf "$TEMP_DIR"
      
      # 노드 재시작 (필요한 경우)
      if [ "$NODE_WAS_RUNNING" = true ]; then
        echo -e "${BLUE}노드를 다시 시작합니다...${NC}"
        docker start ${TARGET_NODE}
        echo -e "${GREEN}노드가 재시작되었습니다.${NC}"
      fi
      
      return 1
    fi
  fi

  # 키스토어 및 네트워크 디렉토리 경로
  TARGET_KEYSTORE_DIR="./${TARGET_NODE}/data/chains/${CHAIN_DIR}/keystore"
  TARGET_NETWORK_DIR="./${TARGET_NODE}/data/chains/${CHAIN_DIR}/network"

  # 백업에 키 파일이 있는지 확인
  if [ ! -d "${TEMP_DIR}/keystore" ] && [ ! -d "${TEMP_DIR}/network" ]; then
    echo -e "${RED}오류: 백업 파일에 키스토어 또는 네트워크 디렉토리가 포함되어 있지 않습니다.${NC}"
    rm -rf "$TEMP_DIR"
    
    # 노드 재시작 (필요한 경우)
    if [ "$NODE_WAS_RUNNING" = true ]; then
      echo -e "${BLUE}노드를 다시 시작합니다...${NC}"
      docker start ${TARGET_NODE}
      echo -e "${GREEN}노드가 재시작되었습니다.${NC}"
    fi
    
    return 1
  fi

  # 대상 디렉토리 백업
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  if [ -d "$TARGET_KEYSTORE_DIR" ]; then
    echo -e "${YELLOW}기존 키스토어 디렉토리 백업 중...${NC}"
    mv "${TARGET_KEYSTORE_DIR}" "${TARGET_KEYSTORE_DIR}.backup-${TIMESTAMP}"
  fi

  if [ -d "$TARGET_NETWORK_DIR" ]; then
    echo -e "${YELLOW}기존 네트워크 디렉토리 백업 중...${NC}"
    mv "${TARGET_NETWORK_DIR}" "${TARGET_NETWORK_DIR}.backup-${TIMESTAMP}"
  fi

  # 대상 디렉토리 생성
  mkdir -p "$TARGET_KEYSTORE_DIR"
  mkdir -p "$TARGET_NETWORK_DIR"

  # 키 파일 복원
  if [ -d "${TEMP_DIR}/keystore" ]; then
    echo -e "${BLUE}키스토어 파일 복원 중...${NC}"
    cp -r "${TEMP_DIR}/keystore/"* "${TARGET_KEYSTORE_DIR}/" 2>/dev/null
  fi

  if [ -d "${TEMP_DIR}/network" ]; then
    echo -e "${BLUE}네트워크 파일 복원 중...${NC}"
    cp -r "${TEMP_DIR}/network/"* "${TARGET_NETWORK_DIR}/" 2>/dev/null
  fi

  # 파일 권한 설정
  echo -e "${BLUE}파일 권한 설정 중...${NC}"
  chmod 700 "$TARGET_KEYSTORE_DIR" "$TARGET_NETWORK_DIR"
  find "$TARGET_KEYSTORE_DIR" -type f -exec chmod 600 {} \; 2>/dev/null
  find "$TARGET_NETWORK_DIR" -type f -exec chmod 600 {} \; 2>/dev/null

  # 임시 디렉토리 삭제
  rm -rf "$TEMP_DIR"

  echo -e "${GREEN}세션키가 '${TARGET_NODE}' 노드에 성공적으로 복원되었습니다.${NC}"
  echo -e "${YELLOW}주의: 동일한 세션키를 가진 두 노드를 동시에 실행하면 슬래싱(처벌)이 발생할 수 있습니다.${NC}"

  # 노드 재시작
  echo -e "${YELLOW}노드를 다시 시작하시겠습니까? (y/N)${NC}"
  read RESTART_CONFIRM
  if [[ "$RESTART_CONFIRM" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "${BLUE}노드 시작 중...${NC}"
    docker start ${TARGET_NODE}
    echo -e "${GREEN}노드가 시작되었습니다.${NC}"
  else
    echo -e "${YELLOW}노드는 중지된 상태로 유지됩니다.${NC}"
  fi
}

# 모든 노드 건강 상태 모니터링
monitorhealth() {
  echo -e "${BLUE}모든 노드의 건강 상태 모니터링 중...${NC}"
  echo -e "${YELLOW}종료하려면 Ctrl+C를 누르세요${NC}"
  
  while true; do
    clear
    echo -e "${BLUE}===== $(date) =====${NC}"
    
    # 실행 중인 노드 검색
    local nodes=$(docker ps --format "{{.Names}}" | grep -E "^(3node|node)[0-9]+" | sort)
    
    if [ -z "$nodes" ]; then
      echo -e "${RED}실행 중인 Creditcoin 노드가 없습니다.${NC}"
    else
      for node in $nodes; do
        echo -e "${GREEN}===== $node 건강 상태 =====${NC}"
        
        # 노드 타입 확인
        if [[ $node == 3node* ]]; then
          local num=$(echo $node | sed 's/3node//g')
          local port=$((33980 + $num))
        elif [[ $node == node* ]]; then
          local num=$(echo $node | sed 's/node//g')
          local port=$((33970 + $num))
        fi
        
        # 건강 상태 확인
        docker exec $node bash -c 'curl -s -H "Content-Type: application/json" -d '"'"'{"id":1, "jsonrpc":"2.0", "method": "system_health", "params":[]}'"'"' http://localhost:'$port'/' | jq 2>/dev/null || echo "응답 없음"
        
        echo ""
      done
    fi
    
    sleep 30  # 30초마다 새로고침
  done
}


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
  sed "s|^WS_SERVER_URL=.*|WS_SERVER_URL=${NEW_URL}|" .env > .env.new
  mv .env.new .env
  
  echo -e "${GREEN}웹소켓 서버 URL이 업데이트되었습니다.${NC}"
  echo -e "${YELLOW}변경 사항을 적용하려면 모니터 서비스를 재시작하세요:${NC}"
  echo -e "${GREEN}monrestart${NC}"
}
# 파이썬 모니터링 관련 함수

# 모니터 시작
mstart() {
  echo -e "${BLUE}파이썬 모니터 서비스 시작 중...${NC}"
  docker compose -f docker-compose-mclient.yml up -d mclient
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}파이썬 모니터 서비스가 시작되었습니다.${NC}"
  else
    echo -e "${RED}파이썬 모니터 서비스 시작에 실패했습니다.${NC}"
  fi
}

# 모니터 중지
mstop() {
  echo -e "${BLUE}파이썬 모니터 서비스 중지 중...${NC}"
  docker compose -f docker-compose-mclient.yml stop mclient
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}파이썬 모니터 서비스가 중지되었습니다.${NC}"
  else
    echo -e "${RED}파이썬 모니터 서비스 중지에 실패했습니다.${NC}"
  fi
}

# 모니터 재시작
mrestart() {
  echo -e "${BLUE}파이썬 모니터 서비스 재시작 중...${NC}"
  
  # 분리된 mclient 파일 확인
  if [ -f "docker-compose-mclient.yml" ]; then
    docker compose -f docker-compose-mclient.yml restart mclient
  else
    echo -e "${RED}docker-compose-mclient.yml 파일이 없습니다.${NC}"
    return 1
  fi
  
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}파이썬 모니터 서비스가 재시작되었습니다.${NC}"
  else
    echo -e "${RED}파이썬 모니터 서비스 재시작에 실패했습니다.${NC}"
  fi
}

# 모니터 로그 확인
mlog() {
  echo -e "${BLUE}파이썬 모니터 서비스 로그 확인 중...${NC}"
  docker logs -f mclient
}

# 모니터 상태 확인
mstatus() {
  echo -e "${BLUE}파이썬 모니터 서비스 상태 확인 중...${NC}"
  if docker ps | grep -q "mclient"; then
    echo -e "${GREEN}파이썬 모니터 서비스가 실행 중입니다.${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "mclient"
  else
    echo -e "${RED}파이썬 모니터 서비스가 실행 중이 아닙니다.${NC}"
  fi
}

# 모니터 서버 URL 업데이트
murl() {
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: murl <새 웹소켓 URL>${NC}"
    echo -e "${YELLOW}예시: murl wss://monitor.example.com/ws${NC}"
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
  grep -v "^M_WS_SERVER_URL=" .env > .env.new
  echo "M_WS_SERVER_URL=${NEW_URL}" >> .env.new
  echo "M_WS_MODE=custom" >> .env.new
  mv .env.new .env
  
  echo -e "${GREEN}웹소켓 서버 URL이 업데이트되었습니다.${NC}"
  echo -e "${YELLOW}변경 사항을 적용하려면 모니터 서비스를 재시작하세요:${NC}"
  echo -e "${GREEN}mrestart${NC}"
}

# 노드 정리 함수 (2.x/3.x 통합)
cleanupnode() {
  local LEGACY_MODE=false
  local ALL_MODE=false
  
  # 옵션 파싱
  while [[ $# -gt 0 ]]; do
    case $1 in
      -l|--legacy)
        LEGACY_MODE=true
        shift
        ;;
      --all)
        ALL_MODE=true
        shift
        ;;
      -h|--help)
        echo "사용법: cleanupnode [옵션]"
        echo "옵션:"
        echo "  -l, --legacy    2.x 레거시 노드만 정리"
        echo "  --all           2.x와 3.x 모든 노드 정리"
        echo "  (옵션 없음)     3.x 노드만 정리 (기본값)"
        return 0
        ;;
      *)
        echo -e "${RED}알 수 없는 옵션: $1${NC}"
        return 1
        ;;
    esac
  done
  
  if [ "$ALL_MODE" = true ]; then
    echo -e "${RED}!!! 경고 !!!${NC}"
    echo -e "${YELLOW}이 명령은 모든 Creditcoin 노드 (2.x + 3.x)를 완전히 삭제합니다.${NC}"
  elif [ "$LEGACY_MODE" = true ]; then
    echo -e "${RED}!!! 경고 !!!${NC}"
    echo -e "${YELLOW}이 명령은 Creditcoin 2.x 레거시 노드를 완전히 삭제합니다.${NC}"
  else
    echo -e "${RED}!!! 경고 !!!${NC}"
    echo -e "${YELLOW}이 명령은 Creditcoin 3.x 노드를 완전히 삭제합니다.${NC}"
  fi
  
  echo -e "${RED}이 작업은 되돌릴 수 없습니다.${NC}"
  echo ""
  echo -n "계속 진행하시겠습니까? (y/N) "
  read response
  
  if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "${BLUE}작업이 취소되었습니다.${NC}"
    return 0
  fi
  
  # 2.x 정리
  if [ "$LEGACY_MODE" = true ] || [ "$ALL_MODE" = true ]; then
    echo -e "${BLUE}===== Creditcoin 2.x 레거시 노드 정리 =====${NC}"
    
    # 2.x 컨테이너 정리
    echo -e "${YELLOW}2.x node 컨테이너 중지 및 삭제...${NC}"
    local RUNNING_NODES=$(docker ps -a --format "{{.Names}}" | grep '^node[0-9]')
    if [ ! -z "$RUNNING_NODES" ]; then
      echo "$RUNNING_NODES" | xargs -r docker stop
      echo "$RUNNING_NODES" | xargs -r docker rm
      echo -e "${GREEN}2.x 컨테이너 정리 완료${NC}"
    fi
    
    # 2.x 이미지 정리
    echo -e "${YELLOW}creditcoin2 이미지 삭제...${NC}"
    local IMAGES=$(docker images | grep 'creditcoin2' | awk '{print $3}')
    if [ ! -z "$IMAGES" ]; then
      echo "$IMAGES" | xargs -r docker rmi -f
      echo -e "${GREEN}2.x 이미지 정리 완료${NC}"
    fi
    
    # 2.x 파일 정리
    echo -e "${YELLOW}2.x 파일 정리...${NC}"
    rm -rf ./node[0-9]*
    rm -f Dockerfile.legacy docker-compose-legacy.yml
    
    # 2.x 환경변수 정리
    if [ -f ".env.legacy" ]; then
      rm -f .env.legacy
      echo -e "${GREEN}2.x 환경변수 파일 정리 완료${NC}"
    fi
    
    echo -e "${GREEN}2.x 노드 정리 완료${NC}"
  fi
  
  # 3.x 정리
  if [ "$LEGACY_MODE" = false ] || [ "$ALL_MODE" = true ]; then
    echo -e "${BLUE}===== Creditcoin 3.x 노드 정리 =====${NC}"
    
    # 3.x 컨테이너 정리
    echo -e "${YELLOW}3.x 3node 컨테이너 중지 및 삭제...${NC}"
    local RUNNING_NODES=$(docker ps -a --format "{{.Names}}" | grep '^3node[0-9]')
    if [ ! -z "$RUNNING_NODES" ]; then
      echo "$RUNNING_NODES" | xargs -r docker stop
      echo "$RUNNING_NODES" | xargs -r docker rm
      echo -e "${GREEN}3.x 컨테이너 정리 완료${NC}"
    fi
    
    # 3.x 이미지 정리
    echo -e "${YELLOW}creditcoin3 이미지 삭제...${NC}"
    local IMAGES=$(docker images | grep 'creditcoin3' | awk '{print $3}')
    if [ ! -z "$IMAGES" ]; then
      echo "$IMAGES" | xargs -r docker rmi -f
      echo -e "${GREEN}3.x 이미지 정리 완료${NC}"
    fi
    
    # 3.x 파일 정리
    echo -e "${YELLOW}3.x 파일 정리...${NC}"
    rm -rf ./3node[0-9]* ./data
    rm -f Dockerfile docker-compose.yml
    
    # 3.x 환경변수 정리 (.env 파일은 3.x 전용이므로 삭제)
    if [ "$1" != "-l" ] && [ "$1" != "--legacy" ]; then
      rm -f .env
      echo -e "${GREEN}3.x 환경변수 파일 삭제 완료${NC}"
    fi
    
    echo -e "${GREEN}3.x 노드 정리 완료${NC}"
  fi
  
  # 공통 정리
  echo -e "${BLUE}===== Docker 캐시 정리 =====${NC}"
  docker builder prune -f
  docker volume prune -f
  docker network prune -f
  
  echo -e "${GREEN}노드 정리 완료!${NC}"
  echo ""
  echo -e "${BLUE}💡 mclient가 변경사항을 인지하도록 재시작: ${GREEN}mrestart${NC}"
}

# 백업 파일 정리 함수 (개선)
cleanupbak() {
  echo -e "${BLUE}백업 파일 검색 중...${NC}"
  
  # 다양한 백업 패턴 찾기
  local bak_files=$(find . -type f \( \
    -name "*.bak" -o \
    -name "*.bak.*" -o \
    -name "*.backup" -o \
    -name "*.orig" -o \
    -name "*.tmp" -o \
    -name "*~" \
  \) | sort)
  
  if [ -z "$bak_files" ]; then
    echo -e "${YELLOW}정리할 백업 파일이 없습니다.${NC}"
    return 0
  fi
  
  echo -e "${YELLOW}다음 백업 파일들을 삭제합니다:${NC}"
  echo "$bak_files" | while read file; do
    echo -e "  - $file"
  done
  
  echo ""
  echo -n "이 파일들을 삭제하시겠습니까? (y/N) "
  read response
  
  if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "$bak_files" | xargs rm -f
    echo -e "${GREEN}백업 파일이 정리되었습니다.${NC}"
  else
    echo -e "${BLUE}작업이 취소되었습니다.${NC}"
  fi
}

# 완전 정리 함수 (모든 것 삭제)
cleanupmc() {
  # 색상 정의
  local RED='\033[0;31m'
  local GREEN='\033[0;32m'
  local YELLOW='\033[1;33m'
  local BLUE='\033[0;34m'
  local NC='\033[0m'

  echo -e "${RED}!!! 경고 !!!${NC}"
  echo -e "${YELLOW}이 명령은 Creditcoin 모니터링 클라이언트를 완전히 삭제합니다:${NC}"
  echo -e " - mclient 컨테이너"
  echo -e " - mclient 이미지들"
  echo -e " - docker-compose-mclient.yml"
  echo -e " - .env.mclient 파일"
  echo -e "${RED}이 작업은 되돌릴 수 없습니다.${NC}"
  echo ""
  echo -e "${YELLOW}계속 진행하시겠습니까? (y/N)${NC}"
  read response
  
  if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "${BLUE}작업이 취소되었습니다.${NC}"
    return 0
  fi

  echo -e "${BLUE}===== mclient 정리 =====${NC}"
  
  # mclient 컨테이너 중지 및 삭제
  echo -e "${YELLOW}mclient 컨테이너 중지 및 삭제...${NC}"
  docker stop mclient 2>/dev/null || true
  docker rm mclient 2>/dev/null || true
  echo -e "${GREEN}mclient 컨테이너 정리 완료${NC}"
  
  # mclient 이미지 삭제
  echo -e "${YELLOW}mclient 이미지 삭제...${NC}"
  docker images | grep 'mclient' | awk '{print $3}' | xargs -r docker rmi -f
  echo -e "${GREEN}mclient 이미지 정리 완료${NC}"
  
  # mclient 관련 파일 삭제
  echo -e "${YELLOW}mclient 관련 파일 삭제...${NC}"
  rm -f docker-compose-mclient.yml
  rm -f .env.mclient
  echo -e "${GREEN}mclient 파일 정리 완료${NC}"
  
  # Docker 캐시 정리
  echo -e "${BLUE}===== Docker 캐시 정리 =====${NC}"
  docker builder prune -f
  
  echo -e "${GREEN}mclient 정리 완료!${NC}"
}

cleanupall() {
  echo -e "${RED}!!! 완전 정리 경고 !!!${NC}"
  echo -e "${YELLOW}이 명령은 다음을 모두 삭제합니다:${NC}"
  echo -e " - 모든 Creditcoin 노드 (2.x + 3.x)"
  echo -e " - 모든 Docker 이미지 및 캐시"
  echo -e " - 모든 백업 파일"
  echo -e " - 모니터링 클라이언트 (mclient)"
  echo -e " - .env 파일"
  echo -e " - zshrc 환경변수"
  echo ""
  echo -e "${RED}이 작업은 완전히 되돌릴 수 없습니다!${NC}"
  echo ""
  echo -n "정말로 모든 것을 삭제하시겠습니까? (y/N) "
  read response
  
  if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "${BLUE}작업이 취소되었습니다.${NC}"
    return 0
  fi
  
  echo -e "${BLUE}===== 완전 정리 시작 =====${NC}"
  
  # 1. 모든 노드 정리 (백업 안내 없이)
  echo -e "${YELLOW}1단계: 모든 노드 정리...${NC}"
  # 모든 컨테이너 중지 및 삭제
  docker ps -a --format "{{.Names}}" | grep -E '^(node|3node)[0-9]' | xargs -r docker stop
  docker ps -a --format "{{.Names}}" | grep -E '^(node|3node)[0-9]' | xargs -r docker rm
  
  # 모든 이미지 삭제
  docker images | grep -E 'creditcoin[23]' | awk '{print $3}' | xargs -r docker rmi -f
  
  # 2. 모니터링 클라이언트 정리
  echo -e "${YELLOW}2단계: 모니터링 클라이언트 정리...${NC}"
  docker stop mclient 2>/dev/null || true
  docker rm mclient 2>/dev/null || true
  docker images | grep 'mclient' | awk '{print $3}' | xargs -r docker rmi -f
  # mclient 폴더는 보존하고 내용물만 정리 (환경설정 파일 제외)
  if [ -d "./mclient" ]; then
    echo -e "${BLUE}mclient 폴더 내용 정리 중... (소스코드는 보존)${NC}"
    rm -f ./mclient/.env.bak ./mclient/*.log ./mclient/__pycache__/* 2>/dev/null || true
    rm -rf ./mclient/venv 2>/dev/null || true
  fi
  
  # 3. 파일 시스템 정리
  echo -e "${YELLOW}3단계: 파일 시스템 정리...${NC}"
  rm -rf ./node[0-9]* ./3node[0-9]* ./data ./mserver
  rm -f Dockerfile Dockerfile.legacy docker-compose*.yml .env .env.legacy .env.mclient
  
  # 4. 백업 파일 정리
  echo -e "${YELLOW}4단계: 백업 파일 정리...${NC}"
  find . -type f \( \
    -name "*.bak" -o \
    -name "*.bak.*" -o \
    -name "*.backup" -o \
    -name "*.orig" -o \
    -name "*.tmp" -o \
    -name "*~" \
  \) -delete
  
  # 5. zshrc 환경변수 정리
  echo -e "${YELLOW}5단계: zshrc 환경변수 정리...${NC}"
  if [ -f ~/.zshrc ]; then
    # Creditcoin 관련 환경변수 제거
    sed -i.bak '/# Creditcoin/,/^$/d; /CREDITCOIN_DIR/d; /HOST_MAC_ADDRESS/d; /HOST_SYSTEM_NAME/d; /HOST_MODEL/d; /HOST_PROCESSOR/d; /HOST_CPU/d; /HOST_MEMORY/d; /HOST_DISK/d' ~/.zshrc
    echo -e "${GREEN}zshrc 환경변수 정리 완료${NC}"
  fi
  
  # 6. Docker 캐시 완전 정리
  echo -e "${YELLOW}6단계: Docker 완전 정리...${NC}"
  docker system prune -af
  docker volume prune -f
  docker network prune -f
  
  echo -e "${BLUE}===== 완전 정리 완료 =====${NC}"
  echo -e "${GREEN}모든 Creditcoin 관련 데이터가 삭제되었습니다.${NC}"
  echo -e "${YELLOW}zshrc 변경사항을 적용하려면 다음 명령을 실행하세요:${NC}"
  echo -e "${GREEN}source ~/.zshrc${NC}"
}

# zshrc 편집 및 업데이트 함수
editz() {
  nano ~/.zshrc
}

updatez() {
  source ~/.zshrc
  echo "zshrc가 업데이트되었습니다."
}

# mclient 인증 함수
mauth() {
  docker compose -f $CREDITCOIN_DIR/docker-compose-mclient.yml run --rm --entrypoint "python3 /app/mauth.py" mclient
}

# 노드 제거 함수
removenode() {
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: removenode <노드명>${NC}"
    echo -e "${YELLOW}예시: removenode node1, removenode 3node0${NC}"
    return 1
  fi
  
  $CREDITCOIN_DIR/removenode.sh "$1"
}

# mclient 한 틱 데이터를 JSON으로 출력
mtick() {
  # mclient 실행 중인지 확인
  if ! docker ps --format "{{.Names}}" | grep -q "^mclient$"; then
    echo -e "${RED}Error: mclient is not running${NC}"
    return 1
  fi
  
  # mclient가 마지막으로 보낸 데이터 읽기 (컨테이너 내부에서)
  local data=$(docker exec mclient cat /tmp/mclient_last_send.json 2>/dev/null)
  
  if [ -z "$data" ]; then
    echo -e "${YELLOW}No data available yet. Make sure mclient has sent at least one message.${NC}"
    return 1
  fi
  
  # jq로 예쁘게 출력 (컬러 포함)
  echo "$data" | jq -C '.'
}

# =================================================
# 프롬프트 설정 관련
# =================================================

# ZSH 프롬프트 설정 내용
_PROMPT_CONFIG='
# =================================================
# 커스텀 프롬프트 설정 (by setupomz)
# =================================================

# Oh My Zsh 기본 설정
export ZSH="$HOME/.oh-my-zsh"

# 테마 설정 (커스텀 프롬프트를 위해 비활성화)
ZSH_THEME=""

# 플러그인 설정
plugins=(git)

# Oh My Zsh 로드
source $ZSH/oh-my-zsh.sh

# 커스텀 프롬프트 설정
# Git 프롬프트 설정
ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_bold[blue]%}git:(%{$fg[red]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%} "
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[blue]%}) %{$fg[yellow]%}✗"
ZSH_THEME_GIT_PROMPT_CLEAN="%{$fg[blue]%})"

# 프롬프트 설정 - 원격지에서는 호스트명을 노란색으로
setopt PROMPT_SUBST
if [ -n "$SSH_CONNECTION" ]; then
  PROMPT='%{$fg_bold[yellow]%}%m%{$reset_color%} > %{$fg_bold[cyan]%}%c%{$reset_color%} $(git_prompt_info)'
else
  PROMPT='%{$fg_bold[green]%}%m%{$reset_color%} > %{$fg_bold[cyan]%}%c%{$reset_color%} $(git_prompt_info)'
fi

# LS 색상 설정
export LS_COLORS="di=1;36:ln=1;35:so=1;32:pi=1;33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=34;43"

# 별칭 설정
alias ls="ls -G"
alias ll="ls -alF"  
alias la="ls -A"
alias l="ls -CF"
alias grep="grep --color=auto"
'


# =================================================
# ZSH와 oh-my-zsh 설치 스크립트
# =================================================

# ZSH 프롬프트 설정 함수
setupomz() {
  if [ $# -eq 0 ]; then
    # 인자가 없으면 로컬 설치
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}     로컬 ZSH 프롬프트 커스터마이징${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo ""
    
    # oh-my-zsh 설치 확인
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
      echo -e "${YELLOW}oh-my-zsh가 설치되어 있지 않습니다.${NC}"
      echo -e "${BLUE}oh-my-zsh를 설치합니다...${NC}"
      
      # RUNZSH=no를 설정하여 설치 후 자동으로 zsh가 실행되지 않도록 함
      RUNZSH=no sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || {
        echo -e "${RED}oh-my-zsh 설치 실패${NC}"
        return 1
      }
      
      echo -e "${GREEN}oh-my-zsh 설치 완료!${NC}"
    fi
    
    # 백업 생성
    if [ -f "$HOME/.zshrc" ]; then
      local BACKUP_FILE="$HOME/.zshrc.backup.$(date +%Y%m%d_%H%M%S)"
      echo -e "${BLUE}기존 .zshrc 파일을 백업합니다...${NC}"
      cp "$HOME/.zshrc" "$BACKUP_FILE"
      echo -e "${GREEN}백업 완료: $BACKUP_FILE${NC}"
    fi
    
    # 기존 프롬프트 설정 확인
    if grep -q "커스텀 프롬프트 설정" "$HOME/.zshrc" 2>/dev/null; then
      echo -e "${YELLOW}이미 커스텀 프롬프트가 설정되어 있습니다.${NC}"
      echo ""
      echo "어떻게 하시겠습니까?"
      echo "1) 덮어쓰기"
      echo "2) 취소"
      echo ""
      read -p "선택 (1): " choice
      
      if [ -z "$choice" ]; then
        choice="1"
      fi
      
      case $choice in
        1)
          # 기존 설정 제거
          sed -i.tmp '/커스텀 프롬프트 설정/,/^fi$/d' "$HOME/.zshrc" 2>/dev/null || true
          sed -i.tmp '/# LS 색상 설정/,/alias l=/d' "$HOME/.zshrc" 2>/dev/null || true
          rm -f "$HOME/.zshrc.tmp"
          echo -e "${YELLOW}기존 설정을 제거했습니다.${NC}"
          ;;
        2)
          echo -e "${GREEN}취소되었습니다.${NC}"
          return 0
          ;;
        *)
          echo -e "${RED}잘못된 선택입니다. 종료합니다.${NC}"
          return 1
          ;;
      esac
    fi
    
    # 프롬프트 설정 추가
    echo -e "${BLUE}프롬프트 설정을 추가합니다...${NC}"
    echo "$_PROMPT_CONFIG" >> "$HOME/.zshrc"
    
    # 호스트명 설정 옵션
    echo ""
    echo -e "${YELLOW}호스트명을 설정하시겠습니까?${NC}"
    echo -e "${CYAN}(SSH 접속 시 구분하기 쉽도록 짧은 이름 권장)${NC}"
    echo ""
    echo "1) 현재 호스트명 유지 ($(hostname -s))"
    echo "2) 새 호스트명 설정"
    echo ""
    read -p "선택 (1): " hostname_choice
    
    if [ -z "$hostname_choice" ]; then
      hostname_choice="1"
    fi
    
    case $hostname_choice in
      2)
        echo ""
        read -p "새 호스트명 입력 (예: D01, N01): " new_hostname
        if [ -n "$new_hostname" ]; then
          echo -e "${YELLOW}호스트명 변경은 관리자 권한이 필요합니다.${NC}"
          if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sudo scutil --set HostName "$new_hostname"
            sudo scutil --set LocalHostName "$new_hostname"
            sudo scutil --set ComputerName "$new_hostname"
            dscacheutil -flushcache
          else
            # Linux
            sudo hostnamectl set-hostname "$new_hostname"
          fi
          echo -e "${GREEN}호스트명이 '$new_hostname'로 변경되었습니다.${NC}"
        fi
        ;;
    esac
    
    echo ""
    echo -e "${GREEN}=====================================================${NC}"
    echo -e "${GREEN}프롬프트 설정이 완료되었습니다!${NC}"
    echo -e "${GREEN}=====================================================${NC}"
    echo ""
    echo -e "${YELLOW}변경사항을 적용하려면:${NC}"
    echo -e "${BLUE}source ~/.zshrc${NC}"
    echo ""
    
    # 바로 적용
    source ~/.zshrc
    echo -e "${GREEN}프롬프트가 적용되었습니다!${NC}"
    
  else
    # 인자가 있으면 원격 서버 설치
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}     원격 서버 ZSH 환경 자동 설정${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo ""
    
    # 각 호스트에 대해 설정
    for host in "$@"; do
      echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
      echo -e "${YELLOW}$host 서버 설정 시작${NC}"
      echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
      
      # SSH 연결 테스트
      if ! ssh -o ConnectTimeout=5 "$host" "echo ''" &>/dev/null; then
        echo -e "${RED}✗ $host 연결 실패${NC}"
        continue
      fi
      
      # 1. 필수 패키지 확인
      echo -e "${BLUE}1. 필수 패키지 확인...${NC}"
      local missing_packages=""
      
      # zsh 확인
      if ! ssh "$host" "which zsh" &>/dev/null; then
        missing_packages="zsh"
      fi
      
      # git 확인
      if ! ssh "$host" "which git" &>/dev/null; then
        missing_packages="$missing_packages git"
      fi
      
      # curl 확인
      if ! ssh "$host" "which curl" &>/dev/null; then
        missing_packages="$missing_packages curl"
      fi
      
      if [ -n "$missing_packages" ]; then
        echo -e "${YELLOW}  필요한 패키지가 없습니다: $missing_packages${NC}"
        
        # sudo 권한 체크
        if ssh "$host" "sudo -n true" 2>/dev/null; then
          echo -e "${BLUE}  패키지 자동 설치를 시도합니다...${NC}"
          ssh -t "$host" "
            if [ -f /etc/debian_version ]; then
              sudo apt-get update && sudo apt-get install -y $missing_packages
            elif [ -f /etc/redhat-release ]; then
              sudo yum install -y $missing_packages
            elif [ -f /etc/arch-release ]; then
              sudo pacman -S --noconfirm $missing_packages
            fi
          "
          if [ $? -ne 0 ]; then
            echo -e "${RED}  ✗ 패키지 설치 실패${NC}"
            echo -e "${YELLOW}  서버에 직접 접속하여 설치해주세요:${NC}"
            echo -e "${BLUE}  ssh $host${NC}"
            echo -e "${BLUE}  sudo apt-get install -y zsh git curl  # Ubuntu/Debian${NC}"
            echo -e "${BLUE}  sudo yum install -y zsh git curl      # RedHat/CentOS${NC}"
            continue
          fi
        else
          echo -e "${YELLOW}  sudo 권한이 필요합니다. 서버에 직접 접속하여 설치해주세요:${NC}"
          echo -e "${BLUE}  ssh $host${NC}"
          echo -e "${BLUE}  sudo apt-get install -y zsh git curl  # Ubuntu/Debian${NC}"
          echo -e "${BLUE}  sudo yum install -y zsh git curl      # RedHat/CentOS${NC}"
          echo ""
          echo -e "${YELLOW}  또는 -t 옵션으로 재시도: setupomz -t $host${NC}"
          continue
        fi
      else
        echo -e "${GREEN}  ✓ 필수 패키지 모두 설치됨${NC}"
      fi
      
      # 2. oh-my-zsh 설치
      echo -e "${BLUE}2. oh-my-zsh 설치 확인...${NC}"
      if ! ssh "$host" "[ -d ~/.oh-my-zsh ]" &>/dev/null; then
        echo -e "${YELLOW}  oh-my-zsh가 없습니다. 설치 중...${NC}"
        ssh "$host" '
          export RUNZSH=no
          export CHSH=no
          sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
        '
        if [ $? -eq 0 ]; then
          echo -e "${GREEN}  ✓ oh-my-zsh 설치 완료${NC}"
        else
          echo -e "${RED}  ✗ oh-my-zsh 설치 실패${NC}"
          continue
        fi
      else
        echo -e "${GREEN}  ✓ oh-my-zsh 이미 설치됨${NC}"
      fi
      
      # 3. .zshrc 백업
      echo -e "${BLUE}3. 기존 설정 백업...${NC}"
      ssh "$host" "[ -f ~/.zshrc ] && cp ~/.zshrc ~/.zshrc.backup.\$(date +%Y%m%d_%H%M%S)"
      echo -e "${GREEN}  ✓ 백업 완료${NC}"
      
      # 4. 기본 .zshrc 설정 (oh-my-zsh가 없으면)
      echo -e "${BLUE}4. 기본 설정 확인...${NC}"
      ssh "$host" '
        if ! grep -q "oh-my-zsh" ~/.zshrc 2>/dev/null; then
          cat > ~/.zshrc << "ZSHRC"
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source $ZSH/oh-my-zsh.sh
ZSHRC
        fi
      '
      echo -e "${GREEN}  ✓ 기본 설정 완료${NC}"
      
      # 5. 프롬프트 설정 추가
      echo -e "${BLUE}5. 프롬프트 설정 추가...${NC}"
      ssh "$host" "
        # 기존 커스텀 프롬프트 설정 제거
        sed -i '/커스텀 프롬프트 설정/,/^fi$/d' ~/.zshrc 2>/dev/null || true
        
        # 새 프롬프트 설정 추가
        echo '$_PROMPT_CONFIG' >> ~/.zshrc
      "
      echo -e "${GREEN}  ✓ 프롬프트 설정 완료${NC}"
      
      # 6. 기본 쉘 변경 (선택사항)
      echo -e "${BLUE}6. 기본 쉘 변경...${NC}"
      ssh "$host" '
        if [ "$SHELL" != "/bin/zsh" ] && [ "$SHELL" != "/usr/bin/zsh" ]; then
          echo "  기본 쉘을 zsh로 변경하려면 다음 명령을 실행하세요:"
          echo "  chsh -s $(which zsh)"
        else
          echo "  ✓ 이미 zsh가 기본 쉘입니다"
        fi
      '
      
      echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
      echo -e "${GREEN}✓ $host 설정 완료!${NC}"
      echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
      echo ""
    done
    
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${GREEN}모든 서버 설정이 완료되었습니다!${NC}"
    echo -e "${CYAN}=====================================================${NC}"
    echo ""
    echo -e "${YELLOW}각 서버에 다시 접속하면 새 프롬프트가 적용됩니다:${NC}"
    echo -e "${GREEN}D01 > creditcoin-docker git:(main)${NC}"
    echo ""
    echo -e "${CYAN}팁: 기본 쉘을 zsh로 변경하려면 각 서버에서:${NC}"
    echo -e "${BLUE}chsh -s \$(which zsh)${NC}"
  fi
}

# 프롬프트 설정 도움말
setupomz-help() {
  echo -e "${BLUE}=====================================================${NC}"
  echo -e "${GREEN}     oh-my-zsh 프롬프트 설정 명령어${NC}"
  echo -e "${BLUE}=====================================================${NC}"
  echo ""
  echo -e "${YELLOW}setupomz${NC}"
  echo -e "  - 로컬 컴퓨터의 프롬프트를 설정합니다"
  echo -e "  - 형식: ${GREEN}N01${NC} > ${CYAN}creditcoin-docker${NC} ${BLUE}git:(${RED}main${BLUE})${NC}"
  echo ""
  echo -e "${YELLOW}setupomz <host1> [host2...]${NC}"
  echo -e "  - 원격 서버의 프롬프트를 설정합니다"
  echo -e "  - zsh와 oh-my-zsh를 자동으로 설치합니다"
  echo -e "  - 예시: setupomz D01 D02"
  echo ""
  echo -e "${CYAN}프롬프트 색상:${NC}"
  echo -e "  - 호스트명: ${GREEN}초록색${NC}"
  echo -e "  - 현재 폴더: ${CYAN}청록색${NC}"
  echo -e "  - Git 정보: ${BLUE}파란색${NC}"
  echo ""
}



