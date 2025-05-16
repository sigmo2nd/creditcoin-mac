#!/bin/bash
# addmclient.sh - Creditcoin 모니터링 클라이언트 추가 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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

# 도움말 표시 함수
show_help() {
  echo "사용법: $0 [옵션]"
  echo ""
  echo "옵션:"
  echo "  -s, --server-id    서버 ID (기본값: server1)"
  echo "  -n, --node-names   모니터링할 노드 이름 목록 (쉼표로 구분, 기본값: node,3node)"
  echo "  -i, --interval     모니터링 간격(초) (기본값: 5)"
  echo "  -w, --ws-mode      웹소켓 모드 (auto, ws, wss, wss_internal) (기본값: auto)"
  echo "  -u, --ws-url       사용자 지정 웹소켓 URL (기본값: 없음)"
  echo "  -c, --creditcoin   Creditcoin 디렉토리 (기본값: 현재 디렉토리)"
  echo "  -f, --force        기존 설정 덮어쓰기"
  echo "  -h, --help         도움말 표시"
  echo ""
  echo "사용 예시:"
  echo "  ./addmclient.sh                        # 기본 설정으로 모니터 설치"
  echo "  ./addmclient.sh -s server2             # 다른 서버 ID로 설치"
  echo "  ./addmclient.sh -n node0,node1,3node0  # 특정 노드만 모니터링"
  echo "  ./addmclient.sh -i 10                  # 10초 간격으로 모니터링"
  echo "  ./addmclient.sh -w wss                 # WSS 모드로 연결"
  echo "  ./addmclient.sh -u wss://example.com/ws  # 지정된 웹소켓 서버 사용"
  echo ""
}

# 기본값 설정
SERVER_ID="server1"
NODE_NAMES="node,3node"
MONITOR_INTERVAL="5"
WS_MODE="auto"
WS_SERVER_URL=""
CREDITCOIN_DIR=$(pwd)
FORCE=false

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
    -w|--ws-mode)
      if [[ "$2" == "auto" || "$2" == "ws" || "$2" == "wss" || "$2" == "wss_internal" ]]; then
        WS_MODE="$2"
        shift 2
      else
        echo -e "${RED}오류: 유효하지 않은 웹소켓 모드입니다. auto, ws, wss, wss_internal 중 하나를 사용하세요.${NC}"
        exit 1
      fi
      ;;
    -u|--ws-url)
      WS_SERVER_URL="$2"
      WS_MODE="custom"
      shift 2
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

echo -e "${BLUE}Creditcoin 파이썬 모니터링 설정:${NC}"
echo -e "${GREEN}- 서버 ID: $SERVER_ID${NC}"
echo -e "${GREEN}- 모니터링 노드: $NODE_NAMES${NC}"
echo -e "${GREEN}- 모니터링 간격: ${MONITOR_INTERVAL}초${NC}"
echo -e "${GREEN}- WebSocket 모드: $WS_MODE${NC}"
if [ -n "$WS_SERVER_URL" ]; then
  echo -e "${GREEN}- WebSocket URL: $WS_SERVER_URL${NC}"
fi
echo -e "${GREEN}- Creditcoin 디렉토리: $CREDITCOIN_DIR${NC}"

# 현재 디렉토리
CURRENT_DIR=$(pwd)

