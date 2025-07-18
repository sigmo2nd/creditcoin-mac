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
import getpass
import aiohttp

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# PayoutChecker import
try:
    from payout_checker import PayoutChecker
except ImportError:
    logger.warning("PayoutChecker not available")
    PayoutChecker = None

# EraMonitor import
try:
    from era_monitor import EraMonitor
except ImportError:
    logger.warning("EraMonitor not available")
    EraMonitor = None

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
    """환경 변수 설정 파일(.env) 로드 - Docker 환경에서는 건너뜀"""
    # Docker 컨테이너에서는 환경변수가 이미 설정되어 있으므로 .env 파일을 읽지 않음
    if os.path.exists('/.dockerenv'):
        logger.debug("Docker 환경에서 실행 중. .env 파일을 건너뜁니다.")
        return True
    
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

#################################################
# 인증 관련 함수들
#################################################

TOKEN_FILE_PATH = "/app/data/.auth_token"

async def handle_tty_authentication(auth_api_url: str, allow_http: bool = False) -> Optional[str]:
    """TTY 모드에서 인증 처리 (토큰 확인 및 로그인)"""
    print(f"{COLOR_BLUE}{'='*50}{COLOR_RESET}")
    print(f"{COLOR_GREEN}     Creditcoin 모니터링 서버 인증{COLOR_RESET}")
    print(f"{COLOR_BLUE}{'='*50}{COLOR_RESET}")
    print("")
    
    # 기존 토큰 확인
    if os.path.exists(TOKEN_FILE_PATH):
        try:
            with open(TOKEN_FILE_PATH, 'r') as f:
                token = f.read().strip()
                if token:
                    print(f"{COLOR_GREEN}기존 토큰을 발견했습니다. 유효성을 확인합니다...{COLOR_RESET}")
                    if await verify_token(token, auth_api_url, allow_http):
                        print(f"{COLOR_GREEN}토큰이 유효합니다.{COLOR_RESET}")
                        
                        # 유효한 토큰이 있으면 바로 사용
                        return token
                    else:
                        print(f"{COLOR_YELLOW}토큰이 만료되었거나 유효하지 않습니다.{COLOR_RESET}")
                        print(f"{COLOR_YELLOW}새로운 로그인이 필요합니다.{COLOR_RESET}")
        except Exception as e:
            logger.error(f"토큰 파일 읽기 오류: {e}")
    else:
        print(f"{COLOR_YELLOW}저장된 토큰이 없습니다. 로그인이 필요합니다.{COLOR_RESET}")
    
    # TTY가 없는 환경에서는 에러 발생
    if not sys.stdin.isatty():
        print(f"{COLOR_RED}TTY가 없는 환경에서는 인증 정보를 입력할 수 없습니다.{COLOR_RESET}")
        print(f"{COLOR_YELLOW}환경변수 AUTH_USER와 AUTH_PASS를 설정하거나 TTY 모드로 실행하세요.{COLOR_RESET}")
        raise RuntimeError("No TTY available for authentication input")
    
    # 대화형 로그인 진행
    return await interactive_login(auth_api_url, allow_http)

async def interactive_login(auth_api_url: str, allow_http: bool = False) -> Optional[str]:
    """대화형 로그인 처리"""
    max_attempts = 3
    for attempt in range(max_attempts):
        print(f"\n{COLOR_YELLOW}로그인 시도 {attempt + 1}/{max_attempts}{COLOR_RESET}")
        
        username = input("사용자명: ")
        password = getpass.getpass("비밀번호: ")
        
        try:
            token = await login_to_server(username, password, auth_api_url, allow_http)
            if token:
                # 토큰 저장
                save_token(token)
                print(f"\n{COLOR_GREEN}로그인 성공! 토큰이 발급되었습니다.{COLOR_RESET}")
                print(f"{COLOR_GREEN}토큰이 안전하게 저장되었습니다.{COLOR_RESET}")
                return token
            else:
                print(f"{COLOR_RED}로그인 실패: 사용자명 또는 비밀번호가 올바르지 않습니다.{COLOR_RESET}")
        except Exception as e:
            print(f"{COLOR_RED}로그인 중 오류 발생: {e}{COLOR_RESET}")
    
    print(f"\n{COLOR_RED}최대 로그인 시도 횟수를 초과했습니다.{COLOR_RESET}")
    return None

async def authenticate_user(auth_api_url: str, allow_http: bool = False) -> Optional[str]:
    """사용자 인증 및 토큰 발급 (환경변수 우선)"""
    # 환경변수에서 인증 정보 확인
    env_username = os.environ.get("AUTH_USER", "")
    env_password = os.environ.get("AUTH_PASS", "")
    
    # 환경변수에 인증 정보가 있으면 자동 로그인 시도
    if env_username and env_password:
        print(f"{COLOR_BLUE}환경변수에서 인증 정보를 찾았습니다. 자동 로그인을 시도합니다...{COLOR_RESET}")
        try:
            token = await login_to_server(env_username, env_password, auth_api_url, allow_http)
            if token:
                save_token(token)
                print(f"{COLOR_GREEN}자동 로그인 성공! 토큰이 발급되었습니다.{COLOR_RESET}")
                print(f"{COLOR_GREEN}토큰이 안전하게 저장되었습니다.{COLOR_RESET}")
                return token
            else:
                print(f"{COLOR_YELLOW}자동 로그인 실패.{COLOR_RESET}")
        except Exception as e:
            print(f"{COLOR_YELLOW}자동 로그인 중 오류: {e}{COLOR_RESET}")
    
    # TTY 인증으로 전환
    return await handle_tty_authentication(auth_api_url, allow_http)

async def login_to_server(username: str, password: str, auth_api_url: str, allow_http: bool) -> Optional[str]:
    """Django 서버에 로그인하여 토큰 발급"""
    login_url = f"{auth_api_url}/login/"
    
    # SSL 검증 설정
    ssl_verify = os.environ.get('SSL_VERIFY', 'true').lower() in ('true', '1', 'yes')
    connector = None
    
    if auth_api_url.startswith('https') and not ssl_verify:
        import ssl as ssl_module
        ssl_context = ssl_module.create_default_context()
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl_module.CERT_NONE
        connector = aiohttp.TCPConnector(ssl=ssl_context)
        logger.debug("SSL 인증서 검증 비활성화")
    
    async with aiohttp.ClientSession(connector=connector) as session:
        try:
            data = {
                "username": username,
                "password": password
            }
            
            async with session.post(login_url, json=data) as response:
                if response.status == 200:
                    result = await response.json()
                    if result.get("success") and result.get("token"):
                        return result["token"]
                return None
        except Exception as e:
            logger.error(f"로그인 API 호출 중 오류: {e}")
            raise

