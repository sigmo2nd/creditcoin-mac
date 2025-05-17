#!/usr/bin/env python3
# main.py - Creditcoin 파이썬 모니터링 클라이언트 (통합 버전)
import asyncio
import logging
import argparse
import sys
import signal
import time
import os
import json
import platform
import psutil
from typing import Dict, List, Any, Optional
import subprocess
from pathlib import Path

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# WebSocket 라이브러리 로깅 레벨 상향 조정 (DEBUG -> WARNING)
logging.getLogger('websockets').setLevel(logging.WARNING)
logging.getLogger('websockets.client').setLevel(logging.WARNING)
logging.getLogger('websockets.server').setLevel(logging.WARNING)
logging.getLogger('websockets.protocol').setLevel(logging.WARNING)

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

#################################################
# 설정 관리 (기존 config.py 통합)
#################################################

# .env 파일 로드
def load_dotenv():
    """환경 변수 설정 파일(.env) 로드"""
    env_file = Path('.env')
    if not env_file.exists():
        logger.debug(".env 파일이 존재하지 않습니다. 기본값을 사용합니다.")
        return False
    
    try:
        with open(env_file, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                    
                key, value = line.split('=', 1)
                key = key.strip()
                value = value.strip()
                
                # 이미 환경변수에 설정되어 있지 않은 경우에만 설정
                if key not in os.environ:
                    os.environ[key] = value
                    logger.debug(f".env에서 로드: {key}={value}")
        
        logger.debug(".env 파일 로드 완료")
        return True
    except Exception as e:
        logger.warning(f".env 파일 로드 중 오류: {e}")
        return False

# 설정 클래스
class Settings:
    """애플리케이션 설정 클래스"""
    
    def __init__(self, args=None):
        # 환경변수 로드 (.env)
        load_dotenv()
        
        # 기본 설정
        self.SERVER_ID = os.environ.get("SERVER_ID", "server1")
        self.NODE_NAMES = os.environ.get("NODE_NAMES", "node,3node")
        self.MONITOR_INTERVAL = int(os.environ.get("MONITOR_INTERVAL", "5"))
        
        # WebSocket 설정
        self.SERVER_URL = os.environ.get("SERVER_URL")
        self.WS_MODE = os.environ.get("WS_MODE", "auto")  # auto, ws, wss, custom
        self.WS_SERVER_HOST = os.environ.get("WS_SERVER_HOST", "192.168.0.24")
        self.WS_PORT_WS = int(os.environ.get("WS_PORT_WS", "8080"))
        self.WS_PORT_WSS = int(os.environ.get("WS_PORT_WSS", "8443"))
        
        # Docker 설정
        self.CREDITCOIN_DIR = os.environ.get("CREDITCOIN_DIR", os.path.expanduser("~/creditcoin-mac"))
        
        # 실행 모드 설정
        self.LOCAL_MODE = os.environ.get("LOCAL_MODE", "").lower() in ('true', '1', 'yes')
        self.DEBUG_MODE = os.environ.get("DEBUG_MODE", "").lower() in ('true', '1', 'yes')
        self.NO_DOCKER = os.environ.get("NO_DOCKER", "").lower() in ('true', '1', 'yes')
        self.NO_SSL_VERIFY = os.environ.get("NO_SSL_VERIFY", "").lower() in ('true', '1', 'yes')
        self.MAX_RETRIES = int(os.environ.get("MAX_RETRIES", "0"))
        self.RETRY_INTERVAL = int(os.environ.get("RETRY_INTERVAL", "10"))
        
        # 명령행 인자 적용 (있는 경우)
        if args:
            # 필수값 오버라이딩
            if args.server_id:
                self.SERVER_ID = args.server_id
            if args.nodes:
                self.NODE_NAMES = args.nodes
            if args.interval:
                self.MONITOR_INTERVAL = args.interval
            if args.ws_mode:
                self.WS_MODE = args.ws_mode
            if args.ws_url:
                self.SERVER_URL = args.ws_url
            
            # 플래그 설정
            if args.local:
                self.LOCAL_MODE = True
            if args.debug:
                self.DEBUG_MODE = True
            if args.no_docker:
                self.NO_DOCKER = True
            if args.no_ssl_verify:
                self.NO_SSL_VERIFY = True
            if args.max_retries is not None:
                self.MAX_RETRIES = args.max_retries
            if args.retry_interval:
                self.RETRY_INTERVAL = args.retry_interval
        
        # 디버그 모드면 로그 레벨 설정
        if self.DEBUG_MODE:
            logging.getLogger().setLevel(logging.DEBUG)
            logger.debug("디버그 모드가 활성화되었습니다.")
    
    def print_settings(self):
        """현재 설정 출력"""
        logger.info("=== 현재 설정 ===")
        logger.info(f"서버 ID: {self.SERVER_ID}")
        logger.info(f"노드 이름: {self.NODE_NAMES}")
        logger.info(f"모니터링 간격: {self.MONITOR_INTERVAL}초")
        
        # 로컬 모드인 경우
        if self.LOCAL_MODE:
            logger.info("모드: 로컬 모드 (데이터 전송 없음)")
        else:
            logger.info("모드: 서버 연결 모드")
            
            # WebSocket 설정
            if self.SERVER_URL:
                logger.info(f"WebSocket URL: {self.SERVER_URL} (커스텀)")
            else:
                logger.info(f"WebSocket 모드: {self.WS_MODE}")
                logger.info(f"WebSocket 호스트: {self.WS_SERVER_HOST}")
                logger.info(f"WebSocket 포트(WS): {self.WS_PORT_WS}")
                logger.info(f"WebSocket 포트(WSS): {self.WS_PORT_WSS}")
            
            logger.info(f"SSL 검증: {'비활성화' if self.NO_SSL_VERIFY else '활성화'}")
            logger.info(f"연결 재시도: {self.MAX_RETRIES if self.MAX_RETRIES > 0 else '무제한'} 회")
            logger.info(f"재시도 간격: {self.RETRY_INTERVAL}초")
        
        logger.info(f"Docker 모니터링: {'비활성화' if self.NO_DOCKER else '활성화'}")
        logger.info(f"Creditcoin 디렉토리: {self.CREDITCOIN_DIR}")
        logger.info(f"디버그 모드: {'활성화' if self.DEBUG_MODE else '비활성화'}")
        logger.info("================")

def get_websocket_url(settings):
    """설정에 따라 WebSocket URL 결정"""
    # 1. 커스텀 URL이 직접 설정된 경우
    if settings.SERVER_URL:
        return settings.SERVER_URL
    
    # 2. 기본 URL 설정 (설정값으로부터 동적 생성)
    base_urls = {
        "ws": f"ws://{settings.WS_SERVER_HOST}:{settings.WS_PORT_WS}/ws",
        "wss": f"wss://{settings.WS_SERVER_HOST}:{settings.WS_PORT_WSS}/ws",
        "wss_internal": f"wss://{settings.WS_SERVER_HOST}:{settings.WS_PORT_WSS}/ws"
    }
    
    # 3. auto 모드인 경우 자동 연결 로직 사용
    if settings.WS_MODE == "auto":
        return "auto"  # 자동 연결 로직은 websocket_client에서 구현
    
    # 4. 모드에 해당하는 URL 반환 (없으면 ws 모드 기본값 사용)
    url = base_urls.get(settings.WS_MODE, base_urls["ws"])
    return url

# 실행 환경 감지
def detect_environment():
    """현재 실행 환경 감지 (macOS, Linux, 컨테이너 등)"""
    if os.path.exists('/.dockerenv'):
        return "container"
    elif platform.system() == "Darwin":
        return "macos"
    elif platform.system() == "Linux":
        return "linux"
    else:
        return "unknown"

# 연결 설정 구성
def configure_connection(settings):
    """설정에 따른 연결 구성 생성"""
    # 로컬 모드인 경우
    if settings.LOCAL_MODE:
        return {"mode": "local", "use_websocket": False}
    
    # 서버 모드인 경우
    environment = detect_environment()
    
    # 커스텀 URL이 있는 경우 그대로 사용
    if settings.SERVER_URL:
        return {
            "mode": "server",
            "url": settings.SERVER_URL,
            "verify_ssl": not settings.NO_SSL_VERIFY
        }
    
    # URL 기반으로 구성
    ws_url = get_websocket_url(settings)
    use_ssl = settings.WS_MODE in ["wss", "wss_internal"] or ws_url.startswith("wss://")
    
    return {
        "mode": "server",
        "url": ws_url,
        "server_id": settings.SERVER_ID,
        "use_ssl": use_ssl,
        "verify_ssl": not settings.NO_SSL_VERIFY,
        "max_retries": settings.MAX_RETRIES,
        "retry_interval": settings.RETRY_INTERVAL
    }

#################################################
# 시스템 정보 수집 클래스
#################################################

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

#################################################
# 전송 통계 클래스
#################################################

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

#################################################
# 유틸리티 함수
#################################################

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

#################################################
# 명령행 인자 파싱
#################################################

def parse_args():
    parser = argparse.ArgumentParser(description='Creditcoin 파이썬 모니터링 클라이언트')
    parser.add_argument('--server-id', help='서버 ID')
    parser.add_argument('--nodes', help='모니터링할 노드 이름 (쉼표로 구분)')
    parser.add_argument('--interval', type=int, help='모니터링 간격(초)')
    parser.add_argument('--ws-mode', choices=['auto', 'ws', 'wss', 'wss_internal', 'custom'],
                      help='WebSocket 연결 모드')
    parser.add_argument('--ws-url', help='사용자 지정 WebSocket URL')
    parser.add_argument('--no-ssl-verify', action='store_true', help='SSL 인증서 검증 비활성화')
    parser.add_argument('--local', action='store_true', help='로컬 모드로 실행')
    parser.add_argument('--debug', action='store_true', help='디버그 모드 활성화')
    parser.add_argument('--no-docker', action='store_true', help='Docker 모니터링 비활성화')
    parser.add_argument('--max-retries', type=int, default=None, help='WebSocket 연결 최대 재시도 횟수 (0=무한)')
    parser.add_argument('--retry-interval', type=int, help='WebSocket 연결 재시도 간격(초)')
    
    return parser.parse_args()

# 로컬 모드 실행 함수
async def run_local_mode(settings, node_names: List[str]):
    """로컬 모드로 모니터링 (터미널에 출력)"""
    print(CLEAR_SCREEN)
    print(f"{STYLE_BOLD}{COLOR_WHITE}크레딧코인 노드 실시간 모니터링 시작 (Ctrl+C로 종료){COLOR_RESET}")
    print("-----------------------------------------")
    
    # 시스템 정보 수집 객체
    system_info = SystemInfo()
    
    # Docker 클라이언트 설정
    docker_stats_client = None
    if not settings.NO_DOCKER:
        try:
            # Docker Stats 클라이언트 사용
            from docker_stats_client import DockerStatsClient
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
        while not shutdown_event.is_set():
            loop_start_time = time.time()
            
            # 새로운 데이터 수집
            sys_metrics = system_info.collect()
            
            container_list = []
            if not settings.NO_DOCKER and docker_stats_client:
                try:
                    # Stats 클라이언트에서 데이터 가져오기 (이미 백그라운드에서 수집됨)
                    container_data = await docker_stats_client.get_stats_for_nodes(node_names)
                    container_list = list(container_data.values())
                except Exception as e:
                    logger.error(f"Docker 정보 수집 실패: {e}")
            
            # 화면 업데이트
            print(CLEAR_SCREEN)
            print_metrics(sys_metrics, container_list, settings.MONITOR_INTERVAL)
            sys.stdout.flush()
            
            # 실행 시간 계산
            loop_end_time = time.time()
            execution_time = loop_end_time - loop_start_time
            
            # 다음 간격까지 대기 (음수가 되지 않도록)
            wait_time = max(0.1, settings.MONITOR_INTERVAL - execution_time)
            
            # 종료 이벤트가 설정될 때까지 또는 대기 시간 동안 대기
            try:
                await asyncio.wait_for(shutdown_event.wait(), timeout=wait_time)
                if shutdown_event.is_set():
                    logger.info("모니터링 루프 종료 요청 감지")
                    break
            except asyncio.TimeoutError:
                # 타임아웃은 정상 동작 (다음 루프로 진행)
                pass
    except Exception as e:
        logger.error(f"로컬 모니터링 중 오류 발생: {e}")
    finally:
        # 정리 작업
        logger.info("리소스 정리 중...")
        if docker_stats_client:
            await docker_stats_client.stop_stats_monitoring()
        logger.info("로컬 모니터링 종료")

# 웹소켓 모드 실행 함수
async def run_websocket_mode(settings, node_names: List[str]):
    """웹소켓 모드로 모니터링 (서버에 전송)"""
    global websocket_client_instance, shutdown_event
    
    # WebSocket URL 결정
    ws_url_or_mode = get_websocket_url(settings)
    
    logger.info(f"모니터링 시작: 서버 ID={settings.SERVER_ID}, 노드={node_names}, 간격={settings.MONITOR_INTERVAL}초")
    
    if settings.SERVER_URL:
        logger.info(f"WebSocket URL: {settings.SERVER_URL}")
    else:
        logger.info(f"WebSocket 모드: {settings.WS_MODE}")
        logger.info(f"WebSocket 호스트: {settings.WS_SERVER_HOST}")
        if settings.WS_MODE in ['ws', 'auto']:
            logger.info(f"WebSocket 포트(WS): {settings.WS_PORT_WS}")
        if settings.WS_MODE in ['wss', 'wss_internal', 'auto']:
            logger.info(f"WebSocket 포트(WSS): {settings.WS_PORT_WSS}")
    
    if settings.NO_SSL_VERIFY:
        logger.info("SSL 인증서 검증이 비활성화되었습니다.")
    
    # 클라이언트 초기화
    system_info = SystemInfo()
    
    # Docker 클라이언트 설정
    docker_stats_client = None
    if not settings.NO_DOCKER:
        try:
            # Docker Stats 클라이언트 사용
            from docker_stats_client import DockerStatsClient
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
    
    # WebSocket 클라이언트 초기화 (SSL 검증 옵션 적용)
    from websocket_client import WebSocketClient
    websocket_client = WebSocketClient(ws_url_or_mode, settings.SERVER_ID, ssl_verify=not settings.NO_SSL_VERIFY)
    websocket_client_instance = websocket_client  # 전역 변수에 할당하여 종료 시 접근 가능
    
    # 전송 통계
    stats = TransmissionStats()
    
    # WebSocket 연결 (재시도 로직 포함)
    connected = False
    retry_count = 0
    max_retries = settings.MAX_RETRIES
    retry_interval = settings.RETRY_INTERVAL
    
    # 연결 시도 로직
    while not connected and not shutdown_event.is_set():
        connected = await websocket_client.connect()
        
        if not connected:
            retry_count += 1
            # 최대 재시도 횟수 초과 또는 무한 재시도(0) 확인
            if max_retries > 0 and retry_count > max_retries:
                logger.error(f"WebSocket 서버 연결 실패: 최대 재시도 횟수({max_retries}회) 초과")
                logger.error("로컬 모드로 전환하려면 --local 옵션을 사용하여 다시 시작하세요.")
                return  # 함수 종료
            
            logger.warning(f"WebSocket 서버 연결 실패 ({retry_count}번째 시도)")
            logger.info(f"{retry_interval}초 후 다시 시도합니다...")
            await asyncio.sleep(retry_interval)
            
            # 종료 요청 확인
            if shutdown_event.is_set():
                logger.info("종료 요청으로 연결 시도 중단")
                return
    
    if not connected:
        return  # 종료 요청으로 연결 실패한 경우
    
    logger.info("WebSocket 서버에 성공적으로 연결되었습니다!")
    
    # 모니터링 루프
    try:
        while not shutdown_event.is_set():
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
            if not settings.NO_DOCKER and docker_stats_client:
                t_start = time.time()
                try:
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
                "server_id": settings.SERVER_ID,
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
                
                stats.success_count += 1
                stats.total_bytes_sent += len(json_str)
                
                # 전송 상태 출력
                loop_end_time = time.time()
                processing_time = loop_end_time - loop_start_time
                stats.add_processing_time(processing_time)
                
                # 터미널에 출력만 하고 로그 출력은 제거
                print_transmission_status(stats)
                
                # 10회마다 누적 통계 로그 출력
                if stats.total_sent % 10 == 0:
                    logger.info(f"누적 통계 #{stats.total_sent}: 성공률 {stats.success_rate():.1f}%")
            else:
                stats.error_count += 1
                logger.error("데이터 전송 실패")
            
            # 실행 시간 계산
            loop_end_time = time.time()
            execution_time = loop_end_time - loop_start_time
            
            # 다음 간격까지 대기 (음수가 되지 않도록)
            wait_time = max(0.1, settings.MONITOR_INTERVAL - execution_time)
            if wait_time < settings.MONITOR_INTERVAL * 0.5:  # 대기 시간이 설정 간격의 절반 미만인 경우
                logger.debug(f"대기 시간 줄어듦: {wait_time:.2f}초 (설정 간격: {settings.MONITOR_INTERVAL}초)")
            
            # 종료 이벤트가 설정될 때까지 또는 대기 시간 동안 대기
            try:
                await asyncio.wait_for(shutdown_event.wait(), timeout=wait_time)
                if shutdown_event.is_set():
                    logger.info("모니터링 루프 종료 요청 감지")
                    break
            except asyncio.TimeoutError:
                # 타임아웃은 정상 동작 (다음 루프로 진행)
                pass
            
    except Exception as e:
        logger.error(f"모니터링 중 오류 발생: {e}")
        stats.error_count += 1
        await asyncio.sleep(1)  # 오류 발생 시 잠시 대기
    finally:
        # 정리 작업
        logger.info("리소스 정리 중...")
        
        # Docker 통계 클라이언트 정리
        if docker_stats_client:
            await docker_stats_client.stop_stats_monitoring()
        
        # WebSocket 연결 정리
        try:
            if websocket_client and websocket_client.connected:
                logger.info("WebSocket 연결 종료 중...")
                await websocket_client.disconnect()
                logger.info("WebSocket 연결 종료 완료")
        except Exception as e:
            logger.error(f"WebSocket 연결 종료 중 오류: {e}")
        
        logger.info("모니터링 종료")

# 메인 함수
async def main():
    # 인자 파싱
    args = parse_args()
    
    # 설정 로드
    settings = Settings(args)
    
    # 노드 이름 파싱
    node_names = [name.strip() for name in settings.NODE_NAMES.split(',')]
    
    # 설정 정보 출력
    settings.print_settings()
    
    # 실행 모드 선택
    if settings.LOCAL_MODE:
        await run_local_mode(settings, node_names)
    else:
        await run_websocket_mode(settings, node_names)

# 종료 플래그 (전역 변수)
shutdown_event = asyncio.Event()  # 여기서 바로 초기화
websocket_client_instance = None

# 신호 핸들러 설정
def signal_handler(sig, frame):
    global shutdown_event
    if shutdown_event is not None:
        logger.info("사용자에 의해 프로그램 종료 요청...")
        # 이벤트 설정으로 정상 종료 신호 전달
        shutdown_event.set()
    else:
        logger.info("사용자에 의해 프로그램이 즉시 종료됩니다.")
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
