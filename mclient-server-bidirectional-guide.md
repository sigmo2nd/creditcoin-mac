# mclient-server 양방향 통신 구현 가이드

## 개요

mclient와 mserver 간의 WebSocket 양방향 통신 구현 가이드입니다. mclient는 모니터링 데이터를 서버로 전송할 뿐만 아니라, 서버로부터 명령을 받아 실행하고 결과를 반환할 수 있습니다.

## 1. 현재 구현된 기능

### 1.1 mclient (클라이언트) 기능

#### WebSocket 통신 (`websocket_client.py`)
- **양방향 통신 지원**
  - 모니터링 데이터 송신
  - 서버 명령 수신 및 처리
  - 자동 재연결 기능
  - SSL/TLS 지원

- **메시지 타입**
  - `command` - 서버로부터 명령 수신
  - `ping/pong` - 연결 상태 확인
  - `stats_ack` - 통계 수신 확인
  - `summary_ack` - 요약 데이터 수신 확인
  - `error` - 오류 메시지 처리

#### 명령 처리 (`command_handler.py`)
- **지원 명령어**
  - `start` - Docker 컨테이너 시작
  - `stop` - Docker 컨테이너 중지
  - `restart` - 컨테이너 재시작
  - `logs` - 컨테이너 로그 조회
  - `status` - 컨테이너 상태 확인
  - `exec` - 컨테이너 내 명령 실행
  - `backup_keys` - 노드 키 백업
  - `payout` - 지급 스크립트 실행
  - `rotate_keys` - 세션 키 교체

### 1.2 mserver (서버) 현재 상태
- 클라이언트 연결 관리
- 모니터링 데이터 수신
- 연결 상태 확인 (ping/pong)
- **명령 전송 기능은 미구현**

## 2. 서버 측 구현 가이드

### 2.1 명령 전송 기능 추가

```python
# mserver.py에 추가할 함수들

async def send_command_to_client(client_id: str, command_type: str, params: dict = None):
    """특정 클라이언트에 명령 전송"""
    if client_id not in connected_clients:
        logger.error(f"클라이언트 {client_id}가 연결되어 있지 않습니다")
        return False
    
    websocket = connected_clients[client_id]
    command_id = f"cmd_{int(time.time() * 1000)}_{random.randint(1000, 9999)}"
    
    command_message = {
        "type": "command",
        "data": {
            "id": command_id,
            "command": command_type,
            "params": params or {},
            "timestamp": int(time.time() * 1000)
        }
    }
    
    try:
        await websocket.send(json.dumps(command_message))
        logger.info(f"명령 전송 완료: {client_id} - {command_type}")
        return command_id
    except Exception as e:
        logger.error(f"명령 전송 실패: {e}")
        return False

async def broadcast_command(command_type: str, params: dict = None):
    """모든 연결된 클라이언트에 명령 전송"""
    results = {}
    for client_id in list(connected_clients.keys()):
        command_id = await send_command_to_client(client_id, command_type, params)
        if command_id:
            results[client_id] = command_id
    return results
```

### 2.2 명령 응답 처리

```python
# handle_client 함수의 메시지 처리 부분에 추가

elif message_type == "command_response":
    response_data = data.get("data", {})
    command_id = response_data.get("id")
    status = response_data.get("status")
    result = response_data.get("result")
    
    logger.info(f"{host_name} - 명령 응답: ID={command_id}, 상태={status}")
    if status == "failed":
        logger.error(f"명령 실패: {response_data.get('error')}")
    else:
        logger.info(f"명령 결과: {result}")
    
    # 응답 확인 메시지
    await websocket.send(json.dumps({
        "type": "command_ack",
        "timestamp": int(time.time() * 1000),
        "command_id": command_id
    }))
```

### 2.3 대화형 인터페이스