async def verify_token(token: str, auth_api_url: str, allow_http: bool) -> bool:
    """토큰 유효성 검증"""
    verify_url = f"{auth_api_url}/verify/"
    
    # SSL 검증 설정
    ssl_verify = os.environ.get('SSL_VERIFY', 'true').lower() in ('true', '1', 'yes')
    connector = None
    
    if verify_url.startswith('https') and not ssl_verify:
        import ssl as ssl_module
        ssl_context = ssl_module.create_default_context()
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl_module.CERT_NONE
        connector = aiohttp.TCPConnector(ssl=ssl_context)
        logger.debug("SSL 인증서 검증 비활성화")
    
    async with aiohttp.ClientSession(connector=connector) as session:
        try:
            headers = {"Authorization": f"Token {token}"}
            
            async with session.get(verify_url, headers=headers) as response:
                if response.status == 200:
                    result = await response.json()
                    return result.get("valid", False)
                return False
        except Exception as e:
            logger.error(f"토큰 검증 중 오류: {e}")
            return False

def save_token(token: str):
    """토큰을 파일에 저장"""
    try:
        os.makedirs(os.path.dirname(TOKEN_FILE_PATH), exist_ok=True)
        with open(TOKEN_FILE_PATH, 'w') as f:
            f.write(token)
        # 파일 권한 설정 (소유자만 읽기/쓰기)
        os.chmod(TOKEN_FILE_PATH, 0o600)
    except Exception as e:
        logger.error(f"토큰 저장 중 오류: {e}")
        raise

def load_token() -> Optional[str]:
    """저장된 토큰 로드"""
    if os.path.exists(TOKEN_FILE_PATH):
        try:
            with open(TOKEN_FILE_PATH, 'r') as f:
                return f.read().strip()
        except Exception as e:
            logger.error(f"토큰 로드 중 오류: {e}")
    return None

# 설정 클래스
class Settings:
    """애플리케이션 설정 클래스"""
    
    def __init__(self, args=None):
        # 환경변수 로드 (.env)
        load_dotenv()
        self.last_reload_time = time.time()
        self.reload_interval = 10  # 10초마다 확인
        
        # 기본 설정
        self.SERVER_ID = os.environ.get("SERVER_ID", "")
        self.NODE_NAMES = os.environ.get("NODE_NAMES", "")
        self.MONITOR_INTERVAL = int(os.environ.get("MONITOR_INTERVAL", "5"))
        
        # WebSocket 설정
        self.SERVER_URL = os.environ.get("SERVER_URL")
        self.WS_MODE = os.environ.get("WS_MODE", "auto")  # auto, ws, wss, custom
        self.WS_SERVER_HOST = os.environ.get("WS_SERVER_HOST", "localhost")
        # WS_SERVER_PORT 환경변수 우선 사용 (addmc.sh에서 설정)
        ws_port = os.environ.get("WS_SERVER_PORT")
        if ws_port:
            # WS_SERVER_PORT가 설정된 경우, 현재 모드에 맞는 포트로 사용
            if self.WS_MODE == "ws":
                self.WS_PORT_WS = int(ws_port)
                self.WS_PORT_WSS = int(os.environ.get("WS_PORT_WSS", "4443"))
            else:  # wss 또는 기타 모드
                self.WS_PORT_WS = int(os.environ.get("WS_PORT_WS", "8080"))
                self.WS_PORT_WSS = int(ws_port)
        else:
            self.WS_PORT_WS = int(os.environ.get("WS_PORT_WS", "8080"))
            self.WS_PORT_WSS = int(os.environ.get("WS_PORT_WSS", "4443"))
        
        # Docker 설정
        self.CREDITCOIN_DIR = os.environ.get("CREDITCOIN_DIR", "")
        
        # 실행 모드 설정
        self.LOCAL_MODE = os.environ.get("LOCAL_MODE", "").lower() in ('true', '1', 'yes')
        self.DEBUG_MODE = os.environ.get("DEBUG_MODE", "").lower() in ('true', '1', 'yes')
        self.NO_DOCKER = os.environ.get("NO_DOCKER", "").lower() in ('true', '1', 'yes')
        # SSL_VERIFY 환경변수 읽기 (기본값: true)
        self.SSL_VERIFY = os.environ.get("SSL_VERIFY", "true").lower() in ('true', '1', 'yes')
        self.MAX_RETRIES = int(os.environ.get("MAX_RETRIES", "0"))
        self.RETRY_INTERVAL = int(os.environ.get("RETRY_INTERVAL", "10"))
        
        # 인증 관련 설정
        self.REQUIRE_AUTH = os.environ.get("REQUIRE_AUTH", "").lower() in ('true', '1', 'yes')
        self.AUTH_API_URL = os.environ.get("AUTH_API_URL", "")
        self.AUTH_ALLOW_HTTP = os.environ.get("AUTH_ALLOW_HTTP", "").lower() in ('true', '1', 'yes')
        self.RUN_MODE = os.environ.get("RUN_MODE", "normal")  # normal, auth
        
        # 호스트 정보 설정 - 환경 변수에서 로드
        self.HOST_SYSTEM_NAME = os.environ.get("HOST_SYSTEM_NAME", "")
        self.HOST_MODEL = os.environ.get("HOST_MODEL", "")
        self.HOST_PROCESSOR = os.environ.get("HOST_PROCESSOR", "")
        self.HOST_CPU_CORES = int(os.environ.get("HOST_CPU_CORES", "0"))
        self.HOST_CPU_PERF_CORES = int(os.environ.get("HOST_CPU_PERF_CORES", "0"))
        self.HOST_CPU_EFF_CORES = int(os.environ.get("HOST_CPU_EFF_CORES", "0"))
        self.HOST_MEMORY_GB = int(os.environ.get("HOST_MEMORY_GB", "0"))
        self.HOST_DISK_TOTAL_GB = int(os.environ.get("HOST_DISK_TOTAL_GB", "0"))
        
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
                self.SSL_VERIFY = False
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
        
        # 호스트 시스템 정보
        if self.HOST_SYSTEM_NAME:
            logger.info(f"호스트 시스템: {self.HOST_SYSTEM_NAME}")
            logger.info(f"모델: {self.HOST_MODEL}")
            logger.info(f"프로세서: {self.HOST_PROCESSOR}")
            logger.info(f"CPU 코어: {self.HOST_CPU_CORES}코어 (성능: {self.HOST_CPU_PERF_CORES}, 효율: {self.HOST_CPU_EFF_CORES})")
            logger.info(f"메모리: {self.HOST_MEMORY_GB}GB")
        
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
            
            logger.info(f"SSL 검증: {'활성화' if self.SSL_VERIFY else '비활성화'}")
            logger.info(f"연결 재시도: {self.MAX_RETRIES if self.MAX_RETRIES > 0 else '무제한'} 회")
            logger.info(f"재시도 간격: {self.RETRY_INTERVAL}초")
        
        logger.info(f"Docker 모니터링: {'비활성화' if self.NO_DOCKER else '활성화'}")
        logger.info(f"Creditcoin 디렉토리: {self.CREDITCOIN_DIR}")
        logger.info(f"디버그 모드: {'활성화' if self.DEBUG_MODE else '비활성화'}")
        logger.info("================")
    
    def reload_if_needed(self):
        """향후 동적 설정 업데이트를 위한 메서드 (현재는 비활성화)"""
        # 10초마다 호출되지만 현재는 아무것도 하지 않음
        return False

