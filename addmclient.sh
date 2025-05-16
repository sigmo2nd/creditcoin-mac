#!/bin/bash
# addmclient.sh - SSL 지원 Creditcoin 모니터링 클라이언트 설치 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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

# 모니터링 폴더 생성
mkdir -p ./mclient
mkdir -p ./mclient/certs

# 필요한 파일 생성
echo -e "${BLUE}파이썬 모니터링 클라이언트 파일 생성 중...${NC}"

# config.py 생성
cat > ./mclient/config.py << 'EOL'
import os
from pydantic_settings import BaseSettings
from pydantic import Field
from typing import Optional

class Settings(BaseSettings):
    # 기본 설정 (환경 변수에서 M_ 접두사를 사용하여 충돌 방지)
    SERVER_ID: str = Field(default="server1", env="M_SERVER_ID")
    NODE_NAMES: str = Field(default="node,3node", env="M_NODE_NAMES")
    MONITOR_INTERVAL: int = Field(default=5, env="M_MONITOR_INTERVAL")
    
    # WebSocket 설정
    WS_MODE: str = Field(default="auto", env="M_WS_MODE")  # auto, ws, wss, wss_internal, custom
    WS_SERVER_URL: Optional[str] = Field(default=None, env="M_WS_SERVER_URL")
    
    # Docker 설정
    CREDITCOIN_DIR: str = Field(default=os.path.expanduser("~/creditcoin-mac"), env="M_CREDITCOIN_DIR")
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

# 싱글톤 설정 인스턴스
settings = Settings()

# 설정 확인용 함수
def print_settings():
    print(f"Server ID: {settings.SERVER_ID}")
    print(f"Node Names: {settings.NODE_NAMES}")
    print(f"Monitor Interval: {settings.MONITOR_INTERVAL}")
    print(f"WebSocket Mode: {settings.WS_MODE}")
    print(f"WebSocket URL: {settings.WS_SERVER_URL}")
    print(f"Creditcoin Directory: {settings.CREDITCOIN_DIR}")

# WebSocket URL 결정 함수
def get_websocket_url():
    if settings.WS_MODE == "custom" and settings.WS_SERVER_URL:
        return settings.WS_SERVER_URL
    
    # 기본 URL 설정
    base_urls = {
        "ws": "ws://localhost:8080/ws",
        "wss": "wss://localhost:8443/ws",
        "wss_internal": "wss://localhost:8443/ws"
    }
    
    # auto 모드인 경우 wss -> wss_internal -> ws 순으로 시도
    if settings.WS_MODE == "auto":
        return "auto"  # 자동 연결 로직은 websocket_client에서 구현
    
    return base_urls.get(settings.WS_MODE, base_urls["ws"])
EOL