# 환경 변수 안전하게 업데이트 함수
update_env_file() {
  # 백업 생성
  if [ -f ".env" ]; then
    echo -e "${BLUE}기존 .env 파일 백업 중...${NC}"
    cp .env ".env.bak.$(date +%Y%m%d%H%M%S)"
  fi
  
  # 새 .env 파일 생성
  echo -e "${BLUE}새 .env 파일 생성 중...${NC}"
  
  # 기존 .env 파일에서 mclient 관련 변수를 제외한 내용 추출
  if [ -f ".env" ]; then
    grep -v "^M_SERVER_ID=\|^M_NODE_NAMES=\|^M_MONITOR_INTERVAL=\|^M_WS_MODE=\|^M_WS_SERVER_URL=\|^M_CREDITCOIN_DIR=" .env > .env.tmp
  else
    touch .env.tmp
  fi
  
  # 모니터링 변수 추가 (충돌 방지를 위해 M_ 접두사 사용)
  echo "M_SERVER_ID=${SERVER_ID}" >> .env.tmp
  echo "M_NODE_NAMES=${NODE_NAMES}" >> .env.tmp
  echo "M_MONITOR_INTERVAL=${MONITOR_INTERVAL}" >> .env.tmp
  echo "M_WS_MODE=${WS_MODE}" >> .env.tmp
  if [ -n "$WS_SERVER_URL" ]; then
    echo "M_WS_SERVER_URL=${WS_SERVER_URL}" >> .env.tmp
  fi
  echo "M_CREDITCOIN_DIR=${CREDITCOIN_DIR}" >> .env.tmp
  
  # 임시 파일을 .env로 이동
  mv .env.tmp .env
  
  echo -e "${GREEN}.env 파일이 성공적으로 업데이트되었습니다.${NC}"
}

# .env 파일 업데이트
update_env_file

# mclient 디렉토리 확인
if [ ! -d "./mclient" ]; then
  echo -e "${RED}오류: mclient 디렉토리가 없습니다.${NC}"
  echo -e "${YELLOW}먼저 setupmclient.sh를 실행하여 기본 환경을 구성한 후 다시 시도하세요.${NC}"
  exit 1
fi

# Python 클라이언트 설정 파일 생성
echo -e "${BLUE}파이썬 모니터링 클라이언트 파일 생성 중...${NC}"

# mclient/.env 파일 생성
cat > ./mclient/.env << EOF
# 모니터링 클라이언트 기본 설정
SERVER_ID=${SERVER_ID}
NODE_NAMES=${NODE_NAMES}
MONITOR_INTERVAL=${MONITOR_INTERVAL}

# WebSocket 설정
WS_MODE=${WS_MODE}
WS_SERVER_URL=${WS_SERVER_URL}

# 디렉토리 설정
CREDITCOIN_DIR=${CREDITCOIN_DIR}
EOF

# main.py 생성
cat > ./mclient/main.py << 'EOL'
# main.py
import asyncio
import logging
import argparse
import sys
import signal
import time
import os
from typing import List, Dict, Any

from config import settings, get_websocket_url
from docker_stats_client import DockerStatsClient
from websocket_client import WebSocketClient

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# ANSI 색상 코드
CLEAR_SCREEN = "\x1B[2J\x1B[1;1H"
COLOR_RESET = "\x1B[0m"
COLOR_RED = "\x1B[31m"
COLOR_GREEN = "\x1B[32m"
COLOR_YELLOW = "\x1B[33m"
COLOR_CYAN = "\x1B[36m"
COLOR_WHITE = "\x1B[37m"
COLOR_BLUE = "\x1B[34m"
STYLE_BOLD = "\x1B[1m"

# 시스템 인포 클래스
class SystemInfo:
    def __init__(self):
        self.hostname = ""
        self.cpu_model = ""
        self.cpu_usage = 0.0
        self.cpu_cores = 0
        self.memory_total = 0
        self.memory_used = 0
        self.memory_used_percent = 0.0
        self.swap_total = 0
        self.swap_used = 0
        self.uptime = 0
        self.disk_total = 0
        self.disk_used = 0
        self._last_collect_time = 0
        self._cache_duration = 0.5  # 초 단위 캐시 지속 시간

    def collect(self):
        """시스템 정보 수집"""
        current_time = time.time()
        
        # 캐시 유효 시간 내에 있으면 이전 값 반환
        if current_time - self._last_collect_time < self._cache_duration:
            return self.to_dict()
        
        import platform
        import psutil
        
        # 수집 시간 갱신
        self._last_collect_time = current_time
        
        # 호스트명
        self.hostname = platform.node()
        
        # CPU 정보
        self.cpu_cores = os.cpu_count() or 1
        self.cpu_model = platform.processor() or "Unknown CPU"
        self.cpu_usage = psutil.cpu_percent(interval=0.1)
        
        # 메모리 정보
        memory = psutil.virtual_memory()
        self.memory_total = memory.total
        self.memory_used = memory.used
        self.memory_used_percent = memory.percent
        
        # 스왑 정보
        swap = psutil.swap_memory()
        self.swap_total = swap.total
        self.swap_used = swap.used
        
        # 업타임
        self.uptime = int(time.time() - psutil.boot_time())
        
        # 디스크 정보
        disk = psutil.disk_usage('/')
        self.disk_total = disk.total
        self.disk_used = disk.used
        
        return self.to_dict()
    
    def to_dict(self):
        return {
            "host_name": self.hostname,
            "cpu_model": self.cpu_model,
            "cpu_usage": self.cpu_usage,
            "cpu_cores": self.cpu_cores,
            "memory_total": self.memory_total,
            "memory_used": self.memory_used,
            "memory_used_percent": self.memory_used_percent,
            "swap_total": self.swap_total,
            "swap_used": self.swap_used,
            "uptime": self.uptime,
            "disk_total": self.disk_total,
            "disk_used": self.disk_used
        }