def get_websocket_url(settings):
    """설정에 따라 WebSocket URL 결정"""
    # 1. 커스텀 URL이 직접 설정된 경우
    if settings.SERVER_URL:
        return settings.SERVER_URL
    
    # 2. 기본 URL 설정 (설정값으로부터 동적 생성)
    base_urls = {
        "ws": f"ws://{settings.WS_SERVER_HOST}:{settings.WS_PORT_WS}/ws/monitoring/",
        "wss": f"wss://{settings.WS_SERVER_HOST}:{settings.WS_PORT_WSS}/ws/monitoring/",
        "wss_internal": f"wss://{settings.WS_SERVER_HOST}:{settings.WS_PORT_WSS}/ws/monitoring/"
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
            "verify_ssl": settings.SSL_VERIFY
        }
    
    # URL 기반으로 구성
    ws_url = get_websocket_url(settings)
    use_ssl = settings.WS_MODE in ["wss", "wss_internal"] or ws_url.startswith("wss://")
    
    return {
        "mode": "server",
        "url": ws_url,
        "server_id": settings.SERVER_ID,
        "use_ssl": use_ssl,
        "verify_ssl": settings.SSL_VERIFY,
        "max_retries": settings.MAX_RETRIES,
        "retry_interval": settings.RETRY_INTERVAL
    }

#################################################
# 시스템 정보 수집 클래스
#################################################

