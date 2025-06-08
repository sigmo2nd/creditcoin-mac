# mserver WebSocket 서버 업데이트 안내

## 새로운 기능 추가 사항

### 1. 클라이언트로 명령 전송 기능

서버에서 연결된 mclient들에게 직접 명령을 전송할 수 있는 기능이 추가되었습니다.

#### 구현해야 할 함수들:

```python
# mserver.py에 추가

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

#### 지원되는 명령어:
- `start` - Docker 컨테이너 시작
- `stop` - Docker 컨테이너 중지  
- `restart` - 컨테이너 재시작
- `logs` - 컨테이너 로그 조회
- `status` - 컨테이너 상태 확인
- `exec` - 컨테이너 내 명령 실행
- `backup_keys` - 노드 키 백업
- `payout` - 지급 스크립트 실행
- `rotate_keys` - 세션 키 교체
- `check_keys` - 세션 키 상태 종합 체크
- `has_session_keys` - 세션 키 존재 확인
- `has_key` - 특정 키 타입 확인

### 2. 명령 응답 처리

`handle_client` 함수의 메시지 처리 부분에 추가:

```python
# 명령 응답 처리
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

### 3. 세션 키 업데이트 처리

rotate_keys 명령 실행 시 새로운 세션 키를 수신하여 저장:

```python
# 키 업데이트 메시지 처리
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
```

### 4. 페이아웃 정보 수신 (이미 구현됨)

60초마다 클라이언트가 전송하는 페이아웃 체크 정보를 수신:

```python
# 60회 요약 데이터 처리 (이미 추가됨)
elif message_type == "summary":
    # 페이아웃 정보 추출 및 로깅
    payout_info = data.get("data", {}).get("payout_info")
    if payout_info:
        # 미청구 페이아웃 정보 처리
```

## 사용 예시

### 대화형 인터페이스 (선택사항)

```python
async def command_interface():
    """대화형 명령 인터페이스"""
    while True:
        try:
            user_input = await asyncio.get_event_loop().run_in_executor(
                None, input, "\n명령 입력 (help, list, send <client_id> <command>): "
            )
            
            parts = user_input.strip().split()
            if not parts:
                continue
                
            cmd = parts[0].lower()
            
            if cmd == "help":
                print("사용 가능한 명령:")
                print("  - start/stop/restart: 컨테이너 제어")
                print("  - logs: 로그 조회")
                print("  - status: 상태 확인")
                print("  - rotate_keys: 세션 키 교체")
                    
            elif cmd == "list":
                print(f"연결된 클라이언트 ({len(connected_clients)}개):")
                for client_id, info in client_info.items():
                    if client_id in connected_clients:
                        host = info.get("host_name", "unknown")
                        print(f"  - {client_id}: {host}")
                        
            elif cmd == "send" and len(parts) >= 3:
                client_id = parts[1]
                command_type = parts[2]
                # 명령 전송
                command_id = await send_command_to_client(client_id, command_type)
                if command_id:
                    print(f"명령 전송 성공: {command_id}")
                    
        except Exception as e:
            print(f"오류: {e}")
```

## 보안 고려사항

1. **인증**: 명령 실행 권한 확인 필요
2. **검증**: 명령 파라미터 검증
3. **로깅**: 모든 명령 실행 기록
4. **제한**: 위험한 명령 차단

## 향후 개선 사항

1. **REST API**: HTTP API로 명령 전송
2. **웹 대시보드**: 관리 UI 구현
3. **스케줄링**: 명령 예약 실행
4. **알림**: 중요 이벤트 알림

## 클라이언트 업데이트 사항

mclient는 이미 다음 기능들이 구현되어 있습니다:
- 명령 수신 및 실행
- 결과 응답 전송
- 세션 키 업데이트 알림
- 1분마다 페이아웃 체크

서버에서는 위의 기능들을 구현하여 클라이언트와 통신할 수 있습니다.