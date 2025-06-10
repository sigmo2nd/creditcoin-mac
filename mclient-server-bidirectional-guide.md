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

## 3. 명령어 상세 설명

### 3.1 지원 명령어 및 파라미터

#### `start` - Docker 컨테이너 시작
```json
{
  "type": "command",
  "data": {
    "id": "cmd_12345",
    "command": "start",
    "target": "3node0",  // 또는 "all"
    "params": {}
  }
}
```
- `target`: 컨테이너 이름 (3node0, node1 등) 또는 "all"
- 결과: 시작된 컨테이너 목록

#### `stop` - Docker 컨테이너 중지
```json
{
  "type": "command",
  "data": {
    "id": "cmd_12346",
    "command": "stop",
    "target": "3node0",  // 또는 "all"
    "params": {}
  }
}
```
- `target`: 컨테이너 이름 또는 "all"
- 결과: 중지된 컨테이너 목록

#### `restart` - 컨테이너 재시작
```json
{
  "type": "command",
  "data": {
    "id": "cmd_12347",
    "command": "restart",
    "target": "3node0",
    "params": {}
  }
}
```
- `target`: 컨테이너 이름
- 결과: 재시작 완료 메시지

#### `logs` - 컨테이너 로그 조회
```json
{
  "type": "command",
  "data": {
    "id": "cmd_12348",
    "command": "logs",
    "target": "3node0",
    "params": {
      "lines": 100,      // 기본값: 50
      "follow": false    // 실시간 로그 (미구현)
    }
  }
}
```
- `target`: 컨테이너 이름
- `params.lines`: 조회할 로그 줄 수
- 결과: 로그 텍스트

#### `status` - 컨테이너 상태 확인
```json
{
  "type": "command",
  "data": {
    "id": "cmd_12349",
    "command": "status",
    "target": "3node0",  // 또는 "all"
    "params": {}
  }
}
```
- `target`: 컨테이너 이름 또는 "all"
- 결과: 컨테이너 상태 테이블

#### `exec` - 컨테이너 내 명령 실행
```json
{
  "type": "command",
  "data": {
    "id": "cmd_12350",
    "command": "exec",
    "target": "3node0",
    "params": {
      "command": "ls -la /root/data"
    }
  }
}
```
- `target`: 컨테이너 이름
- `params.command`: 실행할 명령어
- 결과: 명령 실행 결과

#### `backup_keys` - 노드 키 백업
```json
{
  "type": "command",
  "data": {
    "id": "cmd_12351",
    "command": "backup_keys",
    "target": "3node0",
    "params": {}
  }
}
```
- `target`: 컨테이너 이름
- 동작:
  1. 노드 중지
  2. keystore와 network 디렉토리 tar.gz 백업
  3. 노드 재시작
- 결과: 백업 파일명 (예: "3node0-keys-20250108-1430.tar.gz")

#### `payout` - 지급 스크립트 실행
```json
{
  "type": "command",
  "data": {
    "id": "cmd_12352",
    "command": "payout",
    "target": "3node0",
    "params": {}
  }
}
```
- `target`: 컨테이너 이름
- 결과: 페이아웃 실행 결과 (현재 미구현)

#### `rotate_keys` - 세션 키 교체
```json
{
  "type": "command",
  "data": {
    "id": "cmd_12353",
    "command": "rotate_keys",
    "target": "3node0",
    "params": {}
  }
}
```
- `target`: 컨테이너 이름
- 동작:
  1. RPC로 새 세션 키 생성
  2. 서버로 새 키 전송 (key_update 메시지)
- 결과: 새로운 세션 키

#### `check_keys` - 세션 키 상태 종합 체크
```json
{
  "type": "command",
  "data": {
    "id": "cmd_12354",
    "command": "check_keys",
    "target": "3node0",
    "params": {
      "rotate_to_check": false,  // true면 rotate해서 키 확인 (주의!)
      "public_keys": {           // 선택사항
        "aura": "0x...",
        "gran": "0x..."
      }
    }
  }
}
```
- `target`: 컨테이너 이름
- `params.rotate_to_check`: true면 키를 회전시켜 확인 (기존 키 덮어씀!)
- `params.public_keys`: 각 키 타입별 public key (선택)
- 결과: 세션 키 존재 여부, 각 키 타입별 상태

#### `has_session_keys` - 세션 키 존재 확인
```json
{
  "type": "command",
  "data": {
    "id": "cmd_12355",
    "command": "has_session_keys",
    "target": "3node0",
    "params": {
      "session_keys": ""  // 빈 문자열이면 현재 키 확인
    }
  }
}
```
- `target`: 컨테이너 이름
- `params.session_keys`: 확인할 세션 키 (빈 문자열 = 현재 키)
- 결과: true/false

#### `has_key` - 특정 키 타입 확인
```json
{
  "type": "command",
  "data": {
    "id": "cmd_12356",
    "command": "has_key",
    "target": "3node0",
    "params": {
      "public_key": "0xabc123...",
      "key_type": "aura"  // aura, gran, babe, imon, beefy
    }
  }
}
```
- `target`: 컨테이너 이름
- `params.public_key`: 확인할 public key (필수)
- `params.key_type`: 키 타입 (기본값: aura)
- 결과: true/false