# 전송 통계 클래스
class TransmissionStats:
    def __init__(self):
        self.total_sent = 0
        self.success_count = 0
        self.error_count = 0
        self.total_bytes_sent = 0
        self.last_data_size = 0
        self.last_cpu_usage = 0.0
        self.last_memory_percent = 0.0
        self.container_count = 0
        self.processing_times = []  # 처리 시간 기록
        self.max_times_stored = 100  # 최대 처리 시간 저장 개수
    
    def success_rate(self):
        if self.total_sent == 0:
            return 0.0
        return (self.success_count / self.total_sent) * 100.0
    
    def avg_data_size(self):
        if self.success_count == 0:
            return 0.0
        return self.total_bytes_sent / self.success_count
    
    def avg_processing_time(self):
        if not self.processing_times:
            return 0.0
        return sum(self.processing_times) / len(self.processing_times)
    
    def add_processing_time(self, time_value):
        """처리 시간 추가 및 오래된 값 제거"""
        self.processing_times.append(time_value)
        if len(self.processing_times) > self.max_times_stored:
            self.processing_times.pop(0)

# 커맨드 라인 인자 파싱
def parse_args():
    parser = argparse.ArgumentParser(description='Creditcoin 파이썬 모니터링 클라이언트')
    parser.add_argument('--server-id', help='서버 ID')
    parser.add_argument('--nodes', help='모니터링할 노드 이름 (쉼표로 구분)')
    parser.add_argument('--interval', type=int, help='모니터링 간격(초)')
    parser.add_argument('--ws-mode', choices=['auto', 'ws', 'wss', 'wss_internal', 'custom'],
                      help='WebSocket 연결 모드')
    parser.add_argument('--ws-url', help='사용자 지정 WebSocket URL')
    parser.add_argument('--local', action='store_true', help='로컬 모드로 실행')
    parser.add_argument('--debug', action='store_true', help='디버그 모드 활성화')
    parser.add_argument('--no-docker', action='store_true', help='Docker 모니터링 비활성화')
    
    return parser.parse_args()

# 값에 따른 색상 문자열 선택 함수
def get_color_for_value(value: float) -> str:
    if value > 80.0:
        return COLOR_RED
    elif value > 50.0:
        return COLOR_YELLOW
    else:
        return COLOR_GREEN

# 바이트 단위 변환 함수
def format_bytes(bytes: int) -> str:
    KB = 1024.0
    MB = KB * 1024.0
    GB = MB * 1024.0
    
    bytes_float = float(bytes)
    
    if bytes_float >= GB:
        return f"{bytes_float / GB:.2f}GB"
    elif bytes_float >= MB:
        return f"{bytes_float / MB:.2f}MB"
    elif bytes_float >= KB:
        return f"{bytes_float / KB:.2f}KB"
    else:
        return f"{bytes_float}B"

