# command_handler.py
import asyncio
import subprocess
import json
import logging
import uuid
from typing import Dict, Any, Optional
from datetime import datetime
from substrate_utils import extract_validator_from_storage_key

logger = logging.getLogger(__name__)

class CommandHandler:
    """웹소켓으로 받은 명령어를 처리하는 핸들러"""
    
    def __init__(self, era_monitor=None):
        self.running_commands = {}  # 실행 중인 명령어 추적
        self.era_monitor = era_monitor
        
    async def handle_command(self, command_data: Dict[str, Any]) -> Dict[str, Any]:
        """명령어 실행 및 응답 생성"""
        command_id = command_data.get('id', str(uuid.uuid4()))
        command_type = command_data.get('command')
        target = command_data.get('target')
        params = command_data.get('params', {})
        
        logger.info(f"명령어 수신: {command_type} on {target} (ID: {command_id})")
        
        # 응답 템플릿
        response = {
            'type': 'command_response',
            'data': {
                'command_id': command_id,
                'status': 'in_progress',
                'result': None,
                'error': None,
                'timestamp': int(datetime.now().timestamp())
            }
        }
        
        try:
            # Docker 명령어 처리
            if command_type == 'start':
                result = await self._docker_start(target)
            elif command_type == 'stop':
                result = await self._docker_stop(target)
            elif command_type == 'restart':
                result = await self._docker_restart(target)
            elif command_type == 'logs':
                result = await self._docker_logs(target, params)
            elif command_type == 'status':
                result = await self._docker_status(target)
            elif command_type == 'exec':
                result = await self._docker_exec(target, params)
            elif command_type == 'backup_keys':
                result = await self._backup_keys(target)
            elif command_type == 'payout':
                result = await self._run_payout(target)
            elif command_type == 'rotate_keys':
                result = await self._rotate_keys(target)
            elif command_type == 'check_keys':
                result = await self._check_keys(target, params)
            elif command_type == 'has_session_keys':
                result = await self._has_session_keys(target, params)
            elif command_type == 'has_key':
                result = await self._has_key(target, params)
            elif command_type == 'find_validator':
                # 먼저 간단한 방법 시도
                simple_result = await self._find_validator_simple(target, params)
                if simple_result.get("validator_account") or not params.get("deep_search", True):
                    result = simple_result
                else:
                    # 깊은 검색 수행
                    result = await self._find_validator_account(target, params)
            else:
                raise ValueError(f"지원되지 않는 명령어: {command_type}")
            
            response['data']['status'] = 'completed'
            response['data']['result'] = result
            
        except Exception as e:
            logger.error(f"명령어 실행 실패: {e}")
            response['data']['status'] = 'failed'
            response['data']['error'] = str(e)
        
        return response
    
    async def _run_command(self, cmd: list) -> str:
        """비동기 명령어 실행"""
        try:
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await process.communicate()
            
            if process.returncode != 0:
                raise subprocess.CalledProcessError(
                    process.returncode, cmd, stdout, stderr
                )
            
            return stdout.decode('utf-8').strip()
        except Exception as e:
            logger.error(f"명령어 실행 오류: {' '.join(cmd)} - {e}")
            raise
    
    async def _docker_start(self, container: str) -> str:
        """Docker 컨테이너 시작"""
        if container == 'all':
            # 모든 노드 시작
            containers = await self._get_node_containers()
            results = []
            for c in containers:
                try:
                    result = await self._run_command(['docker', 'start', c])
                    results.append(f"{c}: 시작됨")
                except Exception as e:
                    results.append(f"{c}: 시작 실패 - {e}")
            return '\n'.join(results)
        else:
            await self._run_command(['docker', 'start', container])
            return f"{container} 시작됨"
    
    async def _docker_stop(self, container: str) -> str:
        """Docker 컨테이너 중지"""
        if container == 'all':
            containers = await self._get_node_containers()
            results = []
            for c in containers:
                try:
                    result = await self._run_command(['docker', 'stop', c])
                    results.append(f"{c}: 중지됨")
                except Exception as e:
                    results.append(f"{c}: 중지 실패 - {e}")
            return '\n'.join(results)
        else:
            await self._run_command(['docker', 'stop', container])
            return f"{container} 중지됨"
    
    async def _docker_restart(self, container: str) -> str:
        """Docker 컨테이너 재시작"""
        await self._run_command(['docker', 'restart', container])
        return f"{container} 재시작됨"
    
    async def _docker_logs(self, container: str, params: Dict) -> str:
        """Docker 로그 조회"""
        lines = params.get('lines', 50)
        follow = params.get('follow', False)
        
        cmd = ['docker', 'logs', container, '--tail', str(lines)]
        if follow:
            # 실시간 로그는 별도 처리 필요
            return "실시간 로그 스트리밍은 아직 구현되지 않았습니다"
        
        output = await self._run_command(cmd)
        return output
    
    async def _docker_status(self, container: str) -> str:
        """Docker 컨테이너 상태 확인"""
        if container == 'all':
            output = await self._run_command(['docker', 'ps', '--format', 'table {{.Names}}\t{{.Status}}'])
        else:
            output = await self._run_command(['docker', 'ps', '--filter', f'name={container}', '--format', 'table {{.Names}}\t{{.Status}}'])
        return output
    
    async def _docker_exec(self, container: str, params: Dict) -> str:
        """Docker exec 명령 실행"""
        command = params.get('command')
        if not command:
            raise ValueError("실행할 명령어가 지정되지 않았습니다")
        
        cmd = ['docker', 'exec', container] + command.split()
        output = await self._run_command(cmd)
        return output
    
    async def _backup_keys(self, container: str) -> str:
        """키 백업 실행 - utils.sh의 backupkeys 함수 사용"""
        # mclient는 Docker 내부에서 실행되므로 호스트 스크립트 직접 실행 불가
        # Docker 명령어로 직접 구현
        
        # 1. 컨테이너 실행 중인지 확인
        try:
            status = await self._run_command(['docker', 'inspect', '-f', '{{.State.Running}}', container])
            was_running = status.strip() == 'true'
            
            # 2. 실행 중이면 중지
            if was_running:
                logger.info(f"{container} 중지 중...")
                await self._run_command(['docker', 'stop', container])
            
            # 3. 백업 날짜 생성
            from datetime import datetime
            backup_date = datetime.now().strftime('%Y%m%d-%H%M')
            backup_file = f"{container}-keys-{backup_date}.tar.gz"
            
            # 4. 노드 타입 확인
            if container.startswith('3node'):
                chain_dir = 'creditcoin3'
            elif container.startswith('node'):
                chain_dir = 'creditcoin'
            else:
                raise ValueError(f"지원되지 않는 노드 형식: {container}")
            
            # 5. 백업할 디렉토리 경로
            keystore_dir = f"/root/data/chains/{chain_dir}/keystore"
            network_dir = f"/root/data/chains/{chain_dir}/network"
            
            # 6. tar 명령으로 백업 (컨테이너 내부에서)
            tar_cmd = [
                'docker', 'run', '--rm',
                '-v', f'{container}_data:/data:ro',  # 볼륨 마운트 (읽기 전용)
                '-v', f'/Users/sieg/creditcoin-docker:/backup',  # 백업 저장 위치
                'alpine', 'tar', '-czf', f'/backup/{backup_file}',
                '-C', '/data', f'chains/{chain_dir}/keystore', f'chains/{chain_dir}/network'
            ]
            
            await self._run_command(tar_cmd)
            
            # 7. 노드 재시작
            if was_running:
                logger.info(f"{container} 재시작 중...")
                await self._run_command(['docker', 'start', container])
            
            return f"키 백업 완료: {backup_file}"
            
        except Exception as e:
            # 오류 발생 시 노드 재시작 시도
            try:
                await self._run_command(['docker', 'start', container])
            except:
                pass
            raise Exception(f"키 백업 실패: {str(e)}")
    
    async def _run_payout(self, container: str) -> str:
        """페이아웃 실행"""
        # 페이아웃 스크립트가 컨테이너 내부에 있다고 가정
        cmd = ['docker', 'exec', container, '/path/to/payout.sh']
        output = await self._run_command(cmd)
        return f"페이아웃 실행 완료: {output}"
    
    async def _rotate_keys(self, container: str) -> str:
        """세션 키 회전"""
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
            return f"새 세션 키: {result['result']}"
        else:
            raise Exception(f"키 회전 실패: {result.get('error', 'Unknown error')}")
    
    async def _get_node_containers(self) -> list:
        """실행 중인 노드 컨테이너 목록 가져오기"""
        output = await self._run_command([
            'docker', 'ps', '--filter', 'name=node', 
            '--filter', 'name=3node', '--format', '{{.Names}}'
        ])
        containers = output.strip().split('\n') if output else []
        # mclient, mserver 등 제외
        return [c for c in containers if c and ('node' in c) and ('mclient' not in c)]
    
    async def _check_keys(self, container: str, params: Dict) -> Dict:
        """세션 키 전체 상태 체크"""
        result = {
            "container": container,
            "has_session_keys": False,
            "key_types": {},
            "session_keys_hex": None
        }
        
        try:
            # 세션 키 존재 여부 확인
            has_keys = await self._has_session_keys(container, {})
            result["has_session_keys"] = has_keys.get("has_keys", False)
            
            # rotateKeys는 절대 사용하지 않음 - 키가 바뀌면 검증인 자격 상실
            # 세션 키 확인이 필요한 경우 다른 방법 사용
            # 각 키 타입 존재 여부 (public key가 있을 때만)
            if params.get("public_keys"):
                for key_type in ['aura', 'gran', 'babe', 'imon', 'beefy']:
                    public_key = params["public_keys"].get(key_type)
                    if public_key:
                        has_key_result = await self._has_key(container, {
                            "public_key": public_key,
                            "key_type": key_type
                        })
                        result["key_types"][key_type] = has_key_result.get("has_key", False)
            
            return result
            
        except Exception as e:
            return {"error": str(e), "container": container}
    
    async def _has_session_keys(self, container: str, params: Dict) -> Dict:
        """hasSessionKeys RPC 호출"""
        try:
            # 포트 결정
            if container.startswith('3node'):
                port = 33980 + int(container.replace('3node', ''))
            else:
                port = 33880 + int(container.replace('node', ''))
            
            # 세션 키 파라미터 (빈 문자열이면 현재 키 확인)
            session_keys = params.get("session_keys", "")
            
            cmd = [
                'docker', 'exec', container,
                'curl', '-s', '-H', 'Content-Type: application/json',
                '-d', json.dumps({
                    "jsonrpc": "2.0",
                    "method": "author_hasSessionKeys",
                    "params": [session_keys],
                    "id": 1
                }),
                f'http://localhost:{port}/'
            ]
            
            output = await self._run_command(cmd)
            response = json.loads(output)
            
            return {
                "has_keys": response.get("result", False),
                "container": container,
                "checked_keys": session_keys if session_keys else "current"
            }
            
        except Exception as e:
            return {"error": str(e), "has_keys": False}
    
    async def _has_key(self, container: str, params: Dict) -> Dict:
        """hasKey RPC 호출 - 특정 키 타입 확인"""
        try:
            # 필수 파라미터 확인
            public_key = params.get("public_key")
            key_type = params.get("key_type", "aura")
            
            if not public_key:
                return {"error": "public_key 파라미터가 필요합니다"}
            
            # 포트 결정
            if container.startswith('3node'):
                port = 33980 + int(container.replace('3node', ''))
            else:
                port = 33880 + int(container.replace('node', ''))
            
            cmd = [
                'docker', 'exec', container,
                'curl', '-s', '-H', 'Content-Type: application/json',
                '-d', json.dumps({
                    "jsonrpc": "2.0",
                    "method": "author_hasKey",
                    "params": [public_key, key_type],
                    "id": 1
                }),
                f'http://localhost:{port}/'
            ]
            
            output = await self._run_command(cmd)
            response = json.loads(output)
            
            return {
                "has_key": response.get("result", False),
                "container": container,
                "key_type": key_type,
                "public_key": public_key[:16] + "..." if len(public_key) > 20 else public_key
            }
            
        except Exception as e:
            return {"error": str(e), "has_key": False}
    
    async def _find_validator_account(self, container: str, params: Dict) -> Dict:
        """노드와 연결된 검증인 계정 찾기"""
        try:
            # 포트 결정
            if container.startswith('3node'):
                port = 33980 + int(container.replace('3node', ''))
            else:
                port = 33880 + int(container.replace('node', ''))
            
            # 1. 세션 키 파라미터 확인
            session_keys = params.get("session_keys")
            
            if not session_keys:
                # 세션 키가 제공되지 않은 경우, 체인에서 검색은 불가능
                return {
                    "error": "세션 키가 제공되지 않았습니다. 체인 스토리지 검색을 위해서는 세션 키가 필요합니다.",
                    "container": container,
                    "suggestion": "세션 키를 제공하거나, deep_search: false로 로그 검색을 사용하세요."
                }
            
            # 2. 현재 활성 검증인 목록 가져오기
            validators_cmd = [
                'docker', 'exec', container,
                'curl', '-s', '-H', 'Content-Type: application/json',
                '-d', json.dumps({
                    "jsonrpc": "2.0",
                    "method": "state_getStorage",
                    "params": ["0x5f3e4907f716ac89b6347d15ececedca9c6a637f62ae2af1c7e31eed7e96be04"],  # staking.validators
                    "id": 1
                }),
                f'http://localhost:{port}/'
            ]
            
            validators_output = await self._run_command(validators_cmd)
            validators_response = json.loads(validators_output)
            
            if 'error' in validators_response:
                # 대체 방법: RPC 메타데이터 사용
                validators_cmd = [
                    'docker', 'exec', container,
                    'curl', '-s', '-H', 'Content-Type: application/json',
                    '-d', json.dumps({
                        "jsonrpc": "2.0",
                        "method": "state_call",
                        "params": ["StakingApi_validators", "0x"],
                        "id": 1
                    }),
                    f'http://localhost:{port}/'
                ]
                validators_output = await self._run_command(validators_cmd)
                validators_response = json.loads(validators_output)
            
            # 3. 각 검증인의 세션 키 확인
            matched_validator = None
            validators_checked = 0
            session_keys_found = []
            
            if 'result' in validators_response and validators_response['result']:
                # 검증인 목록 디코딩 (hex -> addresses)
                validators_hex = validators_response['result']
                
                # 세션 키 정규화 (0x 제거)
                target_session_keys = session_keys.replace('0x', '').lower()
                
                # 각 검증인의 nextKeys 확인
                # Session.nextKeys storage key = twox_128("Session") + twox_128("NextKeys") + blake2_128_concat(validator)
                session_prefix = "0x2099d7f109d6e535fb000bba623fd4409f99a2ce711f3a31b2fc05604c93f179"
                
                # 페이지네이션으로 모든 키 가져오기
                all_keys_cmd = [
                    'docker', 'exec', container,
                    'curl', '-s', '-H', 'Content-Type: application/json',
                    '-d', json.dumps({
                        "jsonrpc": "2.0",
                        "method": "state_getPairs",
                        "params": [session_prefix],
                        "id": 1
                    }),
                    f'http://localhost:{port}/'
                ]
                
                all_keys_output = await self._run_command(all_keys_cmd)
                all_keys_response = json.loads(all_keys_output)
                
                if 'result' in all_keys_response:
                    for key_value_pair in all_keys_response['result']:
                        storage_key = key_value_pair[0]
                        storage_value = key_value_pair[1]
                        
                        # 스토리지 값에서 세션 키 추출 (hex 형식)
                        stored_session_keys = storage_value.replace('0x', '').lower()
                        
                        # 매칭 확인
                        if target_session_keys in stored_session_keys or stored_session_keys in target_session_keys:
                            # 스토리지 키에서 검증인 주소 추출
                            # 키 구조: prefix(64) + blake2_128_concat_hash(32) + validator_address(64)
                            validator_hex = storage_key[96:]  # prefix와 hash 제거
                            
                            # SS58 주소로 변환 (간단한 예시, 실제로는 더 복잡)
                            matched_validator = f"0x{validator_hex}"
                            break
                        
                        validators_checked += 1
                        session_keys_found.append(stored_session_keys[:16] + "...")
            
            # 4. 결과 반환
            result = {
                "container": container,
                "session_keys": session_keys[:32] + "..." if len(session_keys) > 36 else session_keys,
                "validator_account": matched_validator,
                "validators_checked": validators_checked,
                "session_keys_found": session_keys_found[:5]  # 처음 5개만
            }
            
            if matched_validator:
                result["status"] = "success"
                result["message"] = f"노드가 검증인 계정 {matched_validator[:16]}...와 연결되어 있습니다"
            else:
                result["status"] = "not_found"
                result["message"] = "매칭되는 검증인 계정을 찾을 수 없습니다"
            
            return result
            
        except Exception as e:
            return {"error": str(e), "container": container}
    
    async def _find_validator_simple(self, container: str, params: Dict) -> Dict:
        """간단한 방법으로 검증인 찾기 - 로그에서 추출"""
        try:
            # 포트 결정
            if container.startswith('3node'):
                port = 33980 + int(container.replace('3node', ''))
            else:
                port = 33880 + int(container.replace('node', ''))
            
            # 1. 노드 로그에서 검증인 정보 찾기
            log_cmd = ['docker', 'logs', container, '--tail', '1000']
            logs = await self._run_command(log_cmd)
            
            validator_info = {
                "container": container,
                "method": "log_parsing",
                "validator_account": None,
                "session_keys": None
            }
            
            # 로그에서 패턴 찾기
            import re
            
            # 검증인 활동 패턴 찾기
            # 1. 블록 생성 패턴
            block_production_patterns = [
                r'🎁\s*Prepared block for proposing',
                r'Starting consensus session on top of parent',
                r'Pre-sealed block for proposal',
                r'👶\s*New epoch',
                r'🙌\s*Starting consensus session'
            ]
            
            for pattern in block_production_patterns:
                if re.search(pattern, logs):
                    validator_info["is_producing_blocks"] = True
                    logger.info(f"{container}: 블록 생성 활동 감지")
                    break
            
            # 2. 기존 패턴도 확인
            validator_pattern = r'validator.*account.*([15][a-zA-Z0-9]{47})'
            session_key_pattern = r'Session keys.*0x([a-fA-F0-9]+)'
            
            validator_match = re.search(validator_pattern, logs, re.IGNORECASE)
            if validator_match:
                validator_info["validator_account"] = validator_match.group(1)
            
            session_match = re.search(session_key_pattern, logs, re.IGNORECASE)
            if session_match:
                validator_info["session_keys"] = "0x" + session_match.group(1)
            
            # 3. hasSessionKeys로 세션키 확인 (가장 간단한 방법)
            try:
                has_keys_cmd = [
                    'docker', 'exec', container,
                    'curl', '-s', '-H', 'Content-Type: application/json',
                    '-d', json.dumps({
                        "jsonrpc": "2.0",
                        "method": "author_hasSessionKeys",
                        "params": [""],  # 빈 문자열 = 현재 키 확인
                        "id": 1
                    }),
                    f'http://localhost:{port}/'
                ]
                
                has_keys_output = await self._run_command(has_keys_cmd)
                has_keys_response = json.loads(has_keys_output)
                
                if has_keys_response.get('result', False):
                    validator_info["has_session_keys"] = True
                    # 세션 키가 있고 블록 생성 패턴이 보이면 검증인
                    if validator_info.get("is_producing_blocks", False):
                        validator_info["validator_account"] = "ACTIVE_VALIDATOR"
                        validator_info["is_authority"] = True
                        logger.info(f"{container}: 활성 검증인으로 확인됨!")
            except Exception as e:
                logger.error(f"세션 키 확인 중 오류: {e}")
            
            # 3. 현재 세션에서 활성 검증인인지 확인
            if validator_info["validator_account"]:
                # 현재 검증인 세트 확인
                current_validators_cmd = [
                    'docker', 'exec', container,
                    'curl', '-s', '-H', 'Content-Type: application/json',
                    '-d', json.dumps({
                        "jsonrpc": "2.0",
                        "method": "state_call",
                        "params": ["SessionApi_validators", "0x"],
                        "id": 1
                    }),
                    f'http://localhost:{port}/'
                ]
                
                validators_output = await self._run_command(current_validators_cmd)
                validators_response = json.loads(validators_output)
                
                if 'result' in validators_response:
                    # 결과에 검증인 주소가 포함되어 있는지 확인
                    validator_info["is_active_validator"] = validator_info["validator_account"] in validators_response.get('result', '')
            
            return validator_info
            
        except Exception as e:
            return {"error": str(e), "container": container, "method": "simple"}
    