#### `find_validator` - 노드와 연결된 검증인 계정 찾기
```json
{
  "type": "command",
  "data": {
    "id": "cmd_12357",
    "command": "find_validator",
    "target": "3node0",
    "params": {
      "session_keys": "0x...",       // 선택사항
      "deep_search": true            // false면 로그 파싱만 사용
    }
  }
}
```
- `target`: 컨테이너 이름
- `params.session_keys`: 확인할 세션 키 (선택사항)
- `params.deep_search`: true면 체인 스토리지 검색, false면 로그 파싱만
- 동작:
  1. 먼저 노드 로그에서 검증인 정보 찾기 (빠름)
  2. 못 찾으면 체인 스토리지에서 세션 키 매칭 (느림)
  3. 노드 역할(Authority) 확인
- 결과: 
  - `validator_account`: 검증인 계정 주소
  - `session_keys`: 노드의 세션 키
  - `is_authority`: Authority 노드 여부
  - `is_active_validator`: 현재 활성 검증인 여부

### 3.2 명령 응답 형식

성공 응답:
```json
{
  "type": "command_response",
  "data": {
    "command_id": "cmd_12345",
    "status": "completed",
    "result": "3node0 시작됨",
    "timestamp": 1704715200
  }
}
```

실패 응답:
```json
{
  "type": "command_response",
  "data": {
    "command_id": "cmd_12345",
    "status": "failed",
    "error": "컨테이너를 찾을 수 없습니다",
    "timestamp": 1704715200
  }
}
```

## 4. rotate_keys 개선 사항

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

## 6. 키 관리 및 세션 키 이해

### 6.1 세션 키의 특성
- **읽기 불가**: 보안상 세션 키는 생성 시점에만 반환되며 이후 읽을 수 없음
- **RPC 메서드**:
  - `author_rotateKeys`: 새 키 생성 (기존 키 덮어씀)
  - `author_hasSessionKeys`: 키 존재 여부만 확인
  - `author_hasKey`: 특정 키 타입 존재 여부 확인

### 6.2 키 백업과 복원
```bash
# 키스토어 위치
# Creditcoin 3.0: /root/data/chains/creditcoin3/keystore/
# Creditcoin 2.0: /root/data/chains/creditcoin/keystore/

# 백업 프로세스 (노드 중지 필요)
docker stop 3node0
docker run --rm -v 3node0_data:/data:ro -v /backup:/backup alpine \
  tar -czf /backup/3node0-keys-$(date +%Y%m%d).tar.gz \
  -C /data chains/creditcoin3/keystore chains/creditcoin3/network
docker start 3node0

# 복원 프로세스 (노드 중지 필요)
docker stop 3node0
docker run --rm -v 3node0_data:/data -v /backup:/backup alpine \
  tar -xzf /backup/3node0-keys-20250108.tar.gz -C /data
docker start 3node0
```

### 6.3 중요 주의사항
- ⚠️ **동일 키 중복 사용 금지**: 같은 세션 키로 여러 노드 동시 운영 시 슬래싱 위험
- ⚠️ **노드 중지 필수**: 키 파일 조작 시 반드시 노드 중지
- ⚠️ **키 노출 방지**: 세션 키가 노출되면 네트워크 보안 위협

## 7. 페이아웃 체크 기능

### 7.1 자동 페이아웃 체크
- **주기**: 60초마다 (60회 데이터 수집 시)
- **동작**: 동기화된 노드를 통해 네트워크 전체 페이아웃 확인
- **특징**: 누구나 페이아웃 실행 가능 (가스비는 실행자 부담)

### 7.2 페이아웃 정보 메시지
```json
{
  "type": "summary",
  "data": {
    "payout_info": {
      "payout_checks": {
        "3node0": {
          "current_era": 1234,
          "unclaimed_payouts": 5,
          "synced": true
        }
      },
      "timestamp": "2025-01-08T14:30:00.000Z"
    }
  }
}
```

## 8. Era 전환 및 검증인 모니터링

### 8.1 자동 Era 전환 감지
- **동작**: 60초마다 Era 정보 수집 중 변경 감지
- **Era 변경 시**: 모든 노드의 검증인 상태 자동 체크
- **부하**: Era는 6시간마다 변경되므로 매우 가벼움

### 8.2 검증인 상태 알림
Era 전환 시 다음 이벤트가 서버로 전송됩니다:

#### 검증인 활성화
```json
{
  "type": "validator_activated",
  "data": {
    "node": "3node1",
    "era": 1235,
    "validator_account": "5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY",
    "is_authority": true,
    "timestamp": 1704715200000
  }
}
```

#### 검증인 변경
```json
{
  "type": "validator_changed",
  "data": {
    "node": "3node1",
    "era": 1235,
    "validator_account": "5FHneW46xGXgs5mUiveU4sbTyGBzmstUspZC92UhjJM694ty",
    "previous_validator": "5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY",
    "is_authority": true,
    "timestamp": 1704715200000
  }
}
```

#### 검증인 비활성화
```json
{
  "type": "validator_deactivated",
  "data": {
    "node": "3node1",
    "era": 1235,
    "previous_validator": "5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY",
    "timestamp": 1704715200000
  }
}
```

## 8. 보안 고려사항

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