class SystemInfo:
    def __init__(self):
        self.hostname = ""
        self.model = ""
        self.chip = ""
        self.cpu_cores_total = 0
        self.cpu_cores_perf = 0
        self.cpu_cores_eff = 0
        self.cpu_user = 0.0
        self.cpu_system = 0.0
        self.cpu_idle = 0.0
        self.cpu_usage = 0.0
        self.host_memory_total = 0  # 호스트 전체 메모리
        self.host_memory_used = 0  # 호스트 메모리 사용량 (추정)
        self.host_memory_percent = 0.0  # 호스트 메모리 사용률 (추정)
        self.docker_available = False
        self.docker_memory_total = 0  # Docker에 할당된 메모리
        self.docker_memory_used = 0  # Docker가 사용 중인 메모리
        self.docker_memory_percent = 0.0  # Docker 할당량 대비 사용률
        self.swap_total = 0
        self.swap_used = 0
        self.uptime = 0
        self.disk_total = 0
        self.disk_used = 0
        self.disk_available = 0
        self.disk_percent = 0.0
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
        import subprocess
        import re
        import os
        
        # 수집 시간 갱신
        self._last_collect_time = current_time
        
        # 호스트명
        self.hostname = platform.node()
        
        # Docker 컨테이너 내부에서 실행 중인지 확인
        is_docker = os.path.exists('/.dockerenv')
        
        # 환경 변수에서 호스트 정보 가져오기 (Docker 실행 시)
        # OrbStack 또는 일반적인 Docker 환경에서 호스트명이 generic한 경우(orbstack, container 등)
        generic_hostnames = ["orbstack", "docker", "container", "localhost"]
        if is_docker or any(name in self.hostname.lower() for name in generic_hostnames):
            # 환경변수에서 호스트명 확인
            env_hostname = os.environ.get("HOST_SYSTEM_NAME")
            if env_hostname:
                self.hostname = env_hostname
                logger.debug(f"호스트명을 환경변수 설정으로 대체: {self.hostname}")
                
            # 다른 호스트 정보도 환경변수에서 가져옴
            env_model = os.environ.get("HOST_MODEL")
            env_processor = os.environ.get("HOST_PROCESSOR")
            env_cpu_cores = os.environ.get("HOST_CPU_CORES")
            env_cpu_perf_cores = os.environ.get("HOST_CPU_PERF_CORES")
            env_cpu_eff_cores = os.environ.get("HOST_CPU_EFF_CORES")
            env_memory_gb = os.environ.get("HOST_MEMORY_GB")
            env_disk_total_gb = os.environ.get("HOST_DISK_TOTAL_GB")
            
            # 값 설정 (있는 경우에만)
            if env_model:
                self.model = env_model
            if env_processor:
                self.chip = env_processor
            if env_cpu_cores:
                self.cpu_cores_total = int(env_cpu_cores)
            if env_cpu_perf_cores:
                self.cpu_cores_perf = int(env_cpu_perf_cores)
            if env_disk_total_gb:
                self.disk_total_gb = int(env_disk_total_gb)
            if env_cpu_eff_cores:
                self.cpu_cores_eff = int(env_cpu_eff_cores)
            
            # 중요: 호스트 메모리 총량 설정
            if env_memory_gb and self.host_memory_total == 0:
                self.host_memory_total = int(env_memory_gb) * 1024 * 1024 * 1024  # GB -> bytes
        
        # macOS 환경에서 직접 시스템 정보 수집 (Docker가 아닌 경우)
        if not is_docker and platform.system() == "Darwin":
            # 모델 정보
            try:
                model_cmd = ["sysctl", "hw.model"]
                model_result = subprocess.run(model_cmd, capture_output=True, text=True)
                if model_result.returncode == 0:
                    self.model = model_result.stdout.split(": ")[1].strip()
                else:
                    self.model = "Unknown Mac Model"
            except:
                self.model = platform.machine()
                
            # 칩 정보 (Apple Silicon vs Intel)
            if platform.machine() == "arm64":  # Apple Silicon
                try:
                    chip_cmd = ["system_profiler", "SPHardwareDataType"]
                    chip_result = subprocess.run(chip_cmd, capture_output=True, text=True)
                    if chip_result.returncode == 0:
                        for line in chip_result.stdout.splitlines():
                            if "Chip" in line and ":" in line:
                                self.chip = line.split(":")[1].strip()
                                break
                        if not self.chip:
                            self.chip = "Apple Silicon"
                    else:
                        self.chip = "Apple Silicon"
                except:
                    self.chip = "Apple Silicon"
            else:  # Intel Mac
                try:
                    chip_cmd = ["sysctl", "-n", "machdep.cpu.brand_string"]
                    chip_result = subprocess.run(chip_cmd, capture_output=True, text=True)
                    if chip_result.returncode == 0:
                        self.chip = chip_result.stdout.strip()
                    else:
                        self.chip = "Intel"
                except:
                    self.chip = "Intel"
                    
            # CPU 코어 정보 (성능/효율 코어 구분)
            self.cpu_cores_total = os.cpu_count() or 1
            try:
                if platform.machine() == "arm64":  # Apple Silicon
                    # 성능 코어 수
                    perf_cmd = ["sysctl", "-n", "hw.perflevel0.logicalcpu"]
                    perf_result = subprocess.run(perf_cmd, capture_output=True, text=True)
                    if perf_result.returncode == 0:
                        self.cpu_cores_perf = int(perf_result.stdout.strip())
                    else:
                        self.cpu_cores_perf = self.cpu_cores_total
                        
                    # 효율 코어 수
                    eff_cmd = ["sysctl", "-n", "hw.perflevel1.logicalcpu"]
                    eff_result = subprocess.run(eff_cmd, capture_output=True, text=True)
                    if eff_result.returncode == 0:
                        self.cpu_cores_eff = int(eff_result.stdout.strip())
                    else:
                        self.cpu_cores_eff = 0
                else:  # Intel (성능 코어만 있음)
                    self.cpu_cores_perf = self.cpu_cores_total
                    self.cpu_cores_eff = 0
            except:
                self.cpu_cores_perf = self.cpu_cores_total
                self.cpu_cores_eff = 0
                
            # CPU 사용률은 psutil로 충분하므로 top 명령 제거
            # 이미 아래에서 psutil로 정보를 가져옴
                
            # vm_stat도 시간이 오래 걸리므로 제거
            # 메모리 정보는 psutil로 충분함
        else:
            # macOS가 아니거나 Docker 환경인 경우 기본 정보만 수집하고
            # 환경변수에서 가져오지 못한 정보 설정
            if not self.model:
                self.model = platform.machine()
            if not self.chip:
                self.chip = platform.processor() or "Unknown CPU"
            if not self.cpu_cores_total:
                self.cpu_cores_total = os.cpu_count() or 1
            if not self.cpu_cores_perf:
                self.cpu_cores_perf = self.cpu_cores_total
            if not self.cpu_cores_eff:
                self.cpu_cores_eff = 0
        
        # psutil로 CPU 정보 수집
        # interval=0 으로 즉시 현재 값 가져오기 (대기 없음)
        cpu_times = psutil.cpu_times_percent(interval=0)
        self.cpu_user = cpu_times.user
        self.cpu_system = cpu_times.system  
        self.cpu_idle = cpu_times.idle
        self.cpu_usage = 100.0 - self.cpu_idle
        
        logger.debug(f"psutil CPU 정보: 전체={self.cpu_usage:.1f}% (user={self.cpu_user:.1f}%, system={self.cpu_system:.1f}%, idle={self.cpu_idle:.1f}%)")
        host_stats_fetched = True
        
        # Docker 메모리 정보 (컨테이너 내부에서 실행 중)
        memory = psutil.virtual_memory()
        self.docker_memory_used = memory.used
        self.docker_memory_percent = memory.percent
        
        # Docker 소켓 경로 찾기
        docker_sock_paths = [
            "/var/run/docker.sock",
            os.path.expanduser("~/.orbstack/run/docker.sock"),
            "/var/run/orbstack/docker.sock"
        ]
        
        # Docker 메모리 정보 수집
        self.docker_available = False
        for sock_path in docker_sock_paths:
            if os.path.exists(sock_path):
                self.docker_available = True
                break
                
        # Docker 메모리 사용량은 동적으로 수집
        try:
            # Docker가 설치되어 있고 실행 중인지 확인
            docker_cmd = ["docker", "info", "--format", "{{.MemTotal}}"]
            docker_result = subprocess.run(docker_cmd, capture_output=True, text=True)
            if docker_result.returncode == 0:
                docker_mem = docker_result.stdout.strip()
                if docker_mem and docker_mem.isdigit():
                    self.docker_available = True
                    self.docker_memory_total = int(docker_mem)
            else:
                self.docker_available = False
        except:
            self.docker_available = False
        
        # 스왑 정보
        swap = psutil.swap_memory()
        self.swap_total = swap.total
        self.swap_used = swap.used
        
        # 업타임
        self.uptime = int(time.time() - psutil.boot_time())
        
        # 디스크 정보 - df 명령어로 호스트 정보 직접 수집
        try:
            # OrbStack 환경에서는 /hostfs/mnt/mac에 실제 Mac 디스크가 마운트됨
            if os.path.exists("/hostfs/mnt/mac"):
                df_cmd = ["df", "-k", "/hostfs/mnt/mac"]
            elif os.path.exists("/hostfs"):
                df_cmd = ["df", "-k", "/hostfs"]
            else:
                df_cmd = ["df", "-k", "/"]
            df_result = subprocess.run(df_cmd, capture_output=True, text=True)
            
            if df_result.returncode == 0:
                # 출력의 마지막 줄에서 정보 추출
                df_lines = df_result.stdout.strip().split('\n')
                if len(df_lines) >= 2:
                    # 공백으로 분리하여 필드 추출
                    fields = df_lines[-1].split()
                    if len(fields) >= 4:
                        # KB 단위를 바이트로 변환
                        disk_total_kb = int(fields[1])
                        disk_used_kb = int(fields[2])
                        disk_avail_kb = int(fields[3])
                        
                        self.disk_total = disk_total_kb * 1024
                        self.disk_used = disk_used_kb * 1024
                        self.disk_available = disk_avail_kb * 1024
                        
                        # 사용률 계산
                        if self.disk_total > 0:
                            self.disk_percent = (self.disk_used / self.disk_total) * 100.0
                        else:
                            self.disk_percent = 0.0
                        
                        logger.debug(f"디스크 정보 (df): 총 {self.disk_total / (1024**3):.1f}GB, "
                                    f"사용 {self.disk_used / (1024**3):.1f}GB, "
                                    f"사용률 {self.disk_percent:.1f}%")
                    else:
                        raise ValueError("df 출력 형식이 예상과 다릅니다")
                else:
                    raise ValueError("df 출력이 비어있습니다")
            else:
                raise Exception(f"df 명령 실패: {df_result.stderr}")
                
        except Exception as e:
            logger.error(f"df 명령으로 디스크 정보 수집 실패: {e}")
            # 실패 시 psutil로 폴백
            try:
                disk = psutil.disk_usage('/')
                self.disk_total = disk.total
                self.disk_used = disk.used
                self.disk_available = disk.free
                self.disk_percent = disk.percent
                logger.debug(f"디스크 정보 (psutil): 총 {self.disk_total / (1024**3):.1f}GB, "
                            f"사용 {self.disk_used / (1024**3):.1f}GB, "
                            f"사용률 {self.disk_percent:.1f}%")
            except Exception as e2:
                logger.error(f"psutil로도 디스크 정보 수집 실패: {e2}")
                # 모든 방법 실패 시 환경변수 사용
                env_disk_total_gb = int(os.environ.get("HOST_DISK_TOTAL_GB", "0"))
                if env_disk_total_gb > 0:
                    self.disk_total = env_disk_total_gb * 1073741824
                    self.disk_used = 0
                    self.disk_available = self.disk_total
                    self.disk_percent = 0.0
                else:
                    self.disk_total = 0
                    self.disk_used = 0
                    self.disk_available = 0
                    self.disk_percent = 0.0
        
        return self.to_dict()
    
    def to_dict(self):
        """시스템 정보를 딕셔너리로 변환 (웹소켓 전송용)"""
        return {
            "host_name": self.hostname,
            "cpu_model": f"{self.model} ({self.chip})",
            "cpu_usage": round(self.cpu_usage, 2),
            "cpu_cores": self.cpu_cores_total,
            "cpu_perf_cores": self.cpu_cores_perf,
            "cpu_eff_cores": self.cpu_cores_eff,
            "cpu_user": round(self.cpu_user, 2),
            "cpu_system": round(self.cpu_system, 2),
            "cpu_idle": round(self.cpu_idle, 2),
            "host_memory_total": self.host_memory_total,
            "docker_available": self.docker_available,
            "docker_memory_total": self.docker_memory_total,
            "docker_memory_used": self.docker_memory_used,
            "docker_memory_percent": self.docker_memory_percent,
            "swap_total": self.swap_total,
            "swap_used": self.swap_used,
            "uptime": self.uptime,
            "disk_total": self.disk_total,
            "disk_used": self.disk_used,
            "disk_available": self.disk_available,
            "disk_percent": self.disk_percent
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
        
        # 60회 데이터 버퍼링을 위한 필드 추가
        self.sixty_point_buffer = {
            'system_cpu': [],
            'system_cpu_user': [],
            'system_cpu_system': [],
            'system_memory_percent': [],
            'system_memory_used': [],
            'disk_percent': [],
            'container_stats': {},  # {container_name: {'cpu': [], 'memory': [], 'memory_percent': []}}
            'node_states': {},  # {node_name: [states]}
            'data_sizes': [],
            'processing_times_60': [],
            'transmission_results': []  # True/False
        }
        self.sixty_point_count = 0
    
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
    
    def add_sixty_point_data(self, sys_metrics, containers, data_size, processing_time, success, configured_nodes=None):
        """60회 버퍼에 데이터 추가"""
        # 첫 번째 데이터인 경우 기본 정보 보관
        if self.sixty_point_count == 0:
            self.sixty_point_buffer['first_system'] = sys_metrics.copy()
            self.sixty_point_buffer['first_containers'] = {c['name']: c.copy() for c in containers}
            if configured_nodes:
                self.sixty_point_buffer['configured_nodes'] = configured_nodes
        
        # 시스템 메트릭 추가 (평균 계산용)
        self.sixty_point_buffer['system_cpu'].append(sys_metrics.get('cpu_usage', 0))
        self.sixty_point_buffer['system_cpu_user'].append(sys_metrics.get('cpu_user', 0))
        self.sixty_point_buffer['system_cpu_system'].append(sys_metrics.get('cpu_system', 0))
        self.sixty_point_buffer['system_memory_percent'].append(sys_metrics.get('docker_memory_percent', 0))
        self.sixty_point_buffer['system_memory_used'].append(sys_metrics.get('docker_memory_used', 0))
        self.sixty_point_buffer['disk_percent'].append(sys_metrics.get('disk_percent', 0))
        
        # 컨테이너별 메트릭 추가
        for container in containers:
            name = container.get('name', 'unknown')
            if name not in self.sixty_point_buffer['container_stats']:
                self.sixty_point_buffer['container_stats'][name] = {
                    'cpu': [],
                    'memory': [],
                    'memory_percent': [],
                    'state': []
                }
            
            self.sixty_point_buffer['container_stats'][name]['cpu'].append(container.get('cpu', {}).get('percent', 0))
            self.sixty_point_buffer['container_stats'][name]['memory'].append(container.get('memory', {}).get('usage', 0))
            self.sixty_point_buffer['container_stats'][name]['memory_percent'].append(container.get('memory', {}).get('percent', 0))
            self.sixty_point_buffer['container_stats'][name]['state'].append(container.get('status', 'unknown'))
        
        # 기타 메트릭
        self.sixty_point_buffer['data_sizes'].append(data_size)
        self.sixty_point_buffer['processing_times_60'].append(processing_time)
        self.sixty_point_buffer['transmission_results'].append(success)
        
        self.sixty_point_count += 1
    
    def should_send_summary(self):
        """60회 데이터가 모였는지 확인"""
        return self.sixty_point_count >= 60
    
    def calculate_sixty_point_summary(self, monitor_interval):
        """60회 데이터의 평균 통계 계산"""
        if self.sixty_point_count == 0:
            return None
        
        # 실제 경과 시간 계산 (초 단위)
        elapsed_seconds = self.sixty_point_count * monitor_interval
        
        # 첫 번째 데이터에서 기본 정보 가져오기
        first_system = self.sixty_point_buffer.get('first_system', {})
        first_containers = self.sixty_point_buffer.get('first_containers', {})
        
        # 시스템 평균값 계산 (원본 구조 유지)
        system_data = first_system.copy()
        
        # 평균값으로 업데이트
        system_data['cpu_usage'] = sum(self.sixty_point_buffer['system_cpu']) / len(self.sixty_point_buffer['system_cpu']) if self.sixty_point_buffer['system_cpu'] else 0
        system_data['cpu_user'] = sum(self.sixty_point_buffer['system_cpu_user']) / len(self.sixty_point_buffer['system_cpu_user']) if self.sixty_point_buffer['system_cpu_user'] else 0
        system_data['cpu_system'] = sum(self.sixty_point_buffer['system_cpu_system']) / len(self.sixty_point_buffer['system_cpu_system']) if self.sixty_point_buffer['system_cpu_system'] else 0
        system_data['cpu_idle'] = 100.0 - system_data['cpu_usage']
        system_data['docker_memory_used'] = int(sum(self.sixty_point_buffer['system_memory_used']) / len(self.sixty_point_buffer['system_memory_used'])) if self.sixty_point_buffer['system_memory_used'] else 0
        system_data['docker_memory_percent'] = sum(self.sixty_point_buffer['system_memory_percent']) / len(self.sixty_point_buffer['system_memory_percent']) if self.sixty_point_buffer['system_memory_percent'] else 0
        system_data['disk_percent'] = sum(self.sixty_point_buffer['disk_percent']) / len(self.sixty_point_buffer['disk_percent']) if self.sixty_point_buffer['disk_percent'] else 0
        
        # 컨테이너 평균값 계산 (배열 형태로)
        containers_data = []
        
        for container_name, stats in self.sixty_point_buffer['container_stats'].items():
            if stats['cpu'] and len(stats['cpu']) > 0 and container_name in first_containers:
                # 첫 번째 컨테이너 데이터 복사
                container_avg = first_containers[container_name].copy()
                
                # 노드 상태 빈도 계산
                state_counts = {}
                for state in stats['state']:
                    state_counts[state] = state_counts.get(state, 0) + 1
                
                # 가장 많이 나타난 상태를 현재 상태로
                most_common_state = max(state_counts.items(), key=lambda x: x[1])[0] if state_counts else 'unknown'
                container_avg['status'] = most_common_state
                
                # 평균값으로 업데이트
                container_avg['cpu']['percent'] = sum(stats['cpu']) / len(stats['cpu'])
                container_avg['memory']['usage'] = int(sum(stats['memory']) / len(stats['memory']))
                container_avg['memory']['percent'] = sum(stats['memory_percent']) / len(stats['memory_percent'])
                
                # 타임스탬프 업데이트
                container_avg['timestamp'] = int(time.time() * 1000)
                
                containers_data.append(container_avg)
        
        # 원래 포맷과 동일한 구조로 반환
        summary = {
            'system': system_data,
            'containers': containers_data,
            'configured_nodes': self.sixty_point_buffer.get('configured_nodes', [])
        }
        
        return summary
    
    def reset_sixty_point_buffer(self):
        """60회 버퍼 초기화"""
        self.sixty_point_buffer = {
            'system_cpu': [],
            'system_cpu_user': [],
            'system_cpu_system': [],
            'system_memory_percent': [],
            'system_memory_used': [],
            'disk_percent': [],
            'container_stats': {},
            'node_states': {},
            'data_sizes': [],
            'processing_times_60': [],
            'transmission_results': []
        }
        self.sixty_point_count = 0

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

# 소수점 형식화 함수
def format_decimal(value: float, places: int = 2) -> str:
    format_str = f"{{:.{places}f}}"
    return format_str.format(value)

# 전송 상태 출력 함수
def print_transmission_status(stats: TransmissionStats):
    status_color = COLOR_GREEN if stats.success_rate() > 95.0 else (
        COLOR_YELLOW if stats.success_rate() > 80.0 else COLOR_RED
    )
    
    cpu_color = get_color_for_value(stats.last_cpu_usage)
    mem_color = get_color_for_value(stats.last_memory_percent)
    
    processing_time = stats.processing_times[-1] if stats.processing_times else 0
    
    print(f"{COLOR_CYAN}[{time.strftime('%H:%M:%S')}] 데이터 전송 #{stats.total_sent}: "
          f"{cpu_color}{STYLE_BOLD}CPU {stats.last_cpu_usage:.2f}%{COLOR_RESET}, "
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
    print(f"{STYLE_BOLD}{COLOR_BLUE}CREDITCOIN NODE RESOURCE MONITOR{COLOR_RESET}                     "
          f"{time.strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # 컨테이너 정보 섹션
    if containers:
        # 헤더 출력
        print(f"{STYLE_BOLD}NODE{COLOR_RESET}            {STYLE_BOLD}CPU%{COLOR_RESET}    "
              f"{STYLE_BOLD}OF TOTAL%{COLOR_RESET}   {STYLE_BOLD}MEM USAGE{COLOR_RESET}          "
              f"{STYLE_BOLD}MEM%{COLOR_RESET}   {STYLE_BOLD}NET RX/TX{COLOR_RESET}")
        
        # 각 컨테이너 정보 출력
        total_cpu = 0.0
        total_cpu_of_total = 0.0
        total_mem_used = 0
        total_mem_limit = 0
        total_mem_percent = 0.0
        total_net_rx = 0
        total_net_tx = 0
        
        for container in containers:
            # CPU와 메모리 색상 가져오기
            cpu_color = get_color_for_value(container['cpu']['percent'])
            mem_color = get_color_for_value(container['memory']['percent'])
            
            # 메모리 단위 변환
            memory_str = format_memory(container['memory']['usage'], container['memory']['limit'])
            
            # 네트워크 단위 변환
            network_str = f"{format_bytes(container['network']['rx'])}/{format_bytes(container['network']['tx'])}"
            
            # CPU 총량 대비 비율 계산
            cpu_of_total = (container['cpu']['percent'] / sys_info['cpu_cores']) if sys_info['cpu_cores'] > 0 else 0
            
            print(f"{container['name']:<14} {cpu_color}{container['cpu']['percent']:>6.2f}%{COLOR_RESET} "
                  f"{cpu_of_total:>9.2f}% {memory_str:<20} "
                  f"{mem_color}{container['memory']['percent']:>6.2f}%{COLOR_RESET} "
                  f"{network_str:<15}")
                  
            # 총계 누적
            total_cpu += container['cpu']['percent']
            total_cpu_of_total += cpu_of_total
            total_mem_used += container['memory']['usage']
            if container['memory']['limit'] > 0:
                if total_mem_limit == 0:
                    total_mem_limit = container['memory']['limit']
                else:
                    # 컨테이너별 메모리 한계는 모두 동일한 값으로 가정
                    pass
            total_net_rx += container['network']['rx']
            total_net_tx += container['network']['tx']
        
        # 총 메모리 사용률 계산
        if total_mem_limit > 0:
            total_mem_percent = (total_mem_used / total_mem_limit) * 100.0
        
        # 구분선
        print("-" * 80)
        
        # 합계 행 출력
        total_memory_str = format_memory(total_mem_used, total_mem_limit)
        total_network_str = f"{format_bytes(total_net_rx)}/{format_bytes(total_net_tx)}"
        
        total_mem_color = get_color_for_value(total_mem_percent)
        total_cpu_color = get_color_for_value(total_cpu)
        
        print(f"{STYLE_BOLD}TOTAL{COLOR_RESET}          {total_cpu_color}{total_cpu:<7.2f}%{COLOR_RESET} "
              f"{total_cpu_of_total:<10.2f}% {total_memory_str:<20} "
              f"{total_mem_color}{total_mem_percent:<7.2f}%{COLOR_RESET} "
              f"{total_network_str:<15}")
        
        print()
    else:
        print("모니터링 중인 컨테이너가 없습니다.")
        print()
    
    # 시스템 정보 섹션
    print(f"{COLOR_BLUE}SYSTEM INFORMATION:{COLOR_RESET}")
    
    # 모델 정보
    model_display = f"{sys_info.get('host_name')} - {sys_info.get('cpu_model')}"
    print(f"{COLOR_YELLOW}MODEL:{COLOR_RESET} {model_display}")
    
    # CPU 사용률 정보
    cpu_usage_info = f"사용자 {sys_info.get('cpu_user', 0):.2f}%, 시스템 {sys_info.get('cpu_system', 0):.2f}%, 유휴 {sys_info.get('cpu_idle', 0):.2f}%"
    print(f"{COLOR_YELLOW}CPU USAGE:{COLOR_RESET} {cpu_usage_info}")
    
    # 메모리 정보
    host_memory_gb = sys_info.get('host_memory_total', 0) / 1024.0 / 1024.0 / 1024.0
    docker_used_gb = sys_info.get('docker_memory_used', 0) / 1024.0 / 1024.0 / 1024.0
    memory_info = f"호스트: {host_memory_gb:.2f} GB (Docker 사용: {docker_used_gb:.2f} GB, {sys_info.get('docker_memory_percent', 0):.2f}%)"
    print(f"{COLOR_YELLOW}MEMORY:{COLOR_RESET} {memory_info}")
    
    # Docker 메모리 정보 (가용한 경우)
    if sys_info.get('docker_available', False):
        docker_mem_gb = sys_info.get('docker_memory_total', 0) / 1024.0 / 1024.0 / 1024.0
        
        # 총 컨테이너 메모리 사용량 계산
        container_mem_total = sum(container['memory']['usage'] for container in containers)
        container_mem_gb = container_mem_total / 1024.0 / 1024.0 / 1024.0
        
        # 사용률 계산
        docker_mem_percent = 0
        if sys_info.get('docker_memory_total', 0) > 0:
            docker_mem_percent = (container_mem_total / sys_info.get('docker_memory_total', 1)) * 100.0
            
        docker_info = f"{docker_mem_gb:.2f} GB 할당됨 (노드 사용: {container_mem_gb:.2f} GB, {docker_mem_percent:.2f}%)"
        print(f"{COLOR_YELLOW}DOCKER:{COLOR_RESET} {docker_info}")
    
    # 디스크 정보
    disk_gb = sys_info.get('disk_total', 0) / 1024.0 / 1024.0 / 1024.0
    used_disk_gb = sys_info.get('disk_used', 0) / 1024.0 / 1024.0 / 1024.0
    avail_disk_gb = sys_info.get('disk_available', 0) / 1024.0 / 1024.0 / 1024.0
    disk_info = f"{used_disk_gb:.2f}GB/{disk_gb:.2f}GB (사용: {sys_info.get('disk_percent', 0):.2f}%, 남음: {avail_disk_gb:.2f}GB)"
    print(f"{COLOR_YELLOW}DISK:{COLOR_RESET} {disk_info}")
    
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
# 로컬 모드 실행 함수
async def run_local_mode(settings, node_names: List[str]):
    """로컬 모드로 모니터링 (터미널에 출력)"""
    print(CLEAR_SCREEN)
    print(f"{STYLE_BOLD}{COLOR_WHITE}크레딧코인 노드 실시간 모니터링 시작 (Ctrl+C로 종료){COLOR_RESET}")
    print("-----------------------------------------")
    
    # 시스템 정보 수집 객체
    system_info = SystemInfo()
    
    # Docker 클라이언트 설정
    docker_client = None
    docker_stats_client = None
    if not settings.NO_DOCKER:
        try:
            # 먼저 Docker Stats 클라이언트 사용 시도
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
            if not settings.NO_DOCKER:
                try:
                    if docker_stats_client:
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
    
    # 웹소켓 라이브러리 관련 import - 필요 시에만 임포트
    from websocket_client import WebSocketClient
    
    # 인증 처리
    auth_token = None
    if settings.REQUIRE_AUTH or settings.RUN_MODE == "auth":
        if not settings.AUTH_API_URL:
            logger.error("인증이 필요하지만 AUTH_API_URL이 설정되지 않았습니다.")
            return
        
        auth_token = await authenticate_user(settings.AUTH_API_URL, settings.AUTH_ALLOW_HTTP)
        if not auth_token:
            logger.error("인증 실패. 프로그램을 종료합니다.")
            return
        
        logger.info("인증 성공. 모니터링을 계속합니다.")
    
    # 설정값 적용
    server_id = settings.SERVER_ID
    
    # WebSocket URL 결정 - settings 변수를 명시적으로 전달
    ws_url_or_mode = get_websocket_url(settings)
    
    logger.info(f"모니터링 시작: 서버 ID={server_id}, 노드={node_names}, 간격={settings.MONITOR_INTERVAL}초")
    
    if settings.SERVER_URL:
        logger.info(f"WebSocket URL: {settings.SERVER_URL}")
    
    if not settings.SSL_VERIFY:
        logger.info("SSL 인증서 검증이 비활성화되었습니다.")
    
    # 클라이언트 초기화
    system_info = SystemInfo()
    
    # Docker 클라이언트 설정
    docker_client = None
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
    
    # WebSocket 클라이언트 초기화 (SSL 검증 옵션 및 토큰 적용)
    websocket_client = WebSocketClient(ws_url_or_mode, server_id, ssl_verify=settings.SSL_VERIFY, auth_token=auth_token, monitor_interval=settings.MONITOR_INTERVAL)
    websocket_client_instance = websocket_client  # 전역 변수에 할당하여 종료 시 접근 가능
    
    # 전송 통계
    stats = TransmissionStats()
    
    # PayoutChecker 초기화
    payout_checker = None
    if PayoutChecker:
        try:
            payout_checker = PayoutChecker()
            logger.info("PayoutChecker 초기화 완료")
        except Exception as e:
            logger.warning(f"PayoutChecker 초기화 실패: {e}")
    
    # EraMonitor 초기화
    era_monitor = None
    if EraMonitor:
        try:
            era_monitor = EraMonitor(websocket_client)
            websocket_client.set_era_monitor(era_monitor)  # WebSocketClient에 EraMonitor 설정
            logger.info("EraMonitor 초기화 완료")
        except Exception as e:
            logger.warning(f"EraMonitor 초기화 실패: {e}")
    
    # WebSocket 연결 (재시도 로직 포함)
    connected = False
    retry_count = 0
    max_retries = settings.MAX_RETRIES
    
    # 연결 시도 로직 (지수 백오프 적용)
    while not connected and not shutdown_event.is_set():
        connected = await websocket_client.connect()
        
        if not connected:
            retry_count += 1
            # 최대 재시도 횟수 초과 또는 무한 재시도(0) 확인
            if max_retries > 0 and retry_count > max_retries:
                logger.error(f"WebSocket 서버 연결 실패: 최대 재시도 횟수({max_retries}회) 초과")
                logger.error("로컬 모드로 전환하려면 --local 옵션을 사용하여 다시 시작하세요.")
                return  # 함수 종료
            
            # 지수 백오프 적용 (websocket_client와 동일한 로직)
            max_backoff = 1024
            if retry_count == 1:
                backoff = 1
            else:
                backoff = min(max_backoff, 2 ** (retry_count - 1))
            
            # 시간 표시 형식 개선
            if backoff >= 60:
                minutes = int(backoff // 60)
                seconds = int(backoff % 60)
                time_str = f"{minutes}분 {seconds}초" if seconds > 0 else f"{minutes}분"
            else:
                time_str = f"{int(backoff)}초"
                
            logger.warning(f"WebSocket 서버 연결 실패 ({retry_count}번째 시도)")
            logger.info(f"{time_str} 후 다시 시도합니다...")
            await asyncio.sleep(backoff)
            
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
            # 환경변수 재로드 확인 (10초마다)
            settings.reload_if_needed()
            
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
            if not settings.NO_DOCKER:
                t_start = time.time()
                try:
                    if docker_stats_client:
                        # Stats 클라이언트에서 데이터 가져오기 (이미 백그라운드에서 수집됨)
                        container_data = await docker_stats_client.get_stats_for_nodes(node_names)
                    
                    container_list = list(container_data.values())
                    
                    # mserver와 PostgreSQL 컨테이너 추가 수집
                    server_containers = await docker_stats_client.get_server_containers()
                    if server_containers:
                        container_list.extend(server_containers)
                        logger.debug(f"서버 컨테이너 {len(server_containers)}개 추가 수집")
                except Exception as e:
                    logger.error(f"Docker 정보 수집 실패: {e}")
                
                t_end = time.time()
                if t_end - t_start > 0.5:  # 실행 시간이 0.5초 이상인 경우만 로그
                    logger.debug(f"Docker 정보 수집 시간: {t_end - t_start:.3f}초")
            
            # 상태 정보 업데이트
            stats.last_cpu_usage = sys_metrics["cpu_usage"]
            stats.last_memory_percent = sys_metrics["docker_memory_percent"]
            stats.container_count = len(container_list)
            
            # 서버로 전송할 데이터 구성 (websocket_client가 감싸므로 내부 데이터만 전송)
            stats_data = {
                "system": sys_metrics,
                "containers": container_list,
                "configured_nodes": node_names  # 설정된 노드 목록 추가
            }
            
            # JSON으로 직렬화 및 전송
            json_data = stats_data  # websocket_client.send_stats가 type, serverId 등을 추가함
            json_str = json.dumps(stats_data)  # 로깅용 (실제 전송 X)
            stats.total_sent += 1
            stats.last_data_size = len(json_str)
            
            # 전송
            t_start = time.time()
            send_success = await websocket_client.send_stats(json_data)
            
            if send_success:
                t_end = time.time()
                send_time = t_end - t_start
                
                stats.success_count += 1
                stats.total_bytes_sent += len(json_str)
                
                # 전송 상태 출력
                loop_end_time = time.time()
                processing_time = loop_end_time - loop_start_time
                stats.add_processing_time(processing_time)
                
                # 60회 데이터 버퍼에 추가
                stats.add_sixty_point_data(
                    sys_metrics, 
                    container_list, 
                    len(json_str), 
                    processing_time, 
                    True,  # success
                    configured_nodes=node_names  # configured_nodes 전달
                )
                
                # 터미널에 출력만 하고 로그 출력은 제거
                print_transmission_status(stats)
                
                # 10회마다 누적 통계 로그 출력
                if stats.total_sent % 10 == 0:
                    logger.info(f"누적 통계 #{stats.total_sent}: 성공률 {stats.success_rate():.1f}%")
                
                # 60회마다 평균 통계 전송
                if stats.should_send_summary():
                    summary_data = stats.calculate_sixty_point_summary(settings.MONITOR_INTERVAL)
                    if summary_data:
                        # 페이아웃 체크 추가
                        if payout_checker:
                            try:
                                # summary_data에서 컨테이너 이름 목록 추출
                                containers = summary_data.get('containers', [])
                                logger.debug(f"Summary data keys: {summary_data.keys()}")
                                logger.debug(f"Total containers in summary: {len(containers)}")
                                logger.debug(f"Container names in summary: {[c.get('name') for c in containers]}")
                                
                                container_names = [c.get('name') for c in containers if c.get('name') and c.get('name').startswith(('node', '3node'))]
                                logger.debug(f"Filtered node container names: {container_names}")
                                
                                # 컨테이너 목록이 비어있으면 configured_nodes 사용
                                if not container_names and summary_data.get('configured_nodes'):
                                    container_names = summary_data.get('configured_nodes', [])
                                    logger.info(f"Using configured_nodes as fallback: {container_names}")
                                
                                if container_names:
                                    payout_info = await payout_checker.check_all_payouts(container_names)
                                    summary_data['payout_info'] = payout_info
                                    logger.info(f"페이아웃 체크 완료: {len(container_names)}개 컨테이너")
                                else:
                                    logger.warning("No container names found for payout check")
                                
                                # Era 전환 체크
                                if era_monitor and 'payout_info' in locals():
                                    try:
                                        transitions = await era_monitor.check_era_transition(payout_info)
                                        if transitions:
                                            summary_data['era_transitions'] = transitions
                                            logger.info(f"Era 전환 감지: {list(transitions.keys())}")
                                    except Exception as e:
                                        logger.error(f"Era 전환 체크 실패: {e}")
                            except Exception as e:
                                logger.error(f"페이아웃 체크 실패: {e}")
                                summary_data['payout_info'] = {"error": str(e)}
                        
                        logger.info(f"60회 평균 통계 계산 완료. 서버로 전송 중...")
                        summary_sent = await websocket_client.send_summary(summary_data)
                        if summary_sent:
                            logger.info(f"60회 평균 통계 전송 성공")
                            # 버퍼 초기화
                            stats.reset_sixty_point_buffer()
                        else:
                            logger.error("60회 평균 통계 전송 실패")
            else:
                stats.error_count += 1
                logger.error("데이터 전송 실패")
                
                # 실패한 경우에도 60회 데이터 버퍼에 추가
                stats.add_sixty_point_data(
                    sys_metrics, 
                    container_list, 
                    len(json_str), 
                    0,  # processing_time (실패 시 0)
                    False,  # success
                    configured_nodes=node_names  # configured_nodes 전달
                )
            
            # 실행 시간 계산
            loop_end_time = time.time()
            execution_time = loop_end_time - loop_start_time
            
            # 다음 루프 시작 시간 계산
            # 설정된 간격대로 정확히 실행되도록 함
            next_loop_time = loop_start_time + settings.MONITOR_INTERVAL
            current_time = time.time()
            wait_time = max(0, next_loop_time - current_time)
            
            logger.debug(f"루프 시간: 시작={loop_start_time:.3f}, 현재={current_time:.3f}, 다음={next_loop_time:.3f}")
            logger.debug(f"실행 시간={execution_time:.3f}초, 대기 시간={wait_time:.3f}초")
            
            if wait_time == 0:
                logger.debug(f"실행 시간({execution_time:.2f}초)이 설정 간격({settings.MONITOR_INTERVAL}초)을 초과")
            
            # 재연결 필요 체크
            if websocket_client.needs_reconnect and not websocket_client.reconnecting:
                logger.info("WebSocket 재연결이 필요합니다.")
                asyncio.create_task(websocket_client.reconnect())
            
            # 재연결 중이면 추가 대기
            if websocket_client.reconnecting and wait_time < 5.0:
                wait_time = 5.0
                logger.debug("WebSocket 재연결 중... 5초 대기")
            
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
async def run_auth_mode(settings):
    """인증 전용 모드 - 로그인만 수행하고 종료"""
    print(f"{COLOR_BLUE}{'='*50}{COLOR_RESET}")
    print(f"{COLOR_GREEN}     인증 전용 모드{COLOR_RESET}")
    print(f"{COLOR_BLUE}{'='*50}{COLOR_RESET}")
    print("")
    
    if not settings.AUTH_API_URL:
        print(f"{COLOR_RED}AUTH_API_URL이 설정되지 않았습니다.{COLOR_RESET}")
        return False
    
    # TTY 인증 처리
    token = await handle_tty_authentication(settings.AUTH_API_URL, settings.AUTH_ALLOW_HTTP)
    
    if token:
        print(f"\n{COLOR_GREEN}인증이 완료되었습니다.{COLOR_RESET}")
        print(f"{COLOR_GREEN}다음 실행부터는 저장된 토큰을 사용합니다.{COLOR_RESET}")
        return True
    else:
        print(f"\n{COLOR_RED}인증에 실패했습니다.{COLOR_RESET}")
        return False

async def main():
    # 인자 파싱
    args = parse_args()
    
    # 설정 로드
    settings = Settings(args)
    
    # 로그인 전용 모드 처리
    if settings.RUN_MODE == "auth":
        success = await run_auth_mode(settings)
        sys.exit(0 if success else 1)
    
    # 일반 모니터링 모드
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
shutdown_event = asyncio.Event()  # 종료 이벤트 초기화
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