# websocket_client.py 생성
cat > ./mclient/websocket_client.py << 'EOL'
# websocket_client.py
import asyncio
import json
import logging
import ssl
import time
import websockets
import random
from typing import Dict, List, Any, Optional

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class WebSocketClient:
    def __init__(self, url_or_mode: str, server_id: str):
        self.url_or_mode = url_or_mode
        self.server_id = server_id
        self.ws = None
        self.connected = False
        self.reconnect_attempts = 0
        self.last_success_time = 0
        self.sequence_number = 0
        self.pending_ack = {}
        self.max_retry_count = 5
        self.message_queue = []
        self.max_queue_size = 100
        self.ping_interval = 30  # 30초마다 핑
        self.ping_task = None
        self.heartbeat_task = None
        
        # 기본 URL 설정 (모두 로컬 주소로 설정)
        self.base_urls = {
            "ws": "ws://localhost:8080/ws",
            "wss": "wss://localhost:8443/ws",
            "wss_internal": "wss://localhost:8443/ws"
        }
    
    async def try_connect(self, url: str, ssl_context: Optional[ssl.SSLContext] = None) -> bool:
        """특정 URL로 연결 시도"""
        try:
            logger.info(f"WebSocket 연결 시도: {url}")
            
            # 연결 타임아웃 및 상세 옵션 설정
            if ssl_context:
                self.ws = await websockets.connect(
                    url, 
                    ssl=ssl_context,
                    ping_interval=20,
                    ping_timeout=10,
                    close_timeout=5,
                    max_size=10_485_760,  # 10MB
                    max_queue=32,
                    compression=None
                )
            else:
                self.ws = await websockets.connect(
                    url,
                    ping_interval=20,
                    ping_timeout=10,
                    close_timeout=5,
                    max_size=10_485_760,  # 10MB
                    max_queue=32,
                    compression=None
                )
            
            # 연결 성공 - 서버 ID 전송
            register_message = {
                "type": "register", 
                "serverId": self.server_id,
                "version": "1.0.0",
                "timestamp": int(time.time() * 1000)
            }
            
            await self.ws.send(json.dumps(register_message))
            
            # 등록 확인 메시지 대기
            try:
                response = await asyncio.wait_for(self.ws.recv(), timeout=5.0)
                response_data = json.loads(response)
                
                if response_data.get("type") == "register_ack" and response_data.get("status") == "success":
                    logger.info(f"WebSocket 연결 및 등록 성공: {url}")
                    self.connected = True
                    self.last_success_time = time.time()
                    
                    # 심비트 및 핑 태스크 시작
                    self._start_ping_task()
                    self._start_heartbeat_task()
                    
                    # 큐에 있는 메시지 전송
                    await self._flush_message_queue()
                    
                    return True
                else:
                    logger.error(f"WebSocket 등록 실패: {response_data}")
                    if self.ws and not self.ws.closed:
                        await self.ws.close()
                    return False
            except asyncio.TimeoutError:
                logger.error("WebSocket 등록 응답 타임아웃")
                if self.ws and not self.ws.closed:
                    await self.ws.close()
                return False
            except Exception as e:
                logger.error(f"WebSocket 등록 중 오류 발생: {str(e)}")
                if self.ws and not self.ws.closed:
                    await self.ws.close()
                return False
        
        except Exception as e:
            logger.error(f"WebSocket 연결 실패 ({url}): {str(e)}")
            return False
    
    def _start_ping_task(self):
        """정기적인 핑 메시지 전송 태스크 시작"""
        if self.ping_task:
            self.ping_task.cancel()
        
        self.ping_task = asyncio.create_task(self._ping_loop())
    
    def _start_heartbeat_task(self):
        """정기적인 하트비트 메시지 전송 태스크 시작"""
        if self.heartbeat_task:
            self.heartbeat_task.cancel()
        
        self.heartbeat_task = asyncio.create_task(self._heartbeat_loop())
    
    async def _ping_loop(self):
        """정기적인 핑 메시지 전송"""
        try:
            while self.connected and self.ws and not self.ws.closed:
                await asyncio.sleep(self.ping_interval)
                
                if self.ws and not self.ws.closed:
                    try:
                        # 핑 메시지 전송
                        pong_waiter = await self.ws.ping()
                        await asyncio.wait_for(pong_waiter, timeout=5)
                        logger.debug("Ping/Pong 성공")
                    except Exception as e:
                        logger.warning(f"Ping 실패: {str(e)}")
                        self.connected = False
                        await self.reconnect()
                        break
        except asyncio.CancelledError:
            # 태스크가 취소됨
            pass
        except Exception as e:
            logger.error(f"Ping 루프 오류: {str(e)}")
            self.connected = False
            await self.reconnect()
    
    async def _heartbeat_loop(self):
        """정기적인 하트비트 메시지 전송"""
        try:
            while self.connected and self.ws and not self.ws.closed:
                await asyncio.sleep(45)  # 45초마다 하트비트
                
                if self.ws and not self.ws.closed:
                    try:
                        heartbeat_message = {
                            "type": "heartbeat", 
                            "serverId": self.server_id,
                            "timestamp": int(time.time() * 1000)
                        }
                        
                        await self.ws.send(json.dumps(heartbeat_message))
                        logger.debug("하트비트 메시지 전송 성공")
                    except Exception as e:
                        logger.warning(f"하트비트 전송 실패: {str(e)}")
                        self.connected = False
                        await self.reconnect()
                        break
        except asyncio.CancelledError:
            # 태스크가 취소됨
            pass
        except Exception as e:
            logger.error(f"하트비트 루프 오류: {str(e)}")
            self.connected = False
            await self.reconnect()
    
    async def connect(self) -> bool:
        """WebSocket 서버에 연결 (자동 또는 지정된 URL)"""
        if self.url_or_mode == "auto":
            # 자동 모드: wss -> wss_internal -> ws 순으로 시도
            
            # 1. WSS 내부 인증서 시도
            ssl_context = ssl.create_default_context()
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE
            if await self.try_connect(self.base_urls["wss_internal"], ssl_context):
                return True
            
            # 2. 일반 WS 시도
            if await self.try_connect(self.base_urls["ws"]):
                return True
            
            logger.error("모든 WebSocket 연결 시도 실패")
            return False
        
        elif self.url_or_mode in self.base_urls:
            # 지정된 모드로 연결
            url = self.base_urls[self.url_or_mode]
            ssl_context = None
            
            if self.url_or_mode == "wss":
                ssl_context = ssl.create_default_context()
                ssl_context.check_hostname = False
                ssl_context.verify_mode = ssl.CERT_NONE
            elif self.url_or_mode == "wss_internal":
                ssl_context = ssl.create_default_context()
                ssl_context.check_hostname = False
                ssl_context.verify_mode = ssl.CERT_NONE
            
            return await self.try_connect(url, ssl_context)
        
        else:
            # 사용자 지정 URL로 간주
            if self.url_or_mode.startswith("wss"):
                ssl_context = ssl.create_default_context()
                # 내부 인증서인지 확인
                if "localhost" in self.url_or_mode or "127.0.0.1" in self.url_or_mode:
                    ssl_context.check_hostname = False
                    ssl_context.verify_mode = ssl.CERT_NONE
                return await self.try_connect(self.url_or_mode, ssl_context)
            else:
                return await self.try_connect(self.url_or_mode)
    
    async def _flush_message_queue(self):
        """큐에 있는 메시지 전송"""
        if not self.connected or not self.ws or self.ws.closed:
            return
        
        logger.info(f"큐에 있는 메시지 {len(self.message_queue)}개 전송 시도")
        
        while self.message_queue and self.connected and self.ws and not self.ws.closed:
            message = self.message_queue.pop(0)
            try:
                await self.ws.send(json.dumps(message))
                logger.info(f"큐에 있던 메시지 전송 성공: {message.get('type')}")
                
                # 응답 대기가 필요한 메시지인 경우
                if message.get("type") == "stats":
                    try:
                        response = await asyncio.wait_for(self.ws.recv(), timeout=5.0)
                        response_data = json.loads(response)
                        logger.debug(f"메시지 응답 수신: {response_data}")
                    except asyncio.TimeoutError:
                        logger.warning("메시지 응답 타임아웃")
                    except Exception as e:
                        logger.warning(f"메시지 응답 처리 중 오류: {str(e)}")
            
            except Exception as e:
                logger.error(f"큐 메시지 전송 실패: {str(e)}")
                # 실패한 메시지를 다시 큐에 추가
                self.message_queue.insert(0, message)
                self.connected = False
                await self.reconnect()
                break
    
    async def send_stats(self, stats: Dict[str, Any]) -> bool:
        """수집된 통계 데이터 전송"""
        if not self.connected or not self.ws:
            # 연결이 없으면 메시지를 큐에 추가하고 재연결 시도
            logger.warning("WebSocket 연결이 없습니다. 메시지를 큐에 추가하고 재연결을 시도합니다.")
            
            # 시퀀스 번호 증가
            self.sequence_number += 1
            
            # 메시지 생성
            message = {
                "type": "stats",
                "serverId": self.server_id,
                "timestamp": int(time.time() * 1000),
                "sequence": self.sequence_number,
                "data": stats
            }
            
            # 큐 크기 제한
            if len(self.message_queue) < self.max_queue_size:
                self.message_queue.append(message)
            else:
                # 큐가 꽉 찼으면 가장 오래된 메시지 제거
                self.message_queue.pop(0)
                self.message_queue.append(message)
                logger.warning("메시지 큐가 꽉 찼습니다. 가장 오래된 메시지를 제거합니다.")
            
            # 재연결 시도
            await self.reconnect()
            return False
        
        try:
            # 시퀀스 번호 증가
            self.sequence_number += 1
            
            # 메시지 생성
            message = {
                "type": "stats",
                "serverId": self.server_id,
                "timestamp": int(time.time() * 1000),
                "sequence": self.sequence_number,
                "data": stats
            }
            
            # 메시지 전송
            await self.ws.send(json.dumps(message))
            
            # 응답 대기
            ack_received = False
            max_attempts = 5  # 최대 응답 대기 시도 횟수
            attempts = 0
            
            while attempts < max_attempts and not ack_received:
                try:
                    response = await asyncio.wait_for(self.ws.recv(), timeout=2.0)
                    response_data = json.loads(response)
                    
                    # 메시지 유형 확인
                    msg_type = response_data.get("type", "")
                    
                    # stats_ack 메시지 처리
                    if msg_type == "stats_ack":
                        logger.debug(f"통계 데이터 전송 성공 (시퀀스: {self.sequence_number})")
                        self.last_success_time = time.time()
                        ack_received = True
                        return True
                        
                    # heartbeat_ack 및 기타 메시지 처리
                    elif msg_type in ["heartbeat_ack", "pong"]:
                        # 다른 메시지 유형 무시하고 계속 대기
                        logger.debug(f"다른 유형의 메시지 수신: {msg_type}, 계속 대기")
                        attempts += 1
                        continue
                    else:
                        # 알 수 없는 메시지 유형
                        logger.debug(f"알 수 없는 메시지 유형 수신: {msg_type}, 계속 대기")
                        attempts += 1
                        continue
                    
                except asyncio.TimeoutError:
                    logger.debug("응답 대기 타임아웃, 재시도...")
                    attempts += 1
                    
                    # 연결 상태 확인
                    if attempts == max_attempts and self.ws and not self.ws.closed:
                        try:
                            # 간단한 핑으로 연결 확인
                            pong_waiter = await self.ws.ping()
                            await asyncio.wait_for(pong_waiter, timeout=1.0)
                            logger.debug("핑/퐁 성공, 서버는 여전히 응답합니다. 전송 성공으로 간주")
                            self.last_success_time = time.time()
                            return True
                        except:
                            logger.warning("핑/퐁 실패, 연결 문제로 간주")
                            self.connected = False
                            await self.reconnect()
                            return False
            
            # 최대 시도 횟수에 도달했지만 ack_received가 여전히 False인 경우
            if not ack_received:
                # 연결이 살아있는지 확인하고 수동으로 성공 판단
                if self.ws and not self.ws.closed:
                    logger.info("stats_ack 메시지를 수신하지 못했지만 연결이 유지되고 있으므로 성공으로 간주")
                    return True
                else:
                    logger.warning("stats_ack 메시지를 수신하지 못했고 연결이 끊어짐")
                    self.connected = False
                    await self.reconnect()
                    return False
                
        except websockets.exceptions.ConnectionClosed as e:
            logger.warning(f"연결이 종료되었습니다: {e}")
            self.connected = False
            
            # 메시지를 큐에 추가
            if len(self.message_queue) < self.max_queue_size:
                message = {
                    "type": "stats",
                    "serverId": self.server_id,
                    "timestamp": int(time.time() * 1000),
                    "sequence": self.sequence_number,
                    "data": stats
                }
                self.message_queue.append(message)
            
            # 재연결 시도
            await self.reconnect()
            return False
        
        except Exception as e:
            logger.error(f"데이터 전송 중 오류 발생: {str(e)}")
            self.connected = False
            
            # 메시지를 큐에 추가
            if len(self.message_queue) < self.max_queue_size:
                message = {
                    "type": "stats",
                    "serverId": self.server_id,
                    "timestamp": int(time.time() * 1000),
                    "sequence": self.sequence_number,
                    "data": stats
                }
                self.message_queue.append(message)
            
            # 재연결 시도
            await self.reconnect()
            return False
    
    async def reconnect(self) -> bool:
        """연결 재시도 (지수 백오프 적용 및 개선된 재시도 전략)"""
        if self.connected:
            return True
        
        # 타스크 취소
        if self.ping_task:
            self.ping_task.cancel()
            self.ping_task = None
        
        if self.heartbeat_task:
            self.heartbeat_task.cancel()
            self.heartbeat_task = None
        
        # WebSocket 연결 닫기
        if self.ws and not self.ws.closed:
            await self.ws.close()
        
        self.reconnect_attempts += 1
        
        # 지수 백오프 + 지터(무작위성)
        max_backoff = 60  # 최대 60초 지연
        base_delay = min(max_backoff, 2 ** min(self.reconnect_attempts, 5))
        jitter = random.uniform(0, 0.5 * base_delay)  # 0-50% 지터
        backoff = base_delay + jitter
        
        # 연결 시도 로깅 - 마이크로초 단위의 타임스탬프 포함
        logger.info(f"WebSocket 재연결 시도 ({self.reconnect_attempts}번째): {backoff:.2f}초 후 시도 (타임스탬프: {time.time():.6f})")
        await asyncio.sleep(backoff)
        
        # 재연결 시도
        connected = await self.connect()
        
        if connected:
            self.reconnect_attempts = 0
            logger.info(f"WebSocket 재연결 성공 (타임스탬프: {time.time():.6f})")
            
            # 큐에 있는 메시지 전송
            await self._flush_message_queue()
        else:
            # 시간이 많이 지났으면 재연결 시도 횟수 감소
            current_time = time.time()
            if self.last_success_time > 0 and (current_time - self.last_success_time) > 300:  # 5분 이상 지남
                logger.info("마지막 성공 연결로부터 5분 이상 지났습니다. 재연결 카운터 리셋")
                self.reconnect_attempts = 0
        
        return connected
    
    async def disconnect(self) -> None:
        """WebSocket 연결 종료"""
        # 타스크 취소
        if self.ping_task:
            self.ping_task.cancel()
            self.ping_task = None
        
        if self.heartbeat_task:
            self.heartbeat_task.cancel()
            self.heartbeat_task = None
        
        # WebSocket 연결 닫기
        if self.ws and not self.ws.closed:
            await self.ws.close()
        
        self.connected = False
        logger.info("WebSocket 연결이 종료되었습니다.")