# 메모리 형식화 함수
def format_memory(usage: int, limit: int) -> str:
    usage_mb = usage / 1024.0 / 1024.0
    limit_mb = limit / 1024.0 / 1024.0
    
    if limit_mb > 1024.0:
        return f"{usage_mb / 1024.0:.2f}GB / {limit_mb / 1024.0:.2f}GB"
    else:
        return f"{usage_mb:.0f}MB / {limit_mb:.0f}MB"

# 전송 상태 출력 함수
def print_transmission_status(stats: TransmissionStats):
    status_color = COLOR_GREEN if stats.success_rate() > 95.0 else (
        COLOR_YELLOW if stats.success_rate() > 80.0 else COLOR_RED
    )
    
    cpu_color = get_color_for_value(stats.last_cpu_usage)
    mem_color = get_color_for_value(stats.last_memory_percent)
    
    processing_time = stats.processing_times[-1] if stats.processing_times else 0
    
    print(f"{COLOR_CYAN}[{time.strftime('%H:%M:%S')}] 데이터 전송 #{stats.total_sent}: "
          f"{cpu_color}{STYLE_BOLD}CPU {stats.last_cpu_usage}%{COLOR_RESET}, "
          f"{mem_color}MEM {stats.last_memory_percent:.1f}%{COLOR_RESET}, "
          f"컨테이너 {stats.container_count}개, "
          f"크기 {stats.last_data_size / 1024.0:.2f}KB, "
          f"처리 시간 {processing_time:.2f}초{COLOR_RESET}")
    
    # 10회마다 누적 통계 표시
    if stats.total_sent % 10 == 0 and stats.total_sent > 0:
        print(f"{STYLE_BOLD}{COLOR_BLUE}=== 누적 전송 통계 (#{stats.total_sent}) ==={COLOR_RESET}")
        print(f"{status_color}성공률: {STYLE_BOLD}{stats.success_rate():.1f}%{COLOR_RESET} "
              f"({stats.success_count}/{stats.total_sent})")
        print(f"평균 데이터 크기: {stats.avg_data_size() / 1024.0:.2f} KB")
        print(f"평균 처리 시간: {stats.avg_processing_time():.2f}초")
        print(f"총 전송 데이터: {stats.total_bytes_sent / 1024.0 / 1024.0:.2f} MB\n")

