#!/usr/bin/env python3
# websocket_client.py
import asyncio
import json
import logging
import ssl
import time
import websockets
import random
import os
from typing import Dict, List, Any, Optional

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class WebSocketClient:
    """WebSocket 클라이언트 클래스"""
    
    def __init__(self, url_or_mode: str, server_id: str, ssl_verify: bool = True):
        """WebSocket 클라이언트 초기화
        
        Args:
            url_or_mode: WebSocket URL 또는 연결 모드 (ws, wss, wss_internal, auto, custom)
            server_id: 서버 식별자
            ssl_verify: SSL 인증서 검증 여부
        """
        self.url_or_mode = url_or_mode
        self.server_id = server_id
        self.ssl_verify = ssl_verify
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
        
        # 환경 변수에서 직접 서버 호스트 가져오기
        self.server_host = os.environ.get("WS_SERVER_HOST", "192.168.0.24")
        
        # 기본 URL 설정
        self.base_urls = {
            "ws": f"ws://{self.server_host}:8080/ws",
            "wss": f"wss://{self.server_host}:8443/ws",
            "wss_internal": f"wss://{self.server_host}:8443/ws"
        }
        
        # 설정 정보 로깅
        logger.info(f"WebSocket 클라이언트 초기화: 모드={url_or_mode}, 서버ID={server_id}")
        logger.info(f"WebSocket 호스트: {self.server_host}")
        logger.info(f"WebSocket 기본 URL: ws={self.base_urls['ws']}, wss={self.base_urls['wss']}")
    
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
        """WebSocket 서버에 연결"""
        if self.url_or_mode == "auto":
            # 자동 모드: 자동 연결 시도
            logger.info("자동 모드: 자동 연결 시도")
            
            # SSL 컨텍스트 생성
            ssl_context = ssl.create_default_context()
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE if not self.ssl_verify else ssl.CERT_REQUIRED
            
            # WSS 자동 시도
            wss_url = self.base_urls["wss"]
            if await self.try_connect(wss_url, ssl_context):
                return True
            
            # WS 자동 시도
            ws_url = self.base_urls["ws"]
            if await self.try_connect(ws_url):
                return True
            
            logger.error("모든 WebSocket 연결 시도 실패")
            return False
            
        elif self.url_or_mode in ["ws", "wss", "wss_internal"]:
            # 지정된 모드: 해당 모드의 URL 사용
            url = self.base_urls.get(self.url_or_mode)
            ssl_context = None
            
            # SSL 관련 모드인 경우
            if self.url_or_mode in ["wss", "wss_internal"]:
                ssl_context = ssl.create_default_context()
                ssl_context.check_hostname = False
                ssl_context.verify_mode = ssl.CERT_NONE if not self.ssl_verify else ssl.CERT_REQUIRED
                logger.info("SSL 인증서 검증이 비활성화되었습니다.")
            
            return await self.try_connect(url, ssl_context)
        
        else:
            # 사용자 지정 URL로 간주
            if self.url_or_mode.startswith("wss"):
                ssl_context = ssl.create_default_context()
                # SSL 검증 비활성화 여부 확인
                if not self.ssl_verify or self.server_host in self.url_or_mode or "127.0.0.1" in self.url_or_mode:
                    ssl_context.check_hostname = False
                    ssl_context.verify_mode = ssl.CERT_NONE
                    if not self.ssl_verify:
                        logger.info("SSL 인증서 검증이 비활성화되었습니다.")
                    else:
                        logger.info("로컬호스트 연결을 위해 SSL 인증서 검증이 비활성화되었습니다.")
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
                        # INFO에서 DEBUG로 변경 - 일반 모드에서는 로그에 출력되지 않음
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
