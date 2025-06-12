# payout_checker.py
import asyncio
import json
import logging
from typing import Dict, List, Any, Optional
from datetime import datetime

logger = logging.getLogger(__name__)

class PayoutChecker:
    """페이아웃 체크 기능 - 누구나 실행 가능한 페이아웃 확인"""
    
    def __init__(self):
        self.payout_cache = {}
        self.last_check_time = {}
        
    async def check_container_payout(self, container_name: str) -> Dict[str, Any]:
        """노드를 통해 네트워크의 미청구 페이아웃 확인"""
        try:
            # 포트 결정
            if container_name.startswith('3node'):
                port = 33980 + int(container_name.replace('3node', ''))
            elif container_name.startswith('node'):
                port = 33970 + int(container_name.replace('node', ''))
            else:
                return {"error": f"Unknown container type: {container_name}"}
            
            # 1. 노드 동기화 상태 확인
            sync_status = await self._check_sync_status(container_name, port)
            if not sync_status.get('synced'):
                return {
                    "container": container_name,
                    "error": "Node not synced",
                    "sync_status": sync_status
                }
            
            # 2. 현재 era 가져오기
            current_era = await self._get_current_era(container_name, port)
            if current_era is None:
                return {
                    "container": container_name,
                    "error": "Failed to get current era"
                }
            
            # 3. 전체 검증인의 미청구 페이아웃 확인
            # 실제로는 특정 검증인 리스트가 있다면 그것만 체크하는 것이 효율적
            payout_info = await self._check_unclaimed_payouts(container_name, port, current_era)
            
            result = {
                "container": container_name,
                "current_era": current_era,
                "unclaimed_payouts": payout_info.get('unclaimed_count', 0),
                "sample_validators": payout_info.get('sample_validators', []),
                "timestamp": datetime.now().isoformat(),
                "synced": True
            }
            
            # 캐시에 저장
            self.payout_cache[container_name] = result
            self.last_check_time[container_name] = datetime.now()
            
            return result
            
        except Exception as e:
            logger.error(f"Payout check failed for {container_name}: {e}")
            return {
                "container": container_name,
                "error": str(e)
            }
    
    async def _check_sync_status(self, container_name: str, port: int) -> Dict[str, Any]:
        """노드 동기화 상태 확인"""
        try:
            cmd = [
                'docker', 'exec', container_name,
                'curl', '-s', '-H', 'Content-Type: application/json',
                '-d', json.dumps({
                    "jsonrpc": "2.0",
                    "method": "system_health",
                    "params": [],
                    "id": 1
                }),
                f'http://localhost:{port}/'
            ]
            
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await process.communicate()
            
            if process.returncode == 0:
                response = json.loads(stdout.decode())
                health = response.get('result', {})
                return {
                    "synced": health.get('isSyncing', True) == False,
                    "peers": health.get('peers', 0)
                }
        except Exception as e:
            logger.error(f"Failed to check sync status: {e}")
        
        return {"synced": False, "peers": 0}
    
    async def _get_current_era(self, container_name: str, port: int) -> Optional[int]:
        """현재 era 가져오기"""
        try:
            cmd = [
                'docker', 'exec', container_name,
                'curl', '-s', '-H', 'Content-Type: application/json',
                '-d', json.dumps({
                    "jsonrpc": "2.0",
                    "method": "query_staking_activeEra",
                    "params": [],
                    "id": 1
                }),
                f'http://localhost:{port}/'
            ]
            
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await process.communicate()
            
            if process.returncode == 0:
                response = json.loads(stdout.decode())
                return response.get('result', {}).get('index')
        except Exception as e:
            logger.error(f"Failed to get current era: {e}")
        
        return None
    
    async def _check_unclaimed_payouts(self, container_name: str, port: int, current_era: int) -> Dict[str, Any]:
        """미청구 페이아웃 확인 (샘플링)"""
        try:
            # 실제 구현에서는 관심있는 검증인 리스트를 가지고 있거나
            # 또는 전체 검증인 중 일부를 샘플링하여 체크
            
            # 여기서는 단순화를 위해 기본 정보만 반환
            # 실제로는 query_staking_validators 등을 사용하여
            # 검증인 목록을 가져오고 각각의 미청구 보상을 확인해야 함
            
            return {
                "unclaimed_count": 0,  # 실제로는 체크 로직 필요
                "sample_validators": [],
                "checked_eras": 0,
                "note": "Simplified implementation - actual payout checking requires validator list"
            }
            
        except Exception as e:
            logger.error(f"Failed to check unclaimed payouts: {e}")
            return {"unclaimed_count": 0, "error": str(e)}
    
    async def check_all_payouts(self, containers: List[str]) -> Dict[str, Any]:
        """모든 컨테이너를 통해 페이아웃 체크"""
        results = {}
        
        logger.debug(f"PayoutChecker received containers: {containers}")
        
        # 노드 컨테이너만 필터링
        node_containers = [c for c in containers if c.startswith(('node', '3node'))]
        logger.debug(f"Filtered node containers: {node_containers}")
        
        # 병렬로 체크 (하지만 첫 번째 동기화된 노드만 사용해도 충분)
        for container in node_containers:
            result = await self.check_container_payout(container)
            results[container] = result
            
            # 동기화된 노드를 찾으면 그것만 사용
            if result.get('synced') and not result.get('error'):
                logger.info(f"Using synced node {container} for payout check")
                break
        
        return {
            "payout_checks": results,
            "timestamp": datetime.now().isoformat(),
            "note": "Payout can be executed by anyone - gas fees paid by executor"
        }
    
    def get_summary(self) -> Dict[str, Any]:
        """페이아웃 체크 요약"""
        synced_nodes = []
        total_unclaimed = 0
        
        for container, data in self.payout_cache.items():
            if data.get('synced') and not data.get('error'):
                synced_nodes.append(container)
                total_unclaimed += data.get('unclaimed_payouts', 0)
        
        return {
            "synced_nodes": synced_nodes,
            "total_unclaimed_payouts": total_unclaimed,
            "last_check": max(
                [t.isoformat() for t in self.last_check_time.values()],
                default=None
            ),
            "note": "Anyone can execute payouts - executor pays gas fees"
        }