# 메트릭 출력 함수 (로컬 모드용)
def print_metrics(sys_info: Dict[str, Any], containers: List[Dict[str, Any]], interval: int):
    print(f"{STYLE_BOLD}{COLOR_WHITE}CREDITCOIN NODE RESOURCE MONITOR{COLOR_RESET}                     "
          f"{time.strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # 시스템 정보 섹션
    print(f"{COLOR_YELLOW}=== 시스템 정보 ==={COLOR_RESET}")
    print(f"호스트명: {sys_info['host_name']}")
    print(f"CPU 모델: {sys_info['cpu_model']}")
    
    # CPU 사용률 (색상으로 강조)
    cpu_color = get_color_for_value(sys_info['cpu_usage'])
    print(f"CPU 사용률: {cpu_color}{sys_info['cpu_usage']:.2f}%{COLOR_RESET} (코어: {sys_info['cpu_cores']}개)")
    
    # 메모리 사용률 (색상으로 강조)
    mem_color = get_color_for_value(sys_info['memory_used_percent'])
    print(f"메모리: {mem_color}{sys_info['memory_used'] / 1024.0 / 1024.0 / 1024.0:.2f}GB / "
          f"{sys_info['memory_total'] / 1024.0 / 1024.0 / 1024.0:.2f}GB ({sys_info['memory_used_percent']:.2f}%){COLOR_RESET}")
    
    print(f"스왑: {sys_info['swap_used'] / 1024.0 / 1024.0 / 1024.0:.2f}GB / "
          f"{sys_info['swap_total'] / 1024.0 / 1024.0 / 1024.0:.2f}GB")
    
    # 디스크 정보 출력
    disk_percent = (sys_info['disk_used'] / sys_info['disk_total'] * 100.0) if sys_info['disk_total'] > 0 else 0.0
    disk_color = get_color_for_value(disk_percent)
    print(f"디스크: {disk_color}{sys_info['disk_used'] / 1024.0 / 1024.0 / 1024.0:.2f}GB / "
          f"{sys_info['disk_total'] / 1024.0 / 1024.0 / 1024.0:.2f}GB ({disk_percent:.2f}%){COLOR_RESET}")
    
    # 업타임
    days = sys_info['uptime'] // 86400
    hours = (sys_info['uptime'] % 86400) // 3600
    minutes = (sys_info['uptime'] % 3600) // 60
    print(f"업타임: {days}일 {hours}시간 {minutes}분")
    print()
    
    # 컨테이너 정보 섹션
    print(f"{COLOR_YELLOW}=== 컨테이너 정보 ==={COLOR_RESET}")
    
    if not containers:
        print("모니터링 중인 컨테이너가 없습니다.")
    else:
        # 헤더 출력
        print(f"{STYLE_BOLD}노드{COLOR_RESET}            {STYLE_BOLD}CPU%{COLOR_RESET}    "
              f"{STYLE_BOLD}메모리 사용량{COLOR_RESET}          {STYLE_BOLD}메모리%{COLOR_RESET}   "
              f"{STYLE_BOLD}네트워크 RX/TX{COLOR_RESET}")
        
        # 각 컨테이너 정보 출력
        for container in containers:
            # CPU와 메모리 색상 가져오기
            cpu_color = get_color_for_value(container['cpu']['percent'])
            mem_color = get_color_for_value(container['memory']['percent'])
            
            # 메모리 단위 변환
            memory_str = format_memory(container['memory']['usage'], container['memory']['limit'])
            
            # 네트워크 단위 변환
            network_str = f"{format_bytes(container['network']['rx'])}/{format_bytes(container['network']['tx'])}"
            
            print(f"{container['name']:<15} {cpu_color}{container['cpu']['percent']:<8.2f}{COLOR_RESET} "
                  f"{memory_str:<20} {mem_color}{container['memory']['percent']:<8.2f}{COLOR_RESET} "
                  f"{network_str:<15}")
    
    # 아래에 상태 라인 추가
    print()
    print(f"{COLOR_CYAN}[{time.strftime('%H:%M:%S')}] 실시간 모니터링 중... (간격: {interval}초){COLOR_RESET}")

# 로컬 모드 실행 함수
async def run_local_mode(node_names: List[str], interval: int, use_docker: bool):
    """로컬 모드로 모니터링 (터미널에 출력)"""
    print(CLEAR_SCREEN)
    print(f"{STYLE_BOLD}{COLOR_WHITE}크레딧코인 노드 실시간 모니터링 시작 (Ctrl+C로 종료){COLOR_RESET}")
    print("-----------------------------------------")
    
    # 시스템 정보 수집 객체
    system_info = SystemInfo()
    
    # Docker 클라이언트 설정
    docker_client = None
    docker_stats_client = None
    if use_docker:
        try:
            # 먼저 Docker Stats 클라이언트 사용 시도
            docker_stats_client = DockerStatsClient()
            
            # Docker stats 모니터링 시작
            success = await docker_stats_client.start_stats_monitoring(node_names)
            if success:
                logger.info("Docker Stats 스트리밍 모니터링 시작됨")
            else:
                logger.warning("Docker Stats 스트리밍 모니터링 시작 실패, 기본 Docker 클라이언트 사용")
                docker_stats_client = None
        except Exception as e:
            logger.error(f"Docker 클라이언트 초기화 중 오류: {e}")
    
    # 모니터링 루프
    try:
        while True:
            loop_start_time = time.time()
            
            # 새로운 데이터 수집
            sys_metrics = system_info.collect()
            
            container_list = []
            if use_docker:
                try:
                    if docker_stats_client:
                        # Stats 클라이언트에서 데이터 가져오기 (이미 백그라운드에서 수집됨)
                        container_data = await docker_stats_client.get_stats_for_nodes(node_names)
                        container_list = list(container_data.values())
                except Exception as e:
                    logger.error(f"Docker 정보 수집 실패: {e}")
            
            # 화면 업데이트
            print(CLEAR_SCREEN)
            print_metrics(sys_metrics, container_list, interval)
            sys.stdout.flush()
            
            # 실행 시간 계산
            loop_end_time = time.time()
            execution_time = loop_end_time - loop_start_time
            
            # 다음 간격까지 대기 (음수가 되지 않도록)
            wait_time = max(0.1, interval - execution_time)
            await asyncio.sleep(wait_time)
    finally:
        # 정리 작업
        if docker_stats_client:
            await docker_stats_client.stop_stats_monitoring()

# 웹소켓 모드 실행 함수
async def run_websocket_mode(args, node_names: List[str], interval: int, use_docker: bool):
    """웹소켓 모드로 모니터링 (서버에 전송)"""
    # 설정값 적용
    server_id = args.server_id or settings.SERVER_ID
    
    # WebSocket URL 결정
    ws_mode = args.ws_mode or settings.WS_MODE
    
    if args.ws_url:
        ws_url_or_mode = args.ws_url
    elif ws_mode == "custom" and settings.WS_SERVER_URL:
        ws_url_or_mode = settings.WS_SERVER_URL
    else:
        ws_url_or_mode = ws_mode
    
    logger.info(f"모니터링 시작: 서버 ID={server_id}, 노드={node_names}, 간격={interval}초")
    logger.info(f"WebSocket 모드: {ws_mode}")
    
    if args.ws_url:
        logger.info(f"WebSocket URL: {args.ws_url}")
    elif settings.WS_SERVER_URL:
        logger.info(f"WebSocket URL: {settings.WS_SERVER_URL}")
    
    # 클라이언트 초기화
    system_info = SystemInfo()
    
    # Docker 클라이언트 설정
    docker_client = None
    docker_stats_client = None
    if use_docker:
        try:
            # Docker Stats 클라이언트 사용
            docker_stats_client = DockerStatsClient()
            
            # Docker stats 모니터링 시작
            success = await docker_stats_client.start_stats_monitoring(node_names)
            if success:
                logger.info("Docker Stats 스트리밍 모니터링 시작됨")
            else:
                logger.warning("Docker Stats 스트리밍 모니터링 시작 실패")
                docker_stats_client = None
        except Exception as e:
            logger.error(f"Docker 클라이언트 초기화 중 오류: {e}")
    
    websocket_client = WebSocketClient(ws_url_or_mode, server_id)
    
    # 전송 통계
    stats = TransmissionStats()
    
    # WebSocket 연결
    connected = await websocket_client.connect()
    if not connected:
        logger.warning("WebSocket 서버에 연결할 수 없습니다. 로컬 모드로 전환합니다.")
        await run_local_mode(node_names, interval, use_docker)
        return
    
    # 모니터링 루프
    try:
        while True:
            loop_start_time = time.time()
            
            # 시스템 정보 수집
            t_start = time.time()
            sys_metrics = system_info.collect()
            t_end = time.time()
            if t_end - t_start > 0.1:  # 실행 시간이 0.1초 이상인 경우만 로그
                logger.debug(f"시스템 정보 수집 시간: {t_end - t_start:.3f}초")
            
            # 컨테이너 정보 수집
            container_data = {}
            container_list = []
            
            # Docker 통계 데이터 가져오기 (Stats 클라이언트 사용)
            if use_docker:
                t_start = time.time()
                try:
                    if docker_stats_client:
                        # Stats 클라이언트에서 데이터 가져오기 (이미 백그라운드에서 수집됨)
                        container_data = await docker_stats_client.get_stats_for_nodes(node_names)
                    
                    container_list = list(container_data.values())
                except Exception as e:
                    logger.error(f"Docker 정보 수집 실패: {e}")
                
                t_end = time.time()
                if t_end - t_start > 0.5:  # 실행 시간이 0.5초 이상인 경우만 로그
                    logger.debug(f"Docker 정보 수집 시간: {t_end - t_start:.3f}초")
            
            # 상태 정보 업데이트
            stats.last_cpu_usage = sys_metrics["cpu_usage"]
            stats.last_memory_percent = sys_metrics["memory_used_percent"]
            stats.container_count = len(container_list)
            
            # 서버로 전송할 데이터 구성
            server_data = {
                "server_id": server_id,
                "timestamp": int(time.time() * 1000),
                "system": sys_metrics,
                "containers": container_list
            }
            
            # JSON으로 직렬화 및 전송
            json_data = server_data  # websocket_client.send_stats가 직렬화 수행
            json_str = str(server_data)  # 로깅용 (실제 전송 X)
            stats.total_sent += 1
            stats.last_data_size = len(json_str)
            
            # 전송
            t_start = time.time()
            if await websocket_client.send_stats(json_data):
                t_end = time.time()
                send_time = t_end - t_start
                logger.debug(f"WebSocket 데이터 전송 시간: {send_time:.3f}초")
                
                stats.success_count += 1
                stats.total_bytes_sent += len(json_str)
                
                # 전송 상태 출력
                loop_end_time = time.time()
                processing_time = loop_end_time - loop_start_time
                stats.add_processing_time(processing_time)
                
                print_transmission_status(stats)
            else:
                stats.error_count += 1
                logger.error("데이터 전송 실패")
            
            # 실행 시간 계산
            loop_end_time = time.time()
            execution_time = loop_end_time - loop_start_time
            
            # 다음 간격까지 대기 (음수가 되지 않도록)
            wait_time = max(0.1, interval - execution_time)
            if wait_time < interval * 0.5:  # 대기 시간이 설정 간격의 절반 미만인 경우
                logger.debug(f"대기 시간 줄어듦: {wait_time:.2f}초 (설정 간격: {interval}초)")
            
            await asyncio.sleep(wait_time)
            
    except Exception as e:
        logger.error(f"모니터링 중 오류 발생: {e}")
        stats.error_count += 1
        await asyncio.sleep(5)  # 오류 발생 시 잠시 대기
    finally:
        # 정리 작업
        if docker_stats_client:
            await docker_stats_client.stop_stats_monitoring()

# 메인 함수
async def main():
    # 인자 파싱
    args = parse_args()
    
    # 설정 로드
    server_id = args.server_id or settings.SERVER_ID
    node_names_str = args.nodes or settings.NODE_NAMES
    node_names = [name.strip() for name in node_names_str.split(',')]
    interval = args.interval or settings.MONITOR_INTERVAL
    
    # 디버그 모드 설정
    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)
        logger.debug("디버그 모드 활성화됨")
    
    # Docker 사용 여부
    use_docker = not args.no_docker
    
    # 설정 정보 출력
    logger.info(f"=== Creditcoin 파이썬 모니터링 클라이언트 시작 ===")
    logger.info(f"서버 ID: {server_id}")
    logger.info(f"모니터링 노드: {node_names}")
    logger.info(f"모니터링 간격: {interval}초")
    logger.info(f"WebSocket 모드: {args.ws_mode or settings.WS_MODE}")
    if args.ws_url:
        logger.info(f"WebSocket URL: {args.ws_url}")
    elif settings.WS_SERVER_URL:
        logger.info(f"WebSocket URL: {settings.WS_SERVER_URL}")
    logger.info(f"Creditcoin 디렉토리: {settings.CREDITCOIN_DIR}")
    logger.info(f"Docker 모니터링: {'활성화' if use_docker else '비활성화'}")
    logger.info(f"모드: {'로컬 모드' if args.local else '서버 연결 모드'}")
    
    # 실행 모드 선택
    if args.local:
        await run_local_mode(node_names, interval, use_docker)
    else:
        await run_websocket_mode(args, node_names, interval, use_docker)