```python
async def command_interface():
    """대화형 명령 인터페이스"""
    while True:
        try:
            # 입력 대기
            user_input = await asyncio.get_event_loop().run_in_executor(
                None, input, "\n명령 입력 (help, list, send <client_id> <command>): "
            )
            
            parts = user_input.strip().split()
            if not parts:
                continue
                
            cmd = parts[0].lower()
            
            if cmd == "help":
                print("사용 가능한 명령:")
                for cmd_name, info in SUPPORTED_COMMANDS.items():
                    print(f"  - {cmd_name}: {info['description']}")
                    
            elif cmd == "list":
                print(f"연결된 클라이언트 ({len(connected_clients)}개):")
                for client_id, info in client_info.items():
                    if client_id in connected_clients:
                        host = info.get("host_name", "unknown")
                        print(f"  - {client_id}: {host}")
                        
            elif cmd == "send" and len(parts) >= 3:
                client_id = parts[1]
                command_type = parts[2]
                params = {}
                
                # 추가 파라미터 파싱
                if command_type == "logs" and len(parts) > 3:
                    params["lines"] = int(parts[3]) if parts[3].isdigit() else 100
                elif command_type == "exec" and len(parts) > 3:
                    params["command"] = " ".join(parts[3:])
                
                # 명령 전송
                command_id = await send_command_to_client(client_id, command_type, params)
                if command_id:
                    print(f"명령 전송 성공: {command_id}")
                else:
                    print("명령 전송 실패")
                    
            elif cmd == "broadcast" and len(parts) >= 2:
                command_type = parts[1]
                results = await broadcast_command(command_type)
                print(f"브로드캐스트 완료: {len(results)}개 클라이언트")
                
        except Exception as e:
            print(f"오류: {e}")
```

## 3. rotate_keys 개선 사항

### 3.1 문제점
- 기존 rotate_keys는 새로운 세션 키를 생성하지만 서버에 전달하지 않음
- 키 회전 시 이전 키는 자동으로 삭제됨

### 3.2 개선된 구현

#### command_handler.py 수정
```python
async def _rotate_keys(self, container: str, websocket_client=None) -> str:
    """세션 키 회전 및 서버 전송"""
    # RPC 호출로 키 회전
    rpc_command = {
        "jsonrpc": "2.0",
        "method": "author_rotateKeys",
        "params": [],
        "id": 1
    }
    
    # 컨테이너 타입에 따른 RPC 포트 결정
    if container.startswith('3node'):
        port = 33980 + int(container.replace('3node', ''))
    else:
        port = 33880 + int(container.replace('node', ''))
    
    cmd = [
        'docker', 'exec', container,
        'curl', '-s', '-H', 'Content-Type: application/json',
        '-d', json.dumps(rpc_command),
        f'http://localhost:{port}/'
    ]
    
    output = await self._run_command(cmd)
    result = json.loads(output)
    
    if 'result' in result:
        new_session_key = result['result']
        
        # 서버로 새 키 전송
        if websocket_client:
            key_update_message = {
                "type": "key_update",
                "data": {
                    "container": container,
                    "session_key": new_session_key,
                    "timestamp": int(datetime.now().timestamp() * 1000),
                    "action": "rotate_keys"
                }
            }
            
            try:
                await websocket_client.send_message(json.dumps(key_update_message))
                logger.info(f"새 세션 키를 서버로 전송 완료: {container}")
            except Exception as e:
                logger.error(f"세션 키 서버 전송 실패: {e}")
        
        return {
            "status": "success",
            "message": f"새 세션 키 생성 및 서버 전송 완료",
            "session_key": new_session_key,
            "container": container
        }
    else:
        raise Exception(f"키 회전 실패: {result.get('error', 'Unknown error')}")
```

