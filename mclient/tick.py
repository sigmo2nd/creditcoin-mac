#!/usr/bin/env python3
"""
한 틱의 모니터링 데이터를 JSON으로 출력하는 간단한 스크립트
실제 main.py의 로직을 최대한 재사용
"""
import asyncio
import json
import os
import sys
import time
import logging
from dotenv import load_dotenv

# 로깅 설정 (stderr로 출력하여 JSON 출력과 분리)
logging.basicConfig(
    level=logging.WARNING,
    format='%(message)s',
    stream=sys.stderr
)

async def main():
    # .env.mclient 로드
    load_dotenv('.env.mclient')
    
    # 필요한 모듈들 임포트
    from main import Settings, SystemInfo
    from docker_stats_client import DockerStatsClient
    
    # 설정 로드
    settings = Settings()
    
    # 시스템 정보 수집
    system_info = SystemInfo()
    sys_metrics = system_info.collect()
    
    # 노드 이름 목록
    node_names = settings.NODE_NAMES.split(',') if settings.NODE_NAMES else []
    
    # Docker 정보 수집
    container_list = []
    if not settings.NO_DOCKER:
        try:
            # Docker Stats 클라이언트 초기화
            docker_stats_client = DockerStatsClient()
            
            # Docker stats 모니터링 시작
            success = await docker_stats_client.start_stats_monitoring(node_names)
            if success:
                # 잠시 대기하여 데이터 수집 시간 부여
                await asyncio.sleep(1)
                
                # 수집된 데이터 가져오기
                container_data = await docker_stats_client.get_stats_for_nodes(node_names)
                container_list = list(container_data.values())
                
                # 정리
                await docker_stats_client.stop_stats_monitoring()
            else:
                print(f"Docker Stats 모니터링 시작 실패", file=sys.stderr)
        except Exception as e:
            print(f"Docker 정보 수집 오류: {e}", file=sys.stderr)
    
    # 전송할 데이터 구성 (main.py와 동일한 구조)
    stats_data = {
        "system": sys_metrics,
        "containers": container_list,
        "configured_nodes": node_names
    }
    
    # 실제 전송되는 형태 (websocket_client가 추가하는 필드 포함)
    full_message = {
        "type": "stats",
        "serverId": settings.SERVER_ID,
        "timestamp": int(time.time() * 1000),
        "data": stats_data
    }
    
    # JSON으로 출력 (pretty print)
    print(json.dumps(full_message, indent=2, ensure_ascii=False))

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(0)
    except Exception as e:
        print(f"오류: {e}", file=sys.stderr)
        sys.exit(1)