# 신호 핸들러 설정
def signal_handler(sig, frame):
    logger.info("사용자에 의해 프로그램이 종료되었습니다.")
    sys.exit(0)

if __name__ == "__main__":
    # 신호 핸들러 등록
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("사용자에 의해 프로그램이 종료되었습니다.")
    except Exception as e:
        logger.error(f"예기치 않은 오류로 프로그램이 종료되었습니다: {e}")
        sys.exit(1)
EOL

# docker-compose.yml 파일 확인/업데이트
if [ ! -f "docker-compose.yml" ]; then
  echo -e "${RED}오류: docker-compose.yml 파일이 없습니다.${NC}"
  echo -e "${YELLOW}먼저 add3node.sh를 실행하여 기본 환경을 구성한 후 다시 시도하세요.${NC}"
  exit 1
fi

# docker-compose.yml 파일 백업
cp docker-compose.yml docker-compose.yml.bak.$(date +%Y%m%d%H%M%S)
echo -e "${GREEN}docker-compose.yml 파일이 백업되었습니다.${NC}"

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
  fi
fi

# mclient 서비스가 없거나 --force 옵션이 지정된 경우 추가
if ! grep -q "  mclient:" docker-compose.yml || [ "$FORCE" = "true" ]; then
  echo -e "${BLUE}docker-compose.yml에 mclient 서비스 추가 중...${NC}"
  
  # networks 섹션 위치 찾기
  networks_line=$(grep -n "^networks:" docker-compose.yml | cut -d: -f1)
  
  if [ -n "$networks_line" ]; then
    # networks 위에 mclient 서비스 추가
    mclient_service=$(cat << EOF

  mclient:
    build:
      context: ./mclient
      dockerfile: Dockerfile
    container_name: mclient
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - SERVER_ID=${SERVER_ID}
      - NODE_NAMES=${NODE_NAMES}
      - MONITOR_INTERVAL=${MONITOR_INTERVAL}
      - WS_MODE=${WS_MODE}
      - WS_SERVER_URL=${WS_SERVER_URL}
      - CREDITCOIN_DIR=/creditcoin-mac
    networks:
      creditnet:
EOF
)
    
    # networks 섹션 앞에 mclient 서비스 삽입
    head -n $((networks_line-1)) docker-compose.yml > docker-compose.yml.new
    echo "$mclient_service" >> docker-compose.yml.new
    tail -n +$((networks_line)) docker-compose.yml >> docker-compose.yml.new
    mv docker-compose.yml.new docker-compose.yml
    
    echo -e "${GREEN}mclient 서비스가 docker-compose.yml에 추가되었습니다.${NC}"
  else
    echo -e "${RED}오류: docker-compose.yml 파일에서 networks 섹션을 찾을 수 없습니다.${NC}"
    exit 1
  fi
