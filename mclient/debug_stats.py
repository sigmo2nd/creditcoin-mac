#!/usr/bin/env python3
import asyncio
import json
import os
import subprocess
from docker_stats_client import DockerStatsClient
from dotenv import load_dotenv

async def main():
    # 환경변수 로드
    load_dotenv('.env.mclient')
    
    print("=== Docker 상태 확인 ===")
    
    # 1. 실행 중인 컨테이너 확인
    result = subprocess.run(['docker', 'ps', '--format', '{{.Names}}'], 
                          capture_output=True, text=True)
    running_containers = [name for name in result.stdout.strip().split('\n') 
                         if name and ('node' in name or '3node' in name)]
    print(f"실행 중인 노드 컨테이너: {running_containers}")
    
    # 2. docker stats 직접 확인
    result = subprocess.run(['docker', 'stats', '--no-stream', '--format', '{{.Name}}'],
                          capture_output=True, text=True)
    stats_containers = [name for name in result.stdout.strip().split('\n')
                       if name and ('node' in name or '3node' in name)]
    print(f"Docker stats에 표시되는 노드: {stats_containers}")
    
    # 3. NODE_NAMES 환경변수 확인
    node_names = os.getenv('NODE_NAMES', '').split(',')
    print(f"설정된 NODE_NAMES: {node_names}")
    
    # 4. DockerStatsClient로 데이터 수집
    print("\n=== DockerStatsClient 테스트 ===")
    client = DockerStatsClient()
    
    # 모니터링 시작
    success = await client.start_stats_monitoring(node_names)
    print(f"모니터링 시작: {success}")
    
    # 데이터 수집 대기
    await asyncio.sleep(3)
    
    # 수집된 데이터 확인
    stats_data = await client.get_stats_for_nodes(node_names)
    print(f"\n수집된 노드 데이터 키: {list(stats_data.keys())}")
    
    # 각 노드 정보 출력
    for node_name, data in stats_data.items():
        print(f"\n{node_name}:")
        print(f"  - CPU: {data.get('cpu_percent', 'N/A')}%")
        print(f"  - Memory: {data.get('memory_percent', 'N/A')}%")
        print(f"  - Status: {data.get('status', 'N/A')}")
    
    # 정리
    await client.stop_stats_monitoring()
    
    # 5. 실제 전송될 데이터 구조 확인
    print("\n=== 전송 데이터 구조 ===")
    container_list = list(stats_data.values())
    data = {
        "configured_nodes": node_names,
        "containers": container_list
    }
    print(f"configured_nodes 개수: {len(node_names)}")
    print(f"containers 개수: {len(container_list)}")
    print(f"containers 이름들: {[c.get('name') for c in container_list]}")

if __name__ == "__main__":
    asyncio.run(main())