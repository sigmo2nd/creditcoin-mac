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
        
        if self.stats_process and self.stats_process.poll() is None:
            try:
                self.stats_process.terminate()
                await asyncio.sleep(0.5)
                if self.stats_process.poll() is None:
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
                        
                        # 찾은 JSON 객체 처리
                        for json_str in json_objects.get('objects', []):
                            try:
                                # JSON 파싱
                                stats_json = json.loads(json_str)
                                
                                # 컨테이너 이름 추출
                                container_name = stats_json.get("Name", "")
                                if not container_name:
                                    continue
                                
                                # 데이터 처리
                                processed_stats = self._process_stats_json(stats_json)
                                if processed_stats:
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
            
            # 메모리 사용량 파싱
            mem_percent_str = stats_json.get("MemPerc", "0%")
            mem_percent = self._parse_percentage(mem_percent_str)
            
            mem_usage = stats_json.get("MemUsage", "0B / 0B")
            mem_used = 0
            mem_limit = 0
            
            # 메모리 사용량/한계 파싱
            try:
                if " / " in mem_usage:
                    mem_parts = mem_usage.split(" / ")
                    mem_used_str = mem_parts[0]
                    mem_limit_str = mem_parts[1]
                    
                    mem_used = self._parse_size_with_unit(mem_used_str)
                    mem_limit = self._parse_size_with_unit(mem_limit_str)
                elif "/" in mem_usage:
                    mem_parts = mem_usage.split("/")
                    mem_used_str = mem_parts[0].strip()
                    mem_limit_str = mem_parts[1].strip()
                    
                    mem_used = self._parse_size_with_unit(mem_used_str)
                    mem_limit = self._parse_size_with_unit(mem_limit_str)
            except Exception as e:
                logger.warning(f"메모리 사용량 파싱 실패: {mem_usage} - {str(e)}")
            
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
            
            # 컨테이너 별명 (nickname) 설정 - 패턴 기반으로 자동 결정
            nickname = None
            
            # 컨테이너 이름에서 패턴 찾기
            if container_name.startswith("3node"):
                nickname = f"Creditcoin 3.0 Node {container_name[5:]}"
            elif container_name.startswith("node"):
                nickname = f"Creditcoin 2.0 Node {container_name[4:]}"
            elif "node" in container_name.lower():
                # 기타 노드 패턴 인식
                nickname = f"Node {container_name}"
            elif "creditcoin" in container_name.lower():
                nickname = f"Creditcoin {container_name}"
            else:
                # 특별한 패턴이 없는 경우 컨테이너 이름 그대로 사용
                nickname = container_name
            
            # 결과 구성
            return {
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
        
        except Exception as e:
            logger.error(f"Stats JSON 처리 중 오류: {str(e)}")
            return None
    
    def _parse_percentage(self, percent_str: str) -> float:
        """백분율 문자열 파싱"""
        try:
            if not percent_str:
                return 0.0
            
            # '%' 제거하고 숫자만 추출
            percent_str = percent_str.strip().rstrip('%')
            return float(percent_str)
        except Exception as e:
            logger.warning(f"백분율 파싱 실패: {percent_str} - {str(e)}")
            return 0.0
    
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