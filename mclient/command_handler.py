# command_handler.py
import asyncio
import subprocess
import json
import logging
import uuid
from typing import Dict, Any, Optional
from datetime import datetime

logger = logging.getLogger(__name__)

class CommandHandler:
    """웹소켓으로 받은 명령어를 처리하는 핸들러"""
    
    def __init__(self):
        self.running_commands = {}  # 실행 중인 명령어 추적
        
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