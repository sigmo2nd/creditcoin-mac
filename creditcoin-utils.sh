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
alias editdf='open -e ${CREDITCOIN_DIR}/Dockerfile'
alias editdfl='open -e ${CREDITCOIN_DIR}/Dockerfile.legacy'
alias editenv='open -e ${CREDITCOIN_DIR}/.env'

# Docker 컨테이너 관리
drestart() { 
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: drestart <컨테이너명>${NC}"
    return 1
  fi
  echo -e "${BLUE}컨테이너 재시작 중: $1${NC}"
  docker restart $1
  echo -e "${GREEN}컨테이너가 재시작되었습니다: $1${NC}"
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

# 시간 동기화 상태 확인 및 강제 동기화
checktimeserver() {
  echo -e "${BLUE}시스템 시간 서버 확인 중...${NC}"
  
  # 현재 시간 서버 확인
  current_server=$(sudo systemsetup -getnetworktimeserver 2>/dev/null | awk -F ': ' '{print $2}')
  network_time_enabled=$(sudo systemsetup -getusingnetworktime 2>/dev/null | grep -q "On" && echo "yes" || echo "no")
  
  if [[ "$current_server" == "(null)" || "$current_server" == "" ]]; then
    echo -e "${RED}⚠️ 경고: 시간 서버가 설정되어 있지 않습니다!${NC}"
    echo -e "${YELLOW}블록체인 노드 운영에는 정확한 시간 동기화가 필수적입니다.${NC}"
    
    echo -e "${YELLOW}자동으로 시간 서버를 설정하시겠습니까? (Y/n)${NC}"
    read response
    if [[ ! "$response" =~ ^([nN][oO]|[nN])$ ]]; then
      sudo systemsetup -setnetworktimeserver time.apple.com
      sudo systemsetup -setusingnetworktime on
      
      echo -e "${YELLOW}시간 서비스 재시작 중...${NC}"
      sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.timed.plist 2>/dev/null
      sleep 5
      sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.timed.plist
      
      echo -e "${YELLOW}시간 강제 동기화 중...${NC}"
      sudo sntp -sS time.apple.com
      
      echo -e "${GREEN}시간 서버가 time.apple.com(자동 지역 감지)으로 설정되었습니다.${NC}"
    else
      echo -e "${RED}시간 서버를 설정하지 않았습니다. 블록체인 노드 운영에 문제가 발생할 수 있습니다.${NC}"
    fi
  elif [[ "$network_time_enabled" != "yes" ]]; then
    echo -e "${RED}⚠️ 경고: 네트워크 시간 동기화가 비활성화되어 있습니다!${NC}"
    echo -e "${YELLOW}네트워크 시간 동기화를 활성화하시겠습니까? (Y/n)${NC}"
    read response
    if [[ ! "$response" =~ ^([nN][oO]|[nN])$ ]]; then
      sudo systemsetup -setusingnetworktime on
      
      echo -e "${YELLOW}시간 서비스 재시작 중...${NC}"
      sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.timed.plist 2>/dev/null
      sleep 5
      sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.timed.plist
      
      echo -e "${YELLOW}시간 강제 동기화 중...${NC}"
      sudo sntp -sS "$current_server"
      
      echo -e "${GREEN}네트워크 시간 동기화가 활성화되었습니다.${NC}"
    else
      echo -e "${RED}네트워크 시간 동기화가 비활성화된 상태로 유지됩니다. 블록체인 노드 운영에 문제가 발생할 수 있습니다.${NC}"
    fi
  else
    echo -e "${GREEN}시간 서버: $current_server${NC}"
    echo -e "${GREEN}네트워크 시간 동기화: 활성화됨${NC}"
    
    # 강제 시간 동기화 제안
    echo -e "${YELLOW}시간을 강제로 동기화하시겠습니까? (Y/n)${NC}"
    read sync_response
    if [[ ! "$sync_response" =~ ^([nN][oO]|[nN])$ ]]; then
      echo -e "${YELLOW}시간 강제 동기화 중...${NC}"
      sudo sntp -sS "$current_server"
      echo -e "${GREEN}시간이 강제로 동기화되었습니다.${NC}"
    fi
  fi
  
  # 현재 시간 표시
  echo -e "${GREEN}현재 시스템 시간: $(date)${NC}"
  echo -e "${GREEN}현재 UTC 시간: $(date -u)${NC}"
}

# 전원 관리 설정 최적화
optimizepower() {
  echo -e "${BLUE}전원 관리 설정 최적화${NC}"
  
  # 현재 설정 확인
  echo -e "${YELLOW}현재 전원 관리 설정:${NC}"
  pmset -g
  
  # 최적화 여부 물어보기
  echo -e "${YELLOW}블록체인 노드 운영에 최적화된 전원 설정을 적용하시겠습니까? (Y/n)${NC}"
  read response
  if [[ ! "$response" =~ ^([nN][oO]|[nN])$ ]]; then
    echo -e "${YELLOW}최적화된 전원 설정을 적용합니다...${NC}"
    
    # 전원 관리 설정 (즉시 적용)
    sudo pmset -a displaysleep 10  # 디스플레이만 10분 후 절전
    sudo pmset -a sleep 0          # 시스템 절전 비활성화
    sudo pmset -a disksleep 0      # 디스크 절전 비활성화
    sudo pmset -a standby 0        # 대기 모드 비활성화
    sudo pmset -a autopoweroff 0   # 자동 전원 끄기 비활성화
    sudo pmset -a powernap 0       # PowerNap 비활성화
    sudo pmset -a ttyskeepawake 1  # SSH 세션 활성화 시 깨어있음
    sudo pmset -a tcpkeepalive 1   # TCP 연결 유지
    sudo pmset -a networkoversleep 0  # 네트워크 연결 유지
    
    echo -e "${GREEN}전원 관리 설정이 최적화되었습니다.${NC}"
    echo -e "${YELLOW}새 설정:${NC}"
    pmset -g
  else
    echo -e "${YELLOW}전원 관리 설정 최적화를 건너뛰었습니다.${NC}"
    echo -e "${YELLOW}블록체인 노드를 24/7 운영하려면 전원 관리 설정 최적화를 권장합니다.${NC}"
  fi
}

# 노드 로그 모니터링 함수
monitorlog() {
  if [ -z "$1" ]; then
    echo -e "${YELLOW}사용법: monitorlog <노드명> [키워드]${NC}"
    echo -e "${YELLOW}예시: monitorlog 3node0${NC}"
    echo -e "${YELLOW}예시: monitorlog 3node0 \"too far\"${NC}"
    return 1
  fi
  
  local node=$1
  local keyword=$2
  
  # 노드 존재 확인
  if ! docker ps -a | grep -q "$node"; then
    echo -e "${RED}오류: $node 노드가 존재하지 않습니다.${NC}"
    return 1
  fi
  
  echo -e "${BLUE}$node 노드 로그 모니터링 중...${NC}"
  
  if [ -z "$keyword" ]; then
    # 키워드 없이 전체 로그 실시간 모니터링
    docker logs -f $node
  else
    # 키워드 포함된 로그만 실시간 모니터링
    echo -e "${YELLOW}키워드 \"$keyword\"가 포함된 로그만 표시합니다.${NC}"
    docker logs -f $node | grep -i "$keyword"
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

# 시스템 성능 요약 표시
sysinfo() {
  echo -e "${BLUE}===== 시스템 성능 요약 =====${NC}"
  
  echo -e "${YELLOW}CPU 사용량:${NC}"
  top -l 1 | grep -E "^CPU" | head -1
  
  echo -e "${YELLOW}메모리 사용량:${NC}"
  vm_stat | grep "Pages free:" | awk '{print "Free memory: " $3 " pages (" $3 * 4096 / 1048576 " MB)"}'
  vm_stat | grep "Pages active:" | awk '{print "Active memory: " $3 " pages (" $3 * 4096 / 1048576 " MB)"}'
  
  echo -e "${YELLOW}디스크 사용량:${NC}"
  df -h . | grep -v "Filesystem"
  
  echo -e "${YELLOW}Docker 컨테이너 리소스 사용량:${NC}"
  docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
  
  echo -e "${YELLOW}네트워크 연결:${NC}"
  netstat -an | grep -E "ESTABLISHED|LISTEN" | wc -l | awk '{print $1 " active connections"}'
  
  echo -e "${YELLOW}현재 시간 설정:${NC}"
  echo "시스템 시간: $(date)"
  echo "UTC 시간: $(date -u)"
  echo "시간 서버: $(sudo systemsetup -getnetworktimeserver 2>/dev/null || echo "확인 불가")"
  echo "네트워크 시간 동기화: $(sudo systemsetup -getusingnetworktime 2>/dev/null || echo "확인 불가")"
  
  echo -e "${YELLOW}전원 관리 설정:${NC}"
  pmset -g | grep -E "displaysleep|sleep|disksleep|standby|autopoweroff"
}

# 전체 시스템 및 노드 최적화
optimize() {
  echo -e "${BLUE}===== 시스템 및 노드 최적화 =====${NC}"
  
  # 시간 서버 확인 및 설정
  checktimeserver
  
  # 전원 관리 설정
  optimizepower
  
  # Docker 시스템 프루닝
  echo -e "${YELLOW}Docker 시스템 프루닝을 실행하시겠습니까? (불필요한 이미지, 컨테이너, 볼륨 정리) (Y/n)${NC}"
  read response
  if [[ ! "$response" =~ ^([nN][oO]|[nN])$ ]]; then
    echo -e "${YELLOW}Docker 시스템 프루닝 중...${NC}"
    docker system prune -f
    echo -e "${GREEN}Docker 시스템 프루닝 완료${NC}"
  fi
  
  # 로그 정리
  echo -e "${YELLOW}Docker 컨테이너 로그 파일을 정리하시겠습니까? (Y/n)${NC}"
  read response
  if [[ ! "$response" =~ ^([nN][oO]|[nN])$ ]]; then
    echo -e "${YELLOW}Docker 컨테이너 로그 정리 중...${NC}"
    for CONTAINER_ID in $(docker ps -a -q); do
      CONTAINER_NAME=$(docker inspect --format '{{.Name}}' $CONTAINER_ID | sed 's/\///')
      echo -e "${YELLOW}컨테이너 $CONTAINER_NAME 로그 정리 중...${NC}"
      if [ -f "$(docker inspect --format='{{.LogPath}}' $CONTAINER_ID)" ]; then
        cat /dev/null > $(docker inspect --format='{{.LogPath}}' $CONTAINER_ID)
        echo -e "${GREEN}로그 정리 완료: $CONTAINER_NAME${NC}"
      else
        echo -e "${YELLOW}로그 파일을 찾을 수 없습니다: $CONTAINER_NAME${NC}"
      fi
    done
    echo -e "${GREEN}모든 컨테이너 로그 정리 완료${NC}"
  fi
  
  # 피어 차단 목록 초기화
  echo -e "${YELLOW}모든 노드의 피어 차단 목록을 초기화하시겠습니까? (Y/n)${NC}"
  read response
  if [[ ! "$response" =~ ^([nN][oO]|[nN])$ ]]; then
    echo -e "${YELLOW}피어 차단 목록 초기화 중...${NC}"
    
    # 실행 중인 노드 검색
    local nodes=$(docker ps --format "{{.Names}}" | grep -E "^(3node|node)[0-9]+")
    
    if [ -z "$nodes" ]; then
      echo -e "${RED}실행 중인 Creditcoin 노드가 없습니다.${NC}"
    else
      for node in $nodes; do
        echo -e "${YELLOW}노드 $node 중지 중...${NC}"
        docker stop $node
        
        # 노드 타입 확인
        if [[ $node == 3node* ]]; then
          echo -e "${YELLOW}Creditcoin 3.0 노드 피어 데이터베이스 초기화 중: $node${NC}"
          # 백업 디렉토리 생성
          mkdir -p "./$node/data/chains/creditcoin3/network/backup_$(date +%Y%m%d)"
          # 파일 백업
          cp -r "./$node/data/chains/creditcoin3/network/"* "./$node/data/chains/creditcoin3/network/backup_$(date +%Y%m%d)/" 2>/dev/null
          # 피어 파일 삭제
          rm -f "./$node/data/chains/creditcoin3/network/peers" "./$node/data/chains/creditcoin3/network/not_connected_peers"
        elif [[ $node == node* ]]; then
          echo -e "${YELLOW}Creditcoin 2.0 노드 피어 데이터베이스 초기화 중: $node${NC}"
          # 백업 디렉토리 생성
          mkdir -p "./$node/data/chains/creditcoin/network/backup_$(date +%Y%m%d)"
          # 파일 백업
          cp -r "./$node/data/chains/creditcoin/network/"* "./$node/data/chains/creditcoin/network/backup_$(date +%Y%m%d)/" 2>/dev/null
          # 피어 파일 삭제
          rm -f "./$node/data/chains/creditcoin/network/peers" "./$node/data/chains/creditcoin/network/not_connected_peers"
        fi
        
        echo -e "${GREEN}피어 데이터베이스 초기화 완료: $node${NC}"
      done
      
      # 모든 노드 재시작
      echo -e "${YELLOW}모든 노드 재시작 중...${NC}"
      for node in $nodes; do
        echo -e "${YELLOW}노드 시작 중: $node${NC}"
        docker start $node
      done
      echo -e "${GREEN}모든 노드 재시작 완료${NC}"
    fi
  fi
  
  echo -e "${GREEN}최적화가 완료되었습니다!${NC}"
  echo -e "${YELLOW}최적의 성능을 위해 시스템을 재부팅하는 것이 좋습니다.${NC}"
}