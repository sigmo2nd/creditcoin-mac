# mserver.py
import asyncio
import websockets
import json
import logging
import time
import random
import ssl
import os
import argparse
from typing import Dict, Set

# 로깅 설정
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(message)s')
logger = logging.getLogger(__name__)

# 연결된 클라이언트 및 관련 정보 저장
connected_clients = {}  # client_id -> websocket
client_info = {}        # client_id -> 클라이언트 정보
data_counters = {}      # client_id -> 받은 데이터 수
last_activity = {}      # client_id -> 마지막 활동 시간

# 서버 전체 통계
server_stats = {
    "total_received": 0,    # 총 수신 메시지 수
    "total_success": 0,     # 성공적으로 처리된 메시지 수
    "start_time": time.time(),  # 서버 시작 시간
    "last_stats_time": time.time()  # 마지막 통계 출력 시간
}

# 활성 연결 상태 확인 간격 (초)
CONNECTION_CHECK_INTERVAL = 60
# 핑 송신 간격 (초)
PING_INTERVAL = 30

async def send_pings():
    """연결된 모든 클라이언트에 정기적인 핑 전송"""
    while True:
        try:
            await asyncio.sleep(PING_INTERVAL)
            current_time = time.time()
            
            for client_id, websocket in list(connected_clients.items()):
                try:
                    if websocket.open:
                        last_activity_time = last_activity.get(client_id, 0)
                        # 마지막 활동이 PING_INTERVAL보다 오래되었으면 핑 전송
                        if current_time - last_activity_time > PING_INTERVAL:
                            logger.debug(f"클라이언트 {client_id}에 핑 전송")
                            pong_waiter = await websocket.ping()
                            try:
                                await asyncio.wait_for(pong_waiter, timeout=5)
                                logger.debug(f"클라이언트 {client_id}로부터 퐁 수신")
                                last_activity[client_id] = current_time
                            except asyncio.TimeoutError:
                                logger.warning(f"클라이언트 {client_id}로부터 퐁 타임아웃")
                                # 연결 종료 준비
                                await handle_client_disconnect(client_id, websocket)
                    else:
                        # 이미 닫힌 웹소켓 정리
                        await handle_client_disconnect(client_id, websocket)
                except Exception as e:
                    logger.error(f"핑 전송 중 오류 발생 ({client_id}): {e}")
                    await handle_client_disconnect(client_id, websocket)
        except Exception as e:
            logger.error(f"핑 루프 중 오류 발생: {e}")

async def check_inactive_clients():
    """장시간 활동이 없는 클라이언트 정리"""
    while True:
        try:
            await asyncio.sleep(CONNECTION_CHECK_INTERVAL)
            current_time = time.time()
            
            for client_id, last_time in list(last_activity.items()):
                if current_time - last_time > CONNECTION_CHECK_INTERVAL * 2:
                    logger.warning(f"장시간 활동 없는 클라이언트 감지: {client_id}, {current_time - last_time:.1f}초 경과")
                    
                    if client_id in connected_clients:
                        websocket = connected_clients[client_id]
                        try:
                            # 핑 전송으로 연결 확인
                            pong_waiter = await websocket.ping()
                            try:
                                await asyncio.wait_for(pong_waiter, timeout=5)
                                logger.info(f"클라이언트 {client_id} 여전히 활성 상태")
                                last_activity[client_id] = current_time
                            except asyncio.TimeoutError:
                                logger.warning(f"클라이언트 {client_id} 응답 없음, 연결 종료")
                                await handle_client_disconnect(client_id, websocket)
                        except Exception as e:
                            logger.error(f"활동 확인 중 오류 발생 ({client_id}): {e}")
                            await handle_client_disconnect(client_id, websocket)
        except Exception as e:
            logger.error(f"비활성 클라이언트 확인 루프 중 오류 발생: {e}")

async def handle_client_disconnect(client_id, websocket):
    """클라이언트 연결 해제 처리"""
    try:
        # 호스트명 정보 가져오기
        host_name = "unknown_host"
        ip = "unknown"
        
        if client_id in client_info:
            host_name = client_info.get(client_id, {}).get("host_name", "unknown_host")
            ip = client_info.get(client_id, {}).get("ip", "unknown")
        
        if client_id in connected_clients:
            del connected_clients[client_id]
        
        if websocket.open:
            await websocket.close()
        
        logger.info(f"{host_name} 연결 해제됨")
    except Exception as e:
        logger.error(f"클라이언트 연결 해제 중 오류 발생: {e}")