#### 서버 측 키 저장 기능
```python
# mserver.py에 추가

elif message_type == "key_update":
    key_data = data.get("data", {})
    container = key_data.get("container")
    session_key = key_data.get("session_key")
    action = key_data.get("action")
    
    logger.info(f"{host_name} - 키 업데이트: {container}")
    logger.info(f"  액션: {action}")
    logger.info(f"  새 세션 키: {session_key}")
    
    # 키 저장 (파일 또는 데이터베이스에)
    await save_session_key(client_id, container, session_key)
    
    # 확인 메시지 전송
    await websocket.send(json.dumps({
        "type": "key_update_ack",
        "status": "success",
        "timestamp": int(time.time() * 1000),
        "message": "세션 키 업데이트 완료"
    }))

async def save_session_key(client_id: str, container: str, session_key: str):
    """세션 키를 파일에 저장"""
    import os
    import json
    from datetime import datetime
    
    # 키 저장 디렉토리
    key_dir = "./session_keys"
    os.makedirs(key_dir, exist_ok=True)
    
    # 파일명: client_id_container_timestamp.json
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"{key_dir}/{client_id}_{container}_{timestamp}.json"
    
    key_data = {
        "client_id": client_id,
        "container": container,
        "session_key": session_key,
        "timestamp": timestamp,
        "created_at": datetime.now().isoformat()
    }
    
    with open(filename, 'w') as f:
        json.dump(key_data, f, indent=2)
    
    # 최신 키 링크 업데이트
    latest_link = f"{key_dir}/{client_id}_{container}_latest.json"
    if os.path.exists(latest_link):
        os.remove(latest_link)
    os.symlink(os.path.basename(filename), latest_link)
    
    logger.info(f"세션 키 저장 완료: {filename}")
```

## 4. 추가 개선 사항

### 4.1 정기적인 키 회전
```python
async def scheduled_key_rotation(websocket_client, interval_hours=24):
    """정기적인 키 회전"""
    while True:
        try:
            await asyncio.sleep(interval_hours * 3600)
            
            # 모든 노드 컨테이너 찾기
            containers = await get_node_containers()
            
            for container in containers:
                try:
                    logger.info(f"정기 키 회전 시작: {container}")
                    command_data = {
                        "id": f"scheduled_{int(time.time())}",
                        "command": "rotate_keys",
                        "target": container
                    }
                    
                    handler = CommandHandler()
                    result = await handler.handle_command(command_data, websocket_client)
                    logger.info(f"정기 키 회전 완료: {container}")
                    
                except Exception as e:
                    logger.error(f"정기 키 회전 실패 ({container}): {e}")
                    
        except Exception as e:
            logger.error(f"키 회전 스케줄러 오류: {e}")
```

### 4.2 키 백업 시 서버 알림
```python
async def _backup_keys(self, container: str, websocket_client=None) -> str:
    # ... 기존 백업 코드 ...
    
    # 백업 완료 후 서버에 알림
    if websocket_client and backup_file:
        backup_notification = {
            "type": "backup_complete",
            "data": {
                "container": container,
                "backup_file": backup_file,
                "timestamp": int(datetime.now().timestamp() * 1000)
            }
        }
        
        try:
            await websocket_client.send_message(json.dumps(backup_notification))
        except Exception as e:
            logger.error(f"백업 알림 전송 실패: {e}")
    
    return f"키 백업 완료: {backup_file}"
```

## 5. 사용 예시

### 서버 실행
```bash
# SSL 지원 서버 실행
python mserver.py --ssl

# 일반 서버 실행
python mserver.py --port 8080
```

### 명령 전송
```bash
# 대화형 모드에서
list                    # 연결된 클라이언트 목록
send client123 restart  # 특정 클라이언트에 재시작 명령
send client123 logs 100 # 로그 100줄 조회
broadcast status        # 모든 클라이언트 상태 확인
```

## 6. 보안 고려사항

1. **인증**: 토큰 기반 인증 구현
2. **암호화**: SSL/TLS 사용
3. **권한 관리**: 명령별 권한 체크
4. **로깅**: 모든 명령 실행 기록 저장
5. **검증**: 입력 파라미터 검증

## 7. 향후 개선 계획

1. **웹 대시보드**: 명령 전송을 위한 웹 인터페이스
2. **스케줄링**: 명령 예약 실행 기능
3. **모니터링**: 명령 실행 상태 실시간 추적
4. **알림**: 중요 이벤트 알림 기능
5. **백업 자동화**: 정기적인 키 백업 및 관리