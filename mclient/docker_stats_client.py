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
        
        # 컨테이너 상태 정보 캐시
        self.container_info_cache = {}
        self.container_status_cache = {}
        self.status_cache_timestamps = {}
        self.status_cache_ttl = 5.0  # 5초 캐시 유효 시간
        
        # RPC 헬스체크 태스크
        self.health_check_tasks = {}  # 컨테이너별 헬스체크 태스크
        self.health_check_interval = 10.0  # 10초마다 체크
        
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
        
        # 컨테이너별 환경변수 캐시 및 타임스탬프
        self.container_env_cache = {}
        self.env_cache_timestamps = {}
        self.env_cache_ttl = 1.0  # 1초 캐시 유효 시간
    
    async def get_container_env(self, container_name: str) -> Dict[str, str]:
        """컨테이너의 환경변수를 가져옴"""
        current_time = time.time()
        
        # 캐시 유효성 확인
        if container_name in self.container_env_cache:
            cache_time = self.env_cache_timestamps.get(container_name, 0)
            if current_time - cache_time < self.env_cache_ttl:
                return self.container_env_cache[container_name]
        
        try:
            # docker inspect로 환경변수 가져오기
            result = await asyncio.create_subprocess_exec(
                "docker", "inspect", container_name,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()
            
            if result.returncode == 0:
                container_info = json.loads(stdout.decode())
                if container_info and len(container_info) > 0:
                    env_list = container_info[0].get("Config", {}).get("Env", [])
                    env_dict = {}
                    for env_str in env_list:
                        if "=" in env_str:
                            key, value = env_str.split("=", 1)
                            env_dict[key] = value
                    
                    # 캐시에 저장 (타임스탬프와 함께)
                    self.container_env_cache[container_name] = env_dict
                    self.env_cache_timestamps[container_name] = current_time
                    return env_dict
        except Exception as e:
            logger.error(f"컨테이너 {container_name} 환경변수 가져오기 실패: {e}")
        
        return {}
    
    async def get_container_info(self, container_name: str) -> Dict[str, Any]:
        """컨테이너의 상세 정보를 가져옴 (이미지, 상태 등)"""
        current_time = time.time()
        
        # 캐시 유효성 확인
        if container_name in self.container_info_cache:
            cache_time = self.status_cache_timestamps.get(f"{container_name}_info", 0)
            if current_time - cache_time < self.status_cache_ttl:
                return self.container_info_cache[container_name]
        
        try:
            # docker inspect로 컨테이너 정보 가져오기
            result = await asyncio.create_subprocess_exec(
                "docker", "inspect", container_name,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()
            
            if result.returncode == 0:
                container_info = json.loads(stdout.decode())
                if container_info and len(container_info) > 0:
                    info = container_info[0]
                    
                    # 이미지 정보 가져오기
                    image_name = info.get("Config", {}).get("Image", "")
                    image_info = await self.get_image_info(image_name)
                    
                    processed_info = {
                        "container_id": info.get("Id", "")[:12],
                        "image": image_name,
                        "image_id": info.get("Image", "")[:12],
                        "image_size": image_info.get("size", 0),
                        "image_size_gb": image_info.get("size_gb", 0),
                        "created": info.get("Created", ""),
                        "state": info.get("State", {}).get("Status", ""),
                        "uptime": info.get("State", {}).get("StartedAt", ""),
                        "restart_count": info.get("RestartCount", 0),
                        "ports": self._extract_port_info(info),
                        "volumes": self._extract_volume_info(info),
                        "network_mode": info.get("HostConfig", {}).get("NetworkMode", "")
                    }
                    
                    # 캐시에 저장
                    self.container_info_cache[container_name] = processed_info
                    self.status_cache_timestamps[f"{container_name}_info"] = current_time
                    return processed_info
        except Exception as e:
            logger.error(f"컨테이너 {container_name} 정보 가져오기 실패: {e}")
        
        return {}
    
    async def get_image_info(self, image_name: str) -> Dict[str, Any]:
        """이미지 정보를 가져옴"""
        try:
            result = await asyncio.create_subprocess_exec(
                "docker", "image", "inspect", image_name,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()
            
            if result.returncode == 0:
                image_info = json.loads(stdout.decode())
                if image_info and len(image_info) > 0:
                    info = image_info[0]
                    size_bytes = info.get("Size", 0)
                    return {
                        "id": info.get("Id", "")[:12],
                        "size": size_bytes,
                        "size_gb": round(size_bytes / 1024 / 1024 / 1024, 2),
                        "created": info.get("Created", ""),
                        "architecture": info.get("Architecture", ""),
                        "os": info.get("Os", "")
                    }
        except Exception as e:
            logger.error(f"이미지 {image_name} 정보 가져오기 실패: {e}")
        
        return {"size": 0, "size_gb": 0}
    
    def _extract_port_info(self, container_info: Dict) -> List[Dict]:
        """컨테이너 포트 정보 추출"""
        ports = []
        port_bindings = container_info.get("NetworkSettings", {}).get("Ports", {})
        
        for container_port, host_bindings in port_bindings.items():
            if host_bindings:
                for binding in host_bindings:
                    ports.append({
                        "container": container_port,
                        "host": f"{binding.get('HostIp', '')}:{binding.get('HostPort', '')}"
                    })
        
        return ports
    
    def _extract_volume_info(self, container_info: Dict) -> List[Dict]:
        """컨테이너 볼륨 정보 추출"""
        volumes = []
        mounts = container_info.get("Mounts", [])
        
        for mount in mounts:
            volumes.append({
                "type": mount.get("Type", ""),
                "source": mount.get("Source", ""),
                "destination": mount.get("Destination", ""),
                "mode": mount.get("Mode", "")
            })
        
        return volumes
    
    async def check_node_health(self, container_name: str, rpc_port: int) -> Dict[str, Any]:
        """노드의 건강 상태를 체크 (블록 동기화 상태 등)"""
        try:
            # RPC를 통해 노드 상태 확인
            cmd = [
                "docker", "exec", container_name,
                "curl", "-s", "-H", "Content-Type: application/json",
                "-d", '{"id":1, "jsonrpc":"2.0", "method": "system_health", "params":[]}',
                f"http://localhost:{rpc_port}/"
            ]
            
            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()
            
            if result.returncode == 0:
                response = json.loads(stdout.decode())
                if "result" in response:
                    health = response["result"]
                    
                    # 동기화 상태 확인
                    is_syncing = health.get("isSyncing", False)
                    peers = health.get("peers", 0)
                    
                    # 블록 정보와 동기화 상태 정보를 병렬로 가져오기
                    block_info_task = asyncio.create_task(self.get_block_info(container_name, rpc_port))
                    sync_state_task = asyncio.create_task(self.get_sync_state(container_name, rpc_port))
                    
                    # return_exceptions=True로 개별 실패를 처리
                    results = await asyncio.gather(block_info_task, sync_state_task, return_exceptions=True)
                    
                    # 결과 처리
                    block_info = results[0] if not isinstance(results[0], Exception) else {"current_block": 0, "best_block": 0, "finalized_block": 0}
                    sync_info = results[1] if not isinstance(results[1], Exception) else {"highest_block": 0, "starting_block": 0}
                    
                    return {
                        "is_syncing": is_syncing,
                        "peers": peers,
                        "should_have_peers": health.get("shouldHavePeers", True),
                        "current_block": block_info.get("current_block", 0),
                        "best_block": block_info.get("best_block", 0),
                        "finalized_block": block_info.get("finalized_block", 0),
                        "target_block": sync_info.get("highest_block", 0),
                        "starting_block": sync_info.get("starting_block", 0),
                        "sync_state": self._determine_sync_state(is_syncing, peers, block_info)
                    }
        except Exception as e:
            logger.error(f"노드 {container_name} 건강 상태 체크 실패: {e}")
        
        # 헬스체크 실패 시 이전 상태 유지
        previous_state = self.container_status_cache.get(container_name, {}).get("sync_state", "unknown")
        # initializing 상태였으면 유지
        if previous_state == "initializing":
            return {
                "is_syncing": None,
                "peers": 0,
                "sync_state": "initializing"
            }
        
        return {
            "is_syncing": None,
            "peers": 0,
            "sync_state": "unknown"
        }
    
    async def get_block_info(self, container_name: str, rpc_port: int) -> Dict[str, Any]:
        """노드의 블록 정보를 가져옴"""
        try:
            # 컨테이너 실행 상태 확인
            check_cmd = ["docker", "inspect", "-f", "{{.State.Running}}", container_name]
            check_result = await asyncio.create_subprocess_exec(
                *check_cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, _ = await check_result.communicate()
            
            if check_result.returncode != 0 or stdout.decode().strip() != "true":
                logger.debug(f"컨테이너 {container_name}가 실행 중이 아님 - 블록 정보 건너뜀")
                return {"current_block": 0, "best_block": 0, "finalized_block": 0}
            
            # 현재 블록 번호 가져오기
            cmd = [
                "docker", "exec", container_name,
                "curl", "-s", "-H", "Content-Type: application/json",
                "-d", '{"id":1, "jsonrpc":"2.0", "method": "chain_getHeader", "params":[]}',
                f"http://localhost:{rpc_port}/"
            ]
            
            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()
            
            if result.returncode == 0:
                response = json.loads(stdout.decode())
                if "result" in response:
                    header = response["result"]
                    current_block = int(header.get("number", "0x0"), 16)
                    
                    # Finalized 블록 정보도 가져오기
                    finalized_block = await self.get_finalized_block(container_name, rpc_port)
                    
                    return {
                        "current_block": current_block,
                        "best_block": current_block,  # 일단 같은 값으로
                        "finalized_block": finalized_block
                    }
        except Exception as e:
            logger.error(f"블록 정보 가져오기 실패: {e}")
        
        return {"current_block": 0, "best_block": 0, "finalized_block": 0}
    
    async def get_finalized_block(self, container_name: str, rpc_port: int) -> int:
        """Finalized 블록 번호를 가져옴"""
        try:
            cmd = [
                "docker", "exec", container_name,
                "curl", "-s", "-H", "Content-Type: application/json",
                "-d", '{"id":1, "jsonrpc":"2.0", "method": "chain_getFinalizedHead", "params":[]}',
                f"http://localhost:{rpc_port}/"
            ]
            
            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()
            
            if result.returncode == 0:
                response = json.loads(stdout.decode())
                if "result" in response:
                    # Finalized 블록 해시로 헤더 정보 가져오기
                    finalized_hash = response["result"]
                    
                    # 블록 헤더 정보 가져오기
                    cmd2 = [
                        "docker", "exec", container_name,
                        "curl", "-s", "-H", "Content-Type: application/json",
                        "-d", f'{{"id":1, "jsonrpc":"2.0", "method": "chain_getHeader", "params":["{finalized_hash}"]}}',
                        f"http://localhost:{rpc_port}/"
                    ]
                    
                    result2 = await asyncio.create_subprocess_exec(
                        *cmd2,
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.PIPE
                    )
                    stdout2, stderr2 = await result2.communicate()
                    
                    if result2.returncode == 0:
                        response2 = json.loads(stdout2.decode())
                        if "result" in response2:
                            header = response2["result"]
                            return int(header.get("number", "0x0"), 16)
        except Exception as e:
            logger.error(f"Finalized 블록 정보 가져오기 실패: {e}")
        
        return 0
    
    async def get_sync_state(self, container_name: str, rpc_port: int) -> Dict[str, Any]:
        """노드의 동기화 상태 정보를 가져옴"""
        try:
            # 컨테이너 실행 상태 확인
            check_cmd = ["docker", "inspect", "-f", "{{.State.Running}}", container_name]
            check_result = await asyncio.create_subprocess_exec(
                *check_cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, _ = await check_result.communicate()
            
            if check_result.returncode != 0 or stdout.decode().strip() != "true":
                logger.debug(f"컨테이너 {container_name}가 실행 중이 아님 - 동기화 상태 건너뜀")
                return {"highest_block": 0, "starting_block": 0}
            cmd = [
                "docker", "exec", container_name,
                "curl", "-s", "-H", "Content-Type: application/json",
                "-d", '{"id":1, "jsonrpc":"2.0", "method": "system_syncState", "params":[]}',
                f"http://localhost:{rpc_port}/"
            ]
            
            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()
            
            if result.returncode == 0 and stdout:
                try:
                    response = json.loads(stdout.decode())
                    if "result" in response and response["result"] is not None:
                        sync_state = response["result"]
                        return {
                            "starting_block": sync_state.get("startingBlock", 0),
                            "current_block": sync_state.get("currentBlock", 0),
                            "highest_block": sync_state.get("highestBlock", 0)
                        }
                except json.JSONDecodeError:
                    pass
        except Exception as e:
            # 동기화 중이 아닐 때는 에러가 발생할 수 있으므로 debug 레벨로 로깅
            logger.debug(f"동기화 상태 정보 가져오기 실패 (정상일 수 있음): {e}")
        
        return {
            "starting_block": 0,
            "current_block": 0,
            "highest_block": 0
        }
    
    def _determine_sync_state(self, is_syncing: bool, peers: int, block_info: Dict) -> str:
        """노드의 동기화 상태를 판단"""
        if is_syncing:
            return "syncing"
        elif peers == 0:
            return "no_peers"
        elif block_info.get("current_block", 0) == 0:
            return "initializing"
        else:
            # 현재 블록과 finalized 블록의 차이를 확인
            current = block_info.get("current_block", 0)
            finalized = block_info.get("finalized_block", 0)
            
            if current - finalized > 100:  # 100블록 이상 차이나면 동기화 중
                return "catching_up"
            else:
                return "synced"
    
    def _extract_rpc_port(self, env_vars: Dict[str, str], container_name: str) -> Optional[int]:
        """환경변수에서 RPC 포트를 추출"""
        # RPC_PORT 환경변수 확인
        rpc_port = env_vars.get("RPC_PORT", "")
        if rpc_port and rpc_port.isdigit():
            return int(rpc_port)
        
        # 컨테이너 이름별 RPC 포트 패턴
        if container_name.startswith("3node"):
            try:
                node_num = int(container_name.replace("3node", ""))
                return 33980 + node_num
            except:
                pass
        elif container_name.startswith("node"):
            try:
                node_num = int(container_name.replace("node", ""))
                return 33880 + node_num  # Creditcoin 2.x는 33880부터 시작
            except:
                pass
        
        return None
    
    async def check_image_building(self) -> Dict[str, Any]:
        """현재 빌드 중인 이미지가 있는지 확인"""
        try:
            # docker ps로 빌드 중인 컨테이너 확인
            cmd = ["docker", "ps", "--filter", "status=created", "--format", "{{json .}}"]
            
            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()
            
            building_images = []
            if result.returncode == 0 and stdout:
                lines = stdout.decode().strip().split('\n')
                for line in lines:
                    if line:
                        try:
                            container = json.loads(line)
                            # 빌드 중인 이미지 정보 추가
                            building_images.append({
                                "image": container.get("Image", ""),
                                "status": container.get("Status", ""),
                                "name": container.get("Names", "")
                            })
                        except:
                            pass
            
            # docker images로 최근 생성된 이미지 확인
            cmd2 = ["docker", "images", "--format", "{{json .}}"]
            
            result2 = await asyncio.create_subprocess_exec(
                *cmd2,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout2, stderr2 = await result2.communicate()
            
            recent_images = []
            if result2.returncode == 0 and stdout2:
                lines = stdout2.decode().strip().split('\n')[:5]  # 최근 5개만
                for line in lines:
                    if line:
                        try:
                            image = json.loads(line)
                            recent_images.append({
                                "repository": image.get("Repository", ""),
                                "tag": image.get("Tag", ""),
                                "created": image.get("CreatedAt", ""),
                                "size": image.get("Size", "")
                            })
                        except:
                            pass
            
            return {
                "building": building_images,
                "recent": recent_images
            }
            
        except Exception as e:
            logger.error(f"이미지 빌드 상태 확인 실패: {e}")
        
        return {"building": [], "recent": []}
    
    async def _health_check_stream(self, container_name: str, rpc_port: int):
        """노드 헬스체크를 주기적으로 실행하는 스트림"""
        logger.info(f"헬스체크 스트림 시작: {container_name} (RPC: {rpc_port})")
        consecutive_failures = 0
        
        while self.running:
            try:
                # 컨테이너가 실행 중인지 먼저 확인
                cmd = ["docker", "inspect", "-f", "{{.State.Running}}", container_name]
                result = await asyncio.create_subprocess_exec(
                    *cmd,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE
                )
                stdout, stderr = await result.communicate()
                
                if result.returncode != 0 or stdout.decode().strip() != "true":
                    logger.warning(f"컨테이너 {container_name}가 실행 중이 아닙니다. 헬스체크 건너뜀")
                    # 오프라인 상태로 캐시 업데이트
                    self.container_status_cache[container_name] = {
                        "is_syncing": False,
                        "peers": 0,
                        "should_have_peers": True,
                        "current_block": 0,
                        "best_block": 0,
                        "finalized_block": 0,
                        "target_block": 0,
                        "starting_block": 0,
                        "sync_state": "offline"
                    }
                    # 오프라인 컨테이너는 더 긴 간격으로 체크
                    await asyncio.sleep(self.health_check_interval * 5)
                    continue
                
                # 헬스 정보 수집
                health_info = await self.check_node_health(container_name, rpc_port)
                
                # 캐시에 저장
                self.container_status_cache[container_name] = health_info
                consecutive_failures = 0
                
                # 대기
                await asyncio.sleep(self.health_check_interval)
                
            except asyncio.CancelledError:
                logger.info(f"헬스체크 스트림 취소됨: {container_name}")
                break
            except Exception as e:
                consecutive_failures += 1
                logger.error(f"헬스체크 스트림 오류 ({container_name}): {e}")
                # 백오프: 실패할수록 대기 시간 증가 (최대 60초)
                wait_time = min(60, self.health_check_interval * (2 ** consecutive_failures))
                await asyncio.sleep(wait_time)
    
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
        
        if self.stats_process and self.stats_process.returncode is None:
            try:
                self.stats_process.terminate()
                await asyncio.sleep(0.5)
                if self.stats_process.returncode is None:
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
        
        # 헬스체크 태스크들 정리
        for container_name, task in self.health_check_tasks.items():
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass
        self.health_check_tasks.clear()
        
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
                last_cleanup_time = time.time()
                cleanup_interval = 1.0  # 1초마다 정리
                
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
                        
                        # 현재 업데이트 주기에서 발견된 컨테이너 이름 추적
                        current_containers = set()
                        
                        # 찾은 JSON 객체 처리
                        for json_str in json_objects.get('objects', []):
                            try:
                                # JSON 파싱
                                stats_json = json.loads(json_str)
                                
                                # 컨테이너 이름 추출
                                container_name = stats_json.get("Name", "")
                                if not container_name:
                                    continue
                                
                                current_containers.add(container_name)
                                
                                # 데이터 처리
                                processed_stats = self._process_stats_json(stats_json)
                                if processed_stats:
                                    # 환경변수에서 TELEMETRY_NAME 가져오기
                                    env_vars = await self.get_container_env(container_name)
                                    telemetry_name = env_vars.get("TELEMETRY_NAME", "")  # 없으면 빈 문자열
                                    processed_stats["node_name"] = container_name  # node_name은 항상 컨테이너 이름
                                    processed_stats["nickname"] = telemetry_name  # nickname은 텔레메트리 이름 (없으면 빈 문자열)
                                    
                                    # 이미지 이름은 환경변수에서 가져오기 (이미 있음)
                                    image_name = env_vars.get("IMAGE", "")
                                    if not image_name and "GIT_TAG" in env_vars:
                                        # GIT_TAG로 이미지 이름 추정
                                        if "3node" in container_name:
                                            image_name = f"creditcoin3:{env_vars.get('GIT_TAG', '')}"
                                        elif "node" in container_name:
                                            image_name = f"creditcoin2:{env_vars.get('GIT_TAG', '')}"
                                    
                                    # 노드 타입 판단 (이미지 이름 기반)
                                    if "creditcoin3" in image_name:
                                        processed_stats["node_type"] = "creditcoin3"
                                    elif "creditcoin2" in image_name:
                                        processed_stats["node_type"] = "creditcoin2"
                                    elif "mclient" in container_name:
                                        processed_stats["node_type"] = "mclient"
                                    elif "postgres" in container_name or "db" in container_name:
                                        processed_stats["node_type"] = "postgres"
                                    else:
                                        processed_stats["node_type"] = "unknown"
                                    
                                    # mclient 자기 자신은 제외
                                    if processed_stats["node_type"] == "mclient":
                                        continue
                                    
                                    # 볼륨 크기 계산 (블록체인 데이터)
                                    volume_size = 0
                                    if processed_stats["node_type"] in ["creditcoin2", "creditcoin3"]:
                                        volume_size = await self.get_volume_size(container_name)
                                    
                                    processed_stats["image_name"] = image_name
                                    processed_stats["data_size"] = volume_size  # image_size 대신 data_size 사용
                                    
                                    
                                    # 블록체인 노드인 경우 헬스체크 태스크 시작
                                    if processed_stats["node_type"] in ["creditcoin2", "creditcoin3"]:
                                        rpc_port = self._extract_rpc_port(env_vars, container_name)
                                        if rpc_port and container_name not in self.health_check_tasks:
                                            # 헬스체크 태스크가 없으면 시작
                                            task = asyncio.create_task(self._health_check_stream(container_name, rpc_port))
                                            self.health_check_tasks[container_name] = task
                                        
                                        # 캐시된 헬스 정보가 있으면 사용
                                        if container_name in self.container_status_cache:
                                            health_info = self.container_status_cache[container_name]
                                            processed_stats["sync_state"] = health_info.get("sync_state", "unknown")
                                            processed_stats["blockchain"] = {
                                                "current_block": health_info.get("current_block", 0),
                                                "finalized_block": health_info.get("finalized_block", 0),
                                                "target_block": health_info.get("target_block", 0),
                                                "starting_block": health_info.get("starting_block", 0),
                                                "peers": health_info.get("peers", 0)
                                            }
                                        else:
                                            # 초기값
                                            processed_stats["sync_state"] = "checking"
                                            processed_stats["blockchain"] = {
                                                "current_block": 0,
                                                "finalized_block": 0,
                                                "target_block": 0,
                                                "starting_block": 0,
                                                "peers": 0
                                            }
                                    
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
                        
                        # 주기적으로 중지된 컨테이너 정리
                        current_time = time.time()
                        if current_time - last_cleanup_time > cleanup_interval and current_containers:
                            # 현재 stats에 없는 컨테이너는 캐시에서 제거
                            removed_containers = []
                            for container_name in list(self.container_stats.keys()):
                                if container_name not in current_containers:
                                    del self.container_stats[container_name]
                                    # 환경변수 캐시도 정리
                                    if container_name in self.container_env_cache:
                                        del self.container_env_cache[container_name]
                                    if container_name in self.env_cache_timestamps:
                                        del self.env_cache_timestamps[container_name]
                                    removed_containers.append(container_name)
                            
                            if removed_containers:
                                logger.info(f"중지된 컨테이너 제거: {', '.join(removed_containers)}")
                            
                            last_cleanup_time = current_time
                            
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
            
            # CPU 값 디버깅
            if cpu_percent > 0:
                logger.debug(f"CPU 처리: 원본='{cpu_str}' -> 파싱결과={cpu_percent} -> round(2)={round(cpu_percent, 2)}")
            
            # 메모리 사용량 파싱
            mem_percent_str = stats_json.get("MemPerc", "0%")
            mem_percent = self._parse_percentage(mem_percent_str)
            
            mem_usage = stats_json.get("MemUsage", "0B / 0B")
            mem_used = 0
            mem_limit = 0
            
            # 메모리 사용량/한계 파싱 - 실패해도 계속 진행
            try:
                # 다양한 구분자 처리
                separators = [" / ", "/", " | ", "|"]
                for sep in separators:
                    if sep in mem_usage:
                        parts = mem_usage.split(sep)
                        if len(parts) >= 2:
                            mem_used = self._parse_size_with_unit(parts[0].strip())
                            mem_limit = self._parse_size_with_unit(parts[1].strip())
                            break
            except:
                # 파싱 실패해도 기본값 사용
                pass
            
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
            
            # 컨테이너 별명 (nickname) 설정 - 기본값은 빈 문자열
            nickname = ""
            
            # 결과 구성
            result = {
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
            
            # CPU 값이 소수점이 있는 경우 디버깅
            if cpu_percent > 0 and cpu_percent != int(cpu_percent):
                logger.debug(f"최종 CPU 결과 ({container_name}): 원본={cpu_percent}, round(2)={result['cpu']['percent']}")
            
            return result
        
        except Exception as e:
            logger.error(f"Stats JSON 처리 중 오류: {str(e)}")
            return None
    
    def _parse_percentage(self, percent_str: str) -> float:
        """백분율 문자열 파싱 - 다양한 형식 자동 처리"""
        if not percent_str:
            return 0.0
        
        try:
            # 문자열 정리
            cleaned = percent_str.strip().rstrip('%')
            
            # 특수 케이스 처리
            if cleaned in ['--', '-', 'N/A', 'n/a', '']:
                return 0.0
            
            # 숫자만 추출 (정규표현식)
            import re
            match = re.search(r'[\d.]+', cleaned)
            if match:
                result = float(match.group())
                # 디버그 로그 추가
                if result > 0 and result != round(result, 2):
                    logger.debug(f"CPU 파싱: '{percent_str}' -> cleaned: '{cleaned}' -> result: {result}")
                return result
            
            return 0.0
        except Exception as e:
            logger.error(f"퍼센트 파싱 오류: '{percent_str}' - {e}")
            return 0.0
    
    async def get_volume_size(self, container_name: str) -> int:
        """컨테이너의 볼륨 크기를 가져옴 (바이트 단위)"""
        try:
            # 볼륨 경로 찾기
            cmd = ["docker", "inspect", container_name, "--format", '{{range .Mounts}}{{if eq .Destination "/root/data"}}{{.Source}}{{end}}{{end}}']
            result = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await result.communicate()
            
            if result.returncode == 0:
                volume_path = stdout.decode().strip()
                if volume_path:
                    logger.debug(f"볼륨 경로 ({container_name}): {volume_path}")
                    # 컨테이너 내부에서 du 명령 실행
                    du_result = await asyncio.create_subprocess_exec(
                        "docker", "exec", container_name, "du", "-sb", "/root/data",
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.PIPE
                    )
                    du_stdout, du_stderr = await du_result.communicate()
                    
                    if du_result.returncode == 0:
                        # du 출력: "크기\t경로"
                        size_str = du_stdout.decode().split('\t')[0]
                        size = int(size_str)
                        logger.debug(f"볼륨 크기 ({container_name}): {size:,} bytes")
                        return size
                    else:
                        logger.error(f"du 명령 실패 ({container_name}): {du_stderr.decode()}")
                else:
                    logger.warning(f"볼륨 경로를 찾을 수 없음 ({container_name})")
            else:
                logger.error(f"docker inspect 실패 ({container_name}): {stderr.decode()}")
        except Exception as e:
            logger.error(f"볼륨 크기 가져오기 실패 ({container_name}): {e}")
        
        return 0
    
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
                'Ti': 1024 ** 4,
                # 소문자 형식 추가
                'kB': 1024,
                'mB': 1024 ** 2,
                'gB': 1024 ** 3,
                'tB': 1024 ** 4
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
    
    async def get_server_containers(self) -> List[Dict[str, Any]]:
        """mserver와 PostgreSQL 컨테이너 정보 수집 (캐시된 데이터 사용)"""
        server_containers = []
        
        try:
            # 이미 수집된 container_stats에서 서버 컨테이너 찾기
            for container_name, stats in self.container_stats.items():
                # mserver 또는 postgres 관련 컨테이너인지 확인
                if 'mserver' in container_name.lower() or 'postgres' in container_name.lower():
                    # 이미 수집된 통계 데이터 사용
                    if stats:
                        server_containers.append(stats)
                        logger.debug(f"캐시된 서버 컨테이너 데이터 사용: {container_name}")
        
        except Exception as e:
            logger.error(f"서버 컨테이너 정보 수집 실패: {e}")
        
        return server_containers
