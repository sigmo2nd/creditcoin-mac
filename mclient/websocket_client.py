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
import aiohttp
from typing import Dict, List, Any, Optional
from command_handler import CommandHandler

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class WebSocketClient:
    """WebSocket 클라이언트 클래스"""
    
    def __init__(self, url_or_mode: str, server_id: str, ssl_verify: bool = True, auth_token: Optional[str] = None):
        """WebSocket 클라이언트 초기화
        
        Args:
            url_or_mode: WebSocket URL 또는 연결 모드 (ws, wss, wss_internal, auto, custom)
            server_id: 서버 식별자
            ssl_verify: SSL 인증서 검증 여부
            auth_token: 인증 토큰 (선택사항)
        """
        self.url_or_mode = url_or_mode
        self.server_id = server_id
        self.ssl_verify = ssl_verify
        self.auth_token = auth_token
        self.ws = None
        self.connected = False
        self.reconnect_attempts = 0
        self.last_success_time = 0
        self.sequence_number = 0
        self.reconnecting = False  # 재연결 진행 중 플래그
        self.pending_ack = {}  # {sequence: future} 대기 중인 ACK
        self.max_retry_count = 5
        self.message_queue = []
        self.max_queue_size = 100
        self.ping_interval = 30  # 30초마다 핑
        self.ping_task = None
        self.heartbeat_task = None
        self.command_handler = CommandHandler()  # 명령어 핸들러 추가
        self.receive_task = None  # 메시지 수신 태스크
        
        # 환경 변수에서 직접 서버 호스트 가져오기
        self.server_host = os.environ.get("WS_SERVER_HOST", "localhost")
        ws_port_ws = os.environ.get("WS_PORT_WS", "8080")
        ws_port_wss = os.environ.get("WS_PORT_WSS", "4443")
        
        # WS_SERVER_PORT가 설정된 경우 모드에 따라 적절한 포트 사용
        ws_server_port = os.environ.get("WS_SERVER_PORT")
        ws_mode = os.environ.get("WS_MODE", "auto")
        if ws_server_port:
            if ws_mode == "wss":
                ws_port_wss = ws_server_port
            elif ws_mode == "ws":
                ws_port_ws = ws_server_port
        
        # 기본 URL 설정
        self.base_urls = {
            "ws": f"ws://{self.server_host}:{ws_port_ws}/ws/monitoring/",
            "wss": f"wss://{self.server_host}:{ws_port_wss}/ws/monitoring/",
            "wss_internal": f"wss://{self.server_host}:{ws_port_wss}/ws/monitoring/"
        }
        
        # 설정 정보 로깅
        logger.info(f"WebSocket 클라이언트 초기화: 모드={url_or_mode}, 서버ID={server_id}")
        logger.info(f"WebSocket 호스트: {self.server_host}")
        logger.info(f"WebSocket 기본 URL: ws={self.base_urls['ws']}, wss={self.base_urls['wss']}")
    
    async def try_connect(self, url: str, ssl_context: Optional[ssl.SSLContext] = None) -> bool:
        """특정 URL로 연결 시도"""
        try:
            logger.info(f"WebSocket 연결 시도: {url}")
            
            # 헤더 준비 (토큰이 있는 경우)
            extra_headers = {}
            if self.auth_token:
                extra_headers["Authorization"] = f"Token {self.auth_token}"
                logger.debug(f"인증 토큰 헤더 추가: Token {self.auth_token[:20]}...")
            else:
                logger.warning("인증 토큰이 없습니다. 토큰 없이 연결을 시도합니다.")
            
            # 연결 타임아웃 및 상세 옵션 설정
            if ssl_context:
                self.ws = await websockets.connect(
                    url,
                    ssl=ssl_context,
                    extra_headers=extra_headers,
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
                    extra_headers=extra_headers,
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
                "version": "1.1.0",
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
                    self._start_receive_task()  # 메시지 수신 태스크 시작
                    
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
                
                # 응답은 _receive_messages 태스크에서 처리됨
                # 여기서는 recv()를 호출하지 않음
            
            except Exception as e:
                logger.error(f"큐 메시지 전송 실패: {str(e)}")
                # 실패한 메시지를 다시 큐에 추가
                self.message_queue.insert(0, message)
                self.connected = False
                await self.reconnect()
                break
    
    async def send_stats(self, stats: Dict[str, Any]) -> bool:
        """수집된 통계 데이터 전송"""
        # 재연결 중이면 바로 False 반환
        if self.reconnecting:
            logger.debug("재연결 진행 중... 데이터 전송 건너뜀")
            return False
            
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
            message_json = json.dumps(message)
            
            # 디버그: 전송 데이터 로깅
            if logger.isEnabledFor(logging.DEBUG):
                # 컨테이너 정보만 간단히 표시
                container_names = [c.get('name', 'unknown') for c in stats.get('containers', [])]
                configured = stats.get('configured_nodes', [])
                logger.debug(f"전송 데이터: configured_nodes={configured}, running_containers={container_names}")
            
            # 디버그 파일에 전송 데이터 기록 (mtick 용)
            try:
                with open('/tmp/mclient_last_send.json', 'w') as f:
                    json.dump(message, f, indent=2)
            except Exception as e:
                logger.debug(f"디버그 파일 쓰기 실패: {e}")
            
            await self.ws.send(message_json)
            
            # 전송 자체는 성공으로 간주 (recv 충돌 방지를 위해)
            logger.debug(f"통계 데이터 전송 완료 (시퀀스: {self.sequence_number})")
            self.last_success_time = time.time()
            
            # 나중에 _receive_messages에서 stats_ack를 받으면 로그 출력
            self.pending_ack[self.sequence_number] = True
            
            return True
                
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
        
        # 이미 재연결 중이면 리턴
        if self.reconnecting:
            logger.debug("이미 재연결 진행 중...")
            return False
        
        self.reconnecting = True
        
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
        
        # 지수 백오프: 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024
        max_backoff = 1024  # 최대 1024초 지연
        if self.reconnect_attempts == 1:
            base_delay = 1
        else:
            base_delay = min(max_backoff, 2 ** (self.reconnect_attempts - 1))
        
        # 지터는 제거하여 정확한 지수 백오프 구현
        backoff = base_delay
        
        # 연결 시도 로깅 - 마이크로초 단위의 타임스탬프 포함
        if backoff >= 60:
            minutes = int(backoff // 60)
            seconds = int(backoff % 60)
            time_str = f"{minutes}분 {seconds}초" if seconds > 0 else f"{minutes}분"
        else:
            time_str = f"{int(backoff)}초"
        logger.info(f"WebSocket 재연결 시도 ({self.reconnect_attempts}번째): {time_str} 후 시도 (타임스탬프: {time.time():.6f})")
        await asyncio.sleep(backoff)
        
        # 재연결 시도
        connected = await self.connect()
        
        if connected:
            self.reconnect_attempts = 0
            logger.info(f"WebSocket 재연결 성공 (타임스탬프: {time.time():.6f})")
            
            # 큐에 있는 메시지 전송
            await self._flush_message_queue()
        else:
            # 5분 지났다고 리셋하지 않음 - 계속 백오프 유지
            pass
        
        self.reconnecting = False  # 재연결 플래그 해제
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
        
        # 수신 태스크 중지
        if self.receive_task:
            self.receive_task.cancel()
            self.receive_task = None
        
        # WebSocket 연결 닫기
        if self.ws and not self.ws.closed:
            await self.ws.close()
        
        self.connected = False
        logger.info("WebSocket 연결이 종료되었습니다.")
    
    def _start_receive_task(self):
        """메시지 수신 태스크 시작"""
        if self.receive_task:
            self.receive_task.cancel()
        self.receive_task = asyncio.create_task(self._receive_messages())
        logger.info("메시지 수신 태스크 시작")
    
    async def _receive_messages(self):
        """서버로부터 메시지 수신 및 처리"""
        try:
            while self.connected and self.ws and not self.ws.closed:
                try:
                    message = await asyncio.wait_for(self.ws.recv(), timeout=60)
                    await self._handle_received_message(message)
                except asyncio.TimeoutError:
                    # 타임아웃은 정상 상황
                    continue
                except websockets.exceptions.ConnectionClosed:
                    logger.warning("WebSocket 연결이 닫혔습니다")
                    break
                except Exception as e:
                    logger.error(f"메시지 수신 중 오류: {e}")
                    await asyncio.sleep(1)
        except asyncio.CancelledError:
            logger.info("메시지 수신 태스크 취소됨")
        except Exception as e:
            logger.error(f"수신 태스크 오류: {e}")
    
    async def _handle_received_message(self, message: str):
        """수신된 메시지 처리"""
        try:
            data = json.loads(message)
            msg_type = data.get('type')
            
            logger.debug(f"메시지 수신: {msg_type}")
            
            if msg_type == 'command':
                # 명령어 처리
                await self._handle_command(data.get('data'))
            elif msg_type == 'ping':
                # 핑 응답
                await self.ws.send(json.dumps({'type': 'pong'}))
            elif msg_type == 'stats_ack':
                # 통계 전송 확인
                self._handle_stats_ack(data)
            else:
                logger.debug(f"알 수 없는 메시지 타입: {msg_type}")
                
        except json.JSONDecodeError as e:
            logger.error(f"메시지 파싱 오류: {e}")
        except Exception as e:
            logger.error(f"메시지 처리 오류: {e}")
    
    async def _handle_command(self, command_data: Dict[str, Any]):
        """명령어 처리 및 응답 전송"""
        try:
            logger.info(f"명령어 수신: {command_data.get('command')} on {command_data.get('target')}")
            
            # CommandHandler로 명령 처리
            response = await self.command_handler.handle_command(command_data)
            
            # 응답 전송
            await self.send_message(response)
            
        except Exception as e:
            logger.error(f"명령어 처리 오류: {e}")
            # 오류 응답 전송
            error_response = {
                'type': 'command_response',
                'data': {
                    'command_id': command_data.get('id', 'unknown'),
                    'status': 'failed',
                    'error': str(e),
                    'timestamp': int(time.time())
                }
            }
            await self.send_message(error_response)
    
    def _handle_stats_ack(self, data: Dict[str, Any]):
        """통계 전송 확인 처리"""
        # 다양한 응답 형식 처리
        seq = None
        
        # data.data.sequence 형식
        if 'data' in data and isinstance(data['data'], dict):
            seq = data['data'].get('sequence')
        
        # data.sequence 형식
        if seq is None and 'sequence' in data:
            seq = data.get('sequence')
            
        if seq in self.pending_ack:
            del self.pending_ack[seq]
            logger.debug(f"통계 전송 ACK 수신 확인: 시퀀스 {seq}")
        else:
            logger.debug(f"이미 처리되었거나 알 수 없는 시퀀스: {seq}")
    
    async def send_message(self, message: Dict[str, Any]) -> bool:
        """일반 메시지 전송"""
        if not self.connected or not self.ws or self.ws.closed:
            logger.warning("WebSocket 연결이 없어 메시지를 전송할 수 없습니다")
            return False
        
        try:
            await self.ws.send(json.dumps(message))
            return True
        except Exception as e:
            logger.error(f"메시지 전송 중 오류: {e}")
            return False
    
    async def send_summary(self, summary_data: Dict[str, Any]) -> bool:
        """60회 평균 통계 데이터 전송 (WebSocket + HTTP POST)"""
        # 재연결 중이면 바로 False 반환
        if self.reconnecting:
            logger.debug("재연결 진행 중... Summary 전송 건너뜀")
            return False
            
        if not self.connected or not self.ws:
            logger.warning("WebSocket 연결이 없습니다. Summary 전송 실패")
            return False
        
        ws_success = False
        http_success = False
        
        try:
            # 시퀀스 번호 증가
            self.sequence_number += 1
            
            # Summary 메시지 생성
            message = {
                "type": "summary",
                "serverId": self.server_id,
                "timestamp": int(time.time() * 1000),
                "sequence": self.sequence_number,
                "data": summary_data
            }
            
            # 메시지 전송
            message_json = json.dumps(message)
            
            # 디버그 로깅
            logger.info(f"60회 평균 통계 전송: 기간={summary_data.get('period_seconds')}초, "
                       f"데이터포인트={summary_data.get('data_points')}개")
            
            # 디버그 파일에 Summary 데이터 기록
            try:
                with open('/tmp/mclient_last_summary.json', 'w') as f:
                    json.dump(message, f, indent=2)
            except Exception as e:
                logger.debug(f"Summary 디버그 파일 쓰기 실패: {e}")
            
            # 1. WebSocket으로 전송
            await self.ws.send(message_json)
            ws_success = True
            logger.info(f"60회 평균 통계 WebSocket 전송 완료 (시퀀스: {self.sequence_number})")
            
            # 2. HTTP POST로도 전송 (비동기로 동시 실행)
            http_task = asyncio.create_task(self._send_summary_http(summary_data))
            
            # HTTP 전송 완료 대기 (최대 5초)
            try:
                http_success = await asyncio.wait_for(http_task, timeout=5.0)
            except asyncio.TimeoutError:
                logger.warning("HTTP POST 전송 타임아웃 (5초)")
                http_success = False
            
            return ws_success  # WebSocket 전송이 성공하면 성공으로 간주
                
        except websockets.exceptions.ConnectionClosed as e:
            logger.warning(f"Summary 전송 중 연결 종료: {e}")
            self.connected = False
            await self.reconnect()
            return False
        
        except Exception as e:
            logger.error(f"Summary 전송 중 오류 발생: {str(e)}")
            self.connected = False
            await self.reconnect()
            return False
    
    async def _send_summary_http(self, summary_data: Dict[str, Any]) -> bool:
        """HTTP POST로 summary 데이터 전송"""
        try:
            # HTTP API URL 구성
            # WebSocket URL에서 HTTP URL 유추
            if hasattr(self, 'url_or_mode') and isinstance(self.url_or_mode, str):
                if self.url_or_mode.startswith('wss://'):
                    api_base_url = self.url_or_mode.replace('wss://', 'https://').replace('/ws/monitoring/', '')
                elif self.url_or_mode.startswith('ws://'):
                    api_base_url = self.url_or_mode.replace('ws://', 'http://').replace('/ws/monitoring/', '')
                else:
                    # 기본 URL 사용
                    api_base_url = f"https://{self.server_host}"
            else:
                api_base_url = f"https://{self.server_host}"
            
            api_url = f"{api_base_url}/api/server-logs/save/"
            
            # 인증 헤더 준비
            headers = {}
            if self.auth_token:
                headers["Authorization"] = f"Token {self.auth_token}"
            headers["Content-Type"] = "application/json"
            
            # SSL 설정
            ssl_verify = self.ssl_verify
            connector = None
            if api_url.startswith('https') and not ssl_verify:
                ssl_context = ssl.create_default_context()
                ssl_context.check_hostname = False
                ssl_context.verify_mode = ssl.CERT_NONE
                connector = aiohttp.TCPConnector(ssl=ssl_context)
            
            # HTTP POST 요청
            async with aiohttp.ClientSession(connector=connector) as session:
                # API 형식에 맞게 데이터 변환
                post_data = {
                    "server_id": self.server_id,
                    "timestamp": int(time.time() * 1000),
                    "summary_data": summary_data,
                    "period_seconds": summary_data.get('period_seconds', 60),
                    "data_points": summary_data.get('data_points', 60)
                }
                
                async with session.post(api_url, json=post_data, headers=headers) as response:
                    if response.status == 200:
                        result = await response.json()
                        logger.info(f"60회 평균 통계 HTTP POST 전송 성공: {api_url}")
                        return True
                    else:
                        error_text = await response.text()
                        logger.error(f"HTTP POST 전송 실패 ({response.status}): {error_text}")
                        return False
                        
        except Exception as e:
            logger.error(f"HTTP POST 전송 중 오류: {str(e)}")
            return False