EOL

# docker_stats_client.py 생성
cat > ./mclient/docker_stats_client.py << 'EOL'
# docker_stats_client.py
import asyncio
import json
import logging
import time
import os
import subprocess
from typing import Dict, List, Any, Optional

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class DockerStatsClient:
    """Docker 컨테이너 통계를 수집하는 클라이언트"""
    
    def __init__(self):
        self.docker_available = False
        self.container_stats = {}  # 컨테이너 이름 -> 통계 데이터
        self.stats_process = None
        self.monitoring_task = None
        self.running = False
        self.update_count = 0  # 업데이트 횟수를 클래스 변수로 저장
        self.initialized = False  # 초기화 완료 플래그
        self.initialization_lock = asyncio.Lock()  # 초기화 중복 방지 락
        
        # WebSocket 라이브러리 로깅 레벨 상향 조정 (DEBUG -> INFO)
        # 이렇게 하면 DEBUG 수준의 메시지는 표시되지 않음
        logging.getLogger('websockets').setLevel(logging.WARNING)
        logging.getLogger('websockets.client').setLevel(logging.WARNING)
        logging.getLogger('websockets.server').setLevel(logging.WARNING)
        logging.getLogger('websockets.protocol').setLevel(logging.WARNING)
        
        # Docker 명령어 사용 가능 여부 확인
        try:
            result = subprocess.run(["docker", "version"], capture_output=True, text=True)
            if result.returncode == 0:
                self.docker_available = True
                logger.info("Docker 사용 가능")
            else:
                logger.error("Docker 사용 불가: %s", result.stderr)
        except Exception as e:
            logger.error("Docker 확인 중 오류: %s", str(e))
    
    async def start_stats_monitoring(self, node_patterns: List[str]=None):
        """스트림 모드로 Docker stats 모니터링 시작"""
        if not self.docker_available:
            logger.error("Docker를 사용할 수 없습니다.")
            return False
        
        if self.monitoring_task is not None:
            logger.warning("이미 모니터링이 실행 중입니다.")
            return True
        
        # 스트림 모드로 docker stats 시작
        self.running = True
        self.monitoring_task = asyncio.create_task(self._monitor_stats_stream())
        logger.info("Docker stats 스트림 모니터링 시작")
        
        # 초기 데이터가 수집될 때까지 대기 (최대 5초)
        for _ in range(10):  # 0.5초 간격으로 10번 확인 (최대 5초)
            if len(self.container_stats) > 0:
                self.initialized = True
                logger.info(f"Docker 통계 초기화 완료: {len(self.container_stats)}개 컨테이너 발견")
                return True
            await asyncio.sleep(0.5)
        
        # 초기화는 실패했지만 백그라운드 작업은 계속 실행
        logger.warning("Docker 통계 초기화 시간 초과. 백그라운드에서 계속 시도합니다.")
        return True
    
    async def stop_stats_monitoring(self):
        """모니터링 중지"""
        self.running = False
        
        if self.stats_process and self.stats_process.poll() is None:
            try:
                self.stats_process.terminate()
                await asyncio.sleep(0.5)
                if self.stats_process.poll() is None:
                    self.stats_process.kill()
            except:
                pass
        
        if self.monitoring_task:
            self.monitoring_task.cancel()
            try:
                await self.monitoring_task
            except asyncio.CancelledError:
                pass
            self.monitoring_task = None
        
        logger.info("Docker stats 모니터링 중지")
        return True
    
    async def _monitor_stats_stream(self):
        """Docker stats 스트림 모니터링 실행"""
        try:
            # docker stats 명령 실행 (스트림 모드)
            # --format "{{ json . }}": JSON 형식으로 출력
            cmd = ["docker", "stats", "--format", "{{ json . }}"]
            
            logger.info(f"Docker stats 스트림 시작: {' '.join(cmd)}")
            
            # 비동기 프로세스 실행
            self.stats_process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            
            # 에러 스트림 읽기 태스크
            error_task = asyncio.create_task(self._read_stderr())
            
            # 메인 스트림 처리
            buffer = ""
            
            try:
                while self.running:
                    # 데이터 읽기
                    try:
                        chunk = await asyncio.wait_for(self.stats_process.stdout.read(4096), 0.5)
                        if not chunk:
                            if self.stats_process.returncode is not None:
                                logger.warning(f"Docker stats 프로세스 종료 (코드: {self.stats_process.returncode})")
                                break
                            await asyncio.sleep(0.1)
                            continue
                        
                        # 버퍼에 데이터 추가
                        buffer += chunk.decode('utf-8')
                        
                        # JSON 객체 찾기
                        json_objects = self._extract_json_objects(buffer)
                        buffer = json_objects.get('remainder', '')
                        
                        # 찾은 JSON 객체 처리
                        for json_str in json_objects.get('objects', []):
                            try:
                                # JSON 파싱
                                stats_json = json.loads(json_str)
                                
                                # 컨테이너 이름 추출
                                container_name = stats_json.get("Name", "")
                                if not container_name:
                                    continue
                                
                                # 데이터 처리
                                processed_stats = self._process_stats_json(stats_json)
                                if processed_stats:
                                    self.container_stats[container_name] = processed_stats
                                    self.update_count += 1  # 업데이트 횟수 증가
                                    
                                    # 초기화 상태 업데이트
                                    if not self.initialized and len(self.container_stats) > 0:
                                        self.initialized = True
                                        logger.info(f"Docker 통계 초기화 완료: {len(self.container_stats)}개 컨테이너 발견")
                            
                            except json.JSONDecodeError:
                                pass
                            except Exception as e:
                                logger.error(f"JSON 처리 중 오류: {e}")
                    except asyncio.TimeoutError:
                        # 타임아웃은 정상적인 상황으로 처리 (계속 진행)
                        continue
            
            except asyncio.CancelledError:
                logger.info("Docker stats 모니터링 태스크 취소됨")
                raise
            
            # 오류 태스크 취소
            error_task.cancel()
            try:
                await error_task
            except asyncio.CancelledError:
                pass
        
        except asyncio.CancelledError:
            logger.info("Docker stats 모니터링 태스크 취소됨")
            raise
        except Exception as e:
            logger.error(f"Docker stats 모니터링 중 오류: {e}")
        finally:
            if self.stats_process and self.stats_process.returncode is None:
                # 프로세스 종료 로직 강화
                try:
                    self.stats_process.terminate()
                    await asyncio.sleep(0.2)
                    
                    # 여전히 실행 중이면 강제 종료
                    if self.stats_process.returncode is None:
                        self.stats_process.kill()
                except:
                    pass
            self.stats_process = None
    
    def _extract_json_objects(self, text):
        """텍스트에서 JSON 객체 추출"""
        result = {'objects': [], 'remainder': ''}
        
        # 무한 루프 방지를 위한 최대 반복 횟수
        max_iterations = 100
        iterations = 0
        
        remainder = text
        
        while iterations < max_iterations:
            iterations += 1
            
            # JSON 객체 시작 위치 찾기
            start_pos = remainder.find('{')
            if start_pos == -1:
                # JSON 시작점이 없으면 종료
                result['remainder'] = remainder
                break
            
            # 중첩 중괄호 처리를 위한 균형 계산
            balance = 0
            pos = start_pos
            found_end = False
            
            while pos < len(remainder):
                char = remainder[pos]
                if char == '{':
                    balance += 1
                elif char == '}':
                    balance -= 1
                    if balance == 0:
                        # JSON 객체 완성
                        json_str = remainder[start_pos:pos+1]
                        try:
                            # 유효한 JSON인지 확인
                            json.loads(json_str)
                            result['objects'].append(json_str)
                            remainder = remainder[pos+1:]
                            found_end = True
                            break
                        except:
                            # 유효하지 않은 JSON은 무시
                            pass
                pos += 1
            
            if not found_end:
                # 완성된 JSON 객체를 찾지 못했으면 나머지를 저장하고 종료
                result['remainder'] = remainder
                break
        
        return result
    
    async def _read_stderr(self):
        """stderr 스트림 읽기"""
        try:
            while self.running and self.stats_process:
                line = await self.stats_process.stderr.readline()
                if not line:
                    break
                
                error_msg = line.decode('utf-8').strip()
                if error_msg:
                    logger.error(f"Docker stats 오류: {error_msg}")
        except asyncio.CancelledError:
            # 취소 처리
            raise
        except Exception as e:
            logger.error(f"stderr 읽기 중 오류: {e}")
    
    async def ensure_initialized(self):
        """Docker 통계가 초기화되었는지 확인하고, 필요하면 대기"""
        if self.initialized:
            return True
        
        # 동시 초기화 방지를 위한 락 획득
        async with self.initialization_lock:
            # 락 획득 후 재확인 (다른 스레드가 초기화를 완료했을 수 있음)
            if self.initialized:
                return True
            
            # Docker 데이터가 수집될 때까지 대기 (최대 5초)
            max_wait_time = 5  # 최대 5초 대기
            wait_interval = 0.2  # 0.2초 간격으로 확인
            start_time = time.time()
            
            while not self.initialized and time.time() - start_time < max_wait_time:
                if len(self.container_stats) > 0:
                    self.initialized = True
                    logger.info(f"Docker 통계 초기화 완료: {len(self.container_stats)}개 컨테이너 발견")
                    return True
                await asyncio.sleep(wait_interval)
            
            # 초기화 실패 시 빈 컨테이너로라도 초기화 설정
            if not self.initialized:
                logger.warning("Docker 통계 초기화 시간 초과. 데이터가 없는 상태로 진행합니다.")
                self.initialized = True
            
            return self.initialized
    
    async def get_stats_for_nodes(self, node_patterns: List[str]=None, show_log: bool=False) -> Dict[str, Any]:
        """지정된 노드 이름에 대한 통계 수집
        
        Args:
            node_patterns: 노드 이름 패턴 리스트
            show_log: 로그 출력 여부 (누적 통계 표시 시 True로 설정)
        """
        # 초기화 확인 및 대기 (필요한 경우)
        if not self.initialized:
            await self.ensure_initialized()
        
        if not self.docker_available:
            logger.warning("Docker를 사용할 수 없어 컨테이너 통계를 수집할 수 없습니다.")
            return {}
        
        # 현재 캐시된 데이터 사용
        if not self.container_stats:
            logger.warning("수집된 컨테이너 통계가 없습니다.")
            return {}
        
        # 로그 출력 여부 (누적 통계 표시 시에만)
        if show_log:
            containers_str = ', '.join(self.container_stats.keys())
            logger.info(f"Docker stats 현황: {self.update_count}건 수집 (컨테이너: {containers_str})")
        
        # 패턴 필터링 (패턴이 지정된 경우)
        if node_patterns:
            filtered_stats = {}
            
            for container_name, stats in self.container_stats.items():
                for pattern in node_patterns:
                    if pattern == container_name or pattern in container_name:
                        filtered_stats[container_name] = stats
                        break
            
            # 필터링된 컨테이너가 없으면 모든 컨테이너 반환
            if not filtered_stats:
                if show_log:
                    logger.warning(f"패턴 '{node_patterns}'과 일치하는 컨테이너가 없습니다. 전체 반환")
                return self.container_stats
            
            return filtered_stats
        else:
            # 모든 컨테이너 통계 반환
            return self.container_stats.copy()
    
    def _process_stats_json(self, stats_json: Dict) -> Dict[str, Any]:
        """Docker stats JSON 데이터 처리"""
        try:
            # 필수 필드 확인
            container_id = stats_json.get("ID", stats_json.get("Container", ""))
            container_name = stats_json.get("Name", "")
            
            if not container_id or not container_name:
                logger.warning("컨테이너 ID 또는 이름 없음")
                return None
            
            # CPU 사용량 파싱
            cpu_str = stats_json.get("CPUPerc", "0%")
            cpu_percent = self._parse_percentage(cpu_str)
            
            # 메모리 사용량 파싱
            mem_percent_str = stats_json.get("MemPerc", "0%")
            mem_percent = self._parse_percentage(mem_percent_str)
            
            mem_usage = stats_json.get("MemUsage", "0B / 0B")
            mem_used = 0
            mem_limit = 0
            
            # 메모리 사용량/한계 파싱
            try:
                if " / " in mem_usage:
                    mem_parts = mem_usage.split(" / ")
                    mem_used_str = mem_parts[0]
                    mem_limit_str = mem_parts[1]
                    
                    mem_used = self._parse_size_with_unit(mem_used_str)
                    mem_limit = self._parse_size_with_unit(mem_limit_str)
                elif "/" in mem_usage:
                    mem_parts = mem_usage.split("/")
                    mem_used_str = mem_parts[0].strip()
                    mem_limit_str = mem_parts[1].strip()
                    
                    mem_used = self._parse_size_with_unit(mem_used_str)
                    mem_limit = self._parse_size_with_unit(mem_limit_str)
            except Exception as e:
                logger.warning(f"메모리 사용량 파싱 실패: {mem_usage} - {str(e)}")
            
            # 네트워크 사용량 파싱
            net_io = stats_json.get("NetIO", "0B / 0B")
            net_rx = 0
            net_tx = 0
            
            try:
                if " / " in net_io:
                    net_parts = net_io.split(" / ")
                    net_rx = self._parse_size_with_unit(net_parts[0])
                    net_tx = self._parse_size_with_unit(net_parts[1])
                elif "/" in net_io:
                    net_parts = net_io.split("/")
                    net_rx = self._parse_size_with_unit(net_parts[0].strip())
                    net_tx = self._parse_size_with_unit(net_parts[1].strip())
            except Exception as e:
                logger.warning(f"네트워크 I/O 파싱 실패: {net_io} - {str(e)}")
            
            # 디스크 IO 파싱
            disk_io = stats_json.get("BlockIO", "0B / 0B")
            disk_read = 0
            disk_write = 0
            
            try:
                if " / " in disk_io:
                    disk_parts = disk_io.split(" / ")
                    disk_read = self._parse_size_with_unit(disk_parts[0])
                    disk_write = self._parse_size_with_unit(disk_parts[1])
                elif "/" in disk_io:
                    disk_parts = disk_io.split("/")
                    disk_read = self._parse_size_with_unit(disk_parts[0].strip())
                    disk_write = self._parse_size_with_unit(disk_parts[1].strip())
            except Exception as e:
                logger.warning(f"디스크 I/O 파싱 실패: {disk_io} - {str(e)}")
            
            # 컨테이너 별명 (nickname) 설정 - 패턴 기반으로 자동 결정
            nickname = None
            
            # 컨테이너 이름에서 패턴 찾기
            if container_name.startswith("3node"):
                nickname = f"Creditcoin 3.0 Node {container_name[5:]}"
            elif container_name.startswith("node"):
                nickname = f"Creditcoin 2.0 Node {container_name[4:]}"
            elif "node" in container_name.lower():
                # 기타 노드 패턴 인식
                nickname = f"Node {container_name}"
            elif "creditcoin" in container_name.lower():
                nickname = f"Creditcoin {container_name}"
            else:
                # 특별한 패턴이 없는 경우 컨테이너 이름 그대로 사용
                nickname = container_name
            
            # 결과 구성
            return {
                "id": container_id,
                "name": container_name,
                "status": "running",
                "cpu": {
                    "percent": round(cpu_percent, 2),
                    "cores": os.cpu_count() or 1
                },
                "memory": {
                    "usage": mem_used,
                    "limit": mem_limit,
                    "percent": round(mem_percent, 2)
                },
                "network": {
                    "rx": net_rx,
                    "tx": net_tx
                },
                "disk": {
                    "read": disk_read,
                    "write": disk_write
                },
                "nickname": nickname,
                "timestamp": int(time.time() * 1000)
            }
        
        except Exception as e:
            logger.error(f"Stats JSON 처리 중 오류: {str(e)}")
            return None
    
    def _parse_percentage(self, percent_str: str) -> float:
        """백분율 문자열 파싱"""
        try:
            if not percent_str:
                return 0.0
            
            # '%' 제거하고 숫자만 추출
            percent_str = percent_str.strip().rstrip('%')
            return float(percent_str)
        except Exception as e:
            logger.warning(f"백분율 파싱 실패: {percent_str} - {str(e)}")
            return 0.0
    
    def _parse_size_with_unit(self, size_str: str) -> int:
        """단위가 있는 크기 문자열을 바이트 값으로 변환"""
        try:
            if not size_str or size_str == "0":
                return 0
            
            # 정규 표현식으로 숫자와 단위 분리
            import re
            match = re.match(r'^([0-9.]+)\s*([A-Za-z]+)?$', size_str.strip())
            
            if not match:
                # 숫자만 있는 경우
                try:
                    return int(float(size_str.strip()))
                except:
                    return 0
            
            value = float(match.group(1))
            unit = match.group(2) if match.group(2) else 'B'
            
            # 단위 변환 테이블
            units = {
                'B': 1,
                'KB': 1024,
                'MB': 1024 ** 2,
                'GB': 1024 ** 3,
                'TB': 1024 ** 4,
                'KiB': 1024,
                'MiB': 1024 ** 2,
                'GiB': 1024 ** 3,
                'TiB': 1024 ** 4,
                # 단축 형태 추가
                'K': 1024,
                'M': 1024 ** 2,
                'G': 1024 ** 3,
                'T': 1024 ** 4,
                'Ki': 1024,
                'Mi': 1024 ** 2,
                'Gi': 1024 ** 3,
                'Ti': 1024 ** 4
            }
            
            # 알려진 단위가 아닌 경우
            if unit not in units:
                logger.warning(f"알 수 없는 단위: {unit} (전체: {size_str})")
                return int(value)
            
            # 바이트 값으로 변환
            return int(value * units[unit])
            
        except Exception as e:
            logger.warning(f"크기 파싱 실패: {size_str} - {str(e)}")
            return 0
EOL

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