async def handle_client(websocket):
    """클라이언트 연결 처리"""
    client_id = None
    host_name = "unknown_host"
    connection_time = time.time()
    
    try:
        client_ip = websocket.remote_address[0] if hasattr(websocket, 'remote_address') and websocket.remote_address else "unknown"
        logger.info(f"클라이언트 연결 됨 (IP: {client_ip})")
        
        # 첫 메시지 대기
        try:
            initial_message = await asyncio.wait_for(websocket.recv(), timeout=10)
            data = json.loads(initial_message)
            message_type = data.get("type")
            
            if message_type == "register":
                client_id = data.get("serverId")
                if not client_id:
                    logger.warning("클라이언트 ID 없음, 임의 ID 생성")
                    client_id = f"unknown-{random.randint(1000, 9999)}"
                
                # 기존 연결 확인 및 처리
                if client_id in connected_clients:
                    old_websocket = connected_clients[client_id]
                    logger.warning(f"동일 ID의 기존 연결 발견: {client_id}, 기존 연결 종료")
                    try:
                        if old_websocket.open:
                            await old_websocket.close()
                    except:
                        pass
                
                # 클라이언트 등록
                connected_clients[client_id] = websocket
                data_counters[client_id] = 0
                last_activity[client_id] = time.time()
                
                # 클라이언트 정보 저장
                client_info[client_id] = {
                    "connected_at": connection_time,
                    "ip": client_ip,
                    "host_name": "unknown_host",  # 초기값, 첫 stats 메시지에서 업데이트됨
                    "user_agent": websocket.request_headers.get("User-Agent", "unknown") if hasattr(websocket, 'request_headers') else "unknown"
                }
                
                # 초기 호스트명 설정 (stats 메시지 전까지 임시 값)
                host_name = client_info[client_id]["host_name"]
                
                logger.info(f"클라이언트 등록됨 (IP: {client_ip})")
                
                # 확인 메시지 전송
                await websocket.send(json.dumps({
                    "type": "register_ack",
                    "status": "success",
                    "serverId": client_id,
                    "timestamp": int(time.time() * 1000),
                    "message": "연결 성공"
                }))
                
            else:
                logger.warning(f"등록되지 않은 클라이언트로부터 메시지 수신: {message_type}")
                await websocket.close()
                return
                
        except asyncio.TimeoutError:
            logger.warning("초기 등록 메시지 타임아웃, 연결 종료")
            await websocket.close()
            return
        except json.JSONDecodeError:
            logger.error("초기 메시지 JSON 파싱 실패, 연결 종료")
            await websocket.close()
            return
        except Exception as e:
            logger.error(f"초기 연결 설정 중 오류 발생: {e}")
            await websocket.close()
            return
        
        # 등록 후 메시지 처리 루프
        async for message in websocket:
            try:
                last_activity[client_id] = time.time()
                
                # JSON 메시지 파싱
                data = json.loads(message)
                message_type = data.get("type")
                
                # 핑 메시지 처리
                if message_type == "ping":
                    await websocket.send(json.dumps({
                        "type": "pong",
                        "timestamp": int(time.time() * 1000)
                    }))
                    continue
                
                # 하트비트 메시지 처리
                elif message_type == "heartbeat":
                    await websocket.send(json.dumps({
                        "type": "heartbeat_ack",
                        "timestamp": int(time.time() * 1000)
                    }))
                    continue
                
                # 통계 데이터 처리
                elif message_type == "stats":
                    # 카운터 증가
                    data_counters[client_id] += 1
                    
                    # 서버 통계 업데이트
                    server_stats["total_received"] += 1
                    server_stats["total_success"] += 1
                    
                    # 메시지 순서 확인 (시퀀스 번호가 있는 경우)
                    if "sequence" in data:
                        seq = data.get("sequence")
                        logger.debug(f"시퀀스 번호 수신: {seq}")
                    
                    # 호스트명 추출
                    system_info = data.get("data", {}).get("system", {})
                    memory_percent = system_info.get("memory_used_percent", 0)
                    
                    # 호스트명 업데이트
                    if "host_name" in system_info:
                        host_name = system_info.get("host_name", "unknown_host")
                        if client_info[client_id].get("host_name") != host_name:
                            client_info[client_id]["host_name"] = host_name
                    
                    # 컨테이너 정보 추출
                    containers = data.get("data", {}).get("containers", [])
                    container_count = len(containers)
                    
                    # 로그 메시지 구성 (호스트명만 표시)
                    log_message = f"{host_name} - {data_counters[client_id]}번 데이터 수신 성공: 메모리 {memory_percent:.1f}%, 컨테이너 {container_count}개"
                    
                    # 10개 단위로 누적 통계 표시
                    if server_stats["total_received"] % 10 == 0:
                        current_time = time.time()
                        elapsed_time = current_time - server_stats["start_time"]
                        elapsed_since_last = current_time - server_stats["last_stats_time"]
                        server_stats["last_stats_time"] = current_time
                        
                        # 서버 통계 계산
                        success_rate = (server_stats["total_success"] / server_stats["total_received"]) * 100 if server_stats["total_received"] > 0 else 0
                        msg_per_minute = (10 / elapsed_since_last) * 60 if elapsed_since_last > 0 else 0
                        
                        # 서버 통계 출력
                        log_message += f"\n=== 서버 누적 통계 (#{server_stats['total_received']}) ===\n"
                        log_message += f"성공률: {success_rate:.1f}%\n"
                        log_message += f"최근 10개 수신 시간: {elapsed_since_last:.1f}초 (분당 {msg_per_minute:.1f}개)\n"
                        log_message += f"연결된 클라이언트: {len(connected_clients)}개\n"
                        log_message += f"총 실행 시간: {elapsed_time / 60:.1f}분"
                        
                        # 연결된 모든 클라이언트 목록 출력
                        log_message += "\n연결된 클라이언트 목록:"
                        for cid, info in client_info.items():
                            if cid in connected_clients:  # 활성 연결만 표시
                                c_host = info.get("host_name", "unknown_host")
                                conn_time = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(info.get("connected_at", 0)))
                                log_message += f"\n - {c_host} - 연결 시간: {conn_time}"
                    
                    logger.info(log_message)
                    
                    # 확인 메시지 전송
                    await websocket.send(json.dumps({
                        "type": "stats_ack",
                        "timestamp": int(time.time() * 1000),
                        "status": "success",
                        "sequence": data.get("sequence")  # 시퀀스 번호 반환
                    }))
                
                # 60회 요약 데이터 처리
                elif message_type == "summary":
                    # 페이아웃 정보 추출
                    payout_info = data.get("data", {}).get("payout_info")
                    if payout_info:
                        payout_checks = payout_info.get("payout_checks", {})
                        total_unclaimed = 0
                        containers_with_payouts = []
                        
                        for container, check_data in payout_checks.items():
                            if "unclaimed_count" in check_data and check_data["unclaimed_count"] > 0:
                                total_unclaimed += check_data["unclaimed_count"]
                                containers_with_payouts.append({
                                    "container": container,
                                    "count": check_data["unclaimed_count"],
                                    "eras": check_data.get("unclaimed_eras", [])[:3]  # 최대 3개만
                                })
                        
                        if total_unclaimed > 0:
                            logger.info(f"{host_name} - 페이아웃 체크: 총 {total_unclaimed}개 미청구 페이아웃")
                            for payout_data in containers_with_payouts:
                                logger.info(f"  - {payout_data['container']}: {payout_data['count']}개 (Era: {payout_data['eras']})")
                    
                    # 확인 메시지 전송
                    await websocket.send(json.dumps({
                        "type": "summary_ack",
                        "timestamp": int(time.time() * 1000),
                        "status": "success"
                    }))
                
                # 알 수 없는 메시지 유형
                else:
                    logger.warning(f"알 수 없는 메시지 유형: {message_type}")
                    
            except json.JSONDecodeError:
                logger.error("잘못된 JSON 형식")
            except Exception as e:
                logger.error(f"메시지 처리 중 오류 발생: {e}")
    
    except websockets.exceptions.ConnectionClosed as e:
        close_code = e.code if hasattr(e, 'code') else "알 수 없음"
        close_reason = e.reason if hasattr(e, 'reason') else "알 수 없음"
        logger.info(f"{host_name} 연결 종료: 코드={close_code}, 이유={close_reason}")
    except Exception as e:
        logger.error(f"클라이언트 처리 중 오류 발생: {e}")
    finally:
        if client_id:
            await handle_client_disconnect(client_id, websocket)

def get_ssl_context(cert_file, key_file):
    """SSL 컨텍스트 생성"""
    if not os.path.exists(cert_file) or not os.path.exists(key_file):
        logger.error(f"인증서 파일 확인 필요: {cert_file}, {key_file}")
        return None
        
    ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    try:
        ssl_context.load_cert_chain(cert_file, key_file)
        logger.info("SSL 인증서 로드 성공")
        return ssl_context
    except Exception as e:
        logger.error(f"SSL 인증서 로드 실패: {e}")
        return None

async def main():
    # 명령줄 인자 파싱
    parser = argparse.ArgumentParser(description='WebSocket 서버 (SSL 지원)')
    parser.add_argument('--host', default='0.0.0.0', help='호스트 주소 (기본값: 0.0.0.0)')
    parser.add_argument('--port', type=int, default=8080, help='포트 번호 (기본값: 8080)')
    parser.add_argument('--ssl', action='store_true', help='SSL 활성화')
    parser.add_argument('--ssl-port', type=int, default=8443, help='SSL 포트 번호 (기본값: 8443)')
    parser.add_argument('--cert', default='./certs/cert.pem', help='인증서 파일 경로 (기본값: ./certs/cert.pem)')
    parser.add_argument('--key', default='./certs/key.pem', help='키 파일 경로 (기본값: ./certs/key.pem)')
    parser.add_argument('--debug', action='store_true', help='디버그 로깅 활성화')
    
    args = parser.parse_args()
    
    # 디버그 로깅 설정
    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)
        logger.info("디버그 모드 활성화됨")
    
    # 정기적인 핑 및 연결 체크 태스크 시작
    ping_task = asyncio.create_task(send_pings())
    check_task = asyncio.create_task(check_inactive_clients())
    
    # WebSocket 서버 시작
    host = args.host
    port = args.port
    
    # 서버 시작 함수
    servers = []
    
    # 일반 WebSocket 서버 시작
    try:
        ws_server = await websockets.serve(
            handle_client,
            host,
            port,
            ping_interval=None,  # 자동 핑 비활성화 (수동으로 제어)
            max_size=10_485_760,  # 10MB
            max_queue=32,
            compression=None,
            close_timeout=5
        )
        servers.append(ws_server)
        logger.info(f"WebSocket 서버 시작: ws://{host}:{port}")
    except Exception as e:
        logger.error(f"WebSocket 서버 시작 실패: {e}")
    
    # SSL WebSocket 서버 시작 (요청 시)
    if args.ssl:
        ssl_context = get_ssl_context(args.cert, args.key)
        if ssl_context:
            try:
                wss_server = await websockets.serve(
                    handle_client,
                    host,
                    args.ssl_port,
                    ssl=ssl_context,
                    ping_interval=None,
                    max_size=10_485_760,
                    max_queue=32,
                    compression=None,
                    close_timeout=5
                )
                servers.append(wss_server)
                logger.info(f"SSL WebSocket 서버 시작: wss://{host}:{args.ssl_port}")
            except Exception as e:
                logger.error(f"SSL WebSocket 서버 시작 실패: {e}")
        else:
            logger.error("SSL 컨텍스트 생성 실패. SSL 서버를 시작할 수 없습니다.")
    
    if not servers:
        logger.error("모든 서버 시작 실패. 프로그램을 종료합니다.")
        ping_task.cancel()
        check_task.cancel()
        return
    
    try:
        # 서버 실행 유지
        await asyncio.Future()
    except asyncio.CancelledError:
        logger.info("서버 종료")
    finally:
        # 정리 작업
        ping_task.cancel()
        check_task.cancel()
        # 연결된 모든 클라이언트 종료
        for client_id, websocket in list(connected_clients.items()):
            try:
                if websocket.open:
                    await websocket.close()
            except:
                pass
        # 모든 서버 닫기
        for server in servers:
            server.close()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("사용자 인터럽트로 서버 종료")