fi

echo -e "${BLUE}----------------------------------------------------${NC}"
echo -e "${GREEN}Creditcoin 모니터링 클라이언트 설정이 완료되었습니다!${NC}"
echo -e "${GREEN}다음 설정으로 모니터링 클라이언트가 구성되었습니다:${NC}"
echo -e "${GREEN}- 서버 ID: ${SERVER_ID}${NC}"
echo -e "${GREEN}- 모니터링 노드: ${NODE_NAMES}${NC}"
echo -e "${GREEN}- 모니터링 간격: ${MONITOR_INTERVAL}초${NC}"
echo -e "${GREEN}- WebSocket 모드: ${WS_MODE}${NC}"
if [ -n "$WS_SERVER_URL" ]; then
  echo -e "${GREEN}- WebSocket URL: ${WS_SERVER_URL}${NC}"
fi
echo -e "${GREEN}- Creditcoin 디렉토리: ${CREDITCOIN_DIR}${NC}"
echo -e "${BLUE}----------------------------------------------------${NC}"

echo -e "${YELLOW}모니터링 클라이언트를 시작하시겠습니까? (Y/n) ${NC}"
read -r response
if [[ "$response" =~ ^([nN][oO]|[nN])$ ]]; then
  echo -e "${YELLOW}모니터링 클라이언트를 시작하지 않습니다.${NC}"
  echo -e "${YELLOW}나중에 다음 명령어로 시작할 수 있습니다:${NC}"
  echo -e "${GREEN}docker compose -p creditcoin3 up -d mclient${NC}"
  echo -e "${YELLOW}또는 shell 함수를 사용하여 시작:${NC}"
  echo -e "${GREEN}mclient-start${NC}"
else
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