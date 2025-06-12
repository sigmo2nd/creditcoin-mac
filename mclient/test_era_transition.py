#!/usr/bin/env python3
"""
Era 전환 자동 감지 테스트 스크립트
"""
import asyncio
import logging
from payout_checker import PayoutChecker
from era_monitor import EraMonitor
from websocket_client import WebSocketClient
import os
from dotenv import load_dotenv

# 로깅 설정
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

async def test_era_transition():
    """Era 전환 감지 테스트"""
    
    # 환경 변수 로드
    load_dotenv('.env.mclient')
    
    # WebSocket 클라이언트 초기화 (실제 서버 연결 없이 테스트)
    websocket_client = WebSocketClient(
        url_or_mode='wss://localhost:8765',
        server_id='test_server',
        ssl_verify=False
    )
    
    # PayoutChecker와 EraMonitor 초기화
    payout_checker = PayoutChecker()
    era_monitor = EraMonitor(websocket_client)
    
    # 테스트 시나리오 1: 빈 컨테이너 목록
    logger.info("=== 테스트 1: 빈 컨테이너 목록 ===")
    empty_containers = []
    result1 = await payout_checker.check_all_payouts(empty_containers)
    logger.info(f"빈 컨테이너 결과: {result1}")
    
    # 테스트 시나리오 2: configured_nodes 사용
    logger.info("\n=== 테스트 2: configured_nodes로 테스트 ===")
    configured_nodes = ['3node0', '3node1', '3node2']
    result2 = await payout_checker.check_all_payouts(configured_nodes)
    logger.info(f"configured_nodes 결과: {result2}")
    
    # 테스트 시나리오 3: Era 전환 체크
    logger.info("\n=== 테스트 3: Era 전환 체크 ===")
    if result2.get('payout_checks'):
        transitions = await era_monitor.check_era_transition(result2)
        if transitions:
            logger.info(f"Era 전환 감지됨: {transitions}")
        else:
            logger.info("Era 전환 없음")
    
    # 테스트 시나리오 4: 실제 컨테이너 목록 시뮬레이션
    logger.info("\n=== 테스트 4: 실제 컨테이너 목록 시뮬레이션 ===")
    simulated_containers = [
        {'name': '3node0', 'status': 'running'},
        {'name': '3node1', 'status': 'running'},
        {'name': 'postgres', 'status': 'running'},  # 이건 필터링됨
        {'name': 'redis', 'status': 'running'}      # 이것도 필터링됨
    ]
    
    # main.py의 로직 시뮬레이션
    container_names = [c.get('name') for c in simulated_containers 
                      if c.get('name') and c.get('name').startswith(('node', '3node'))]
    logger.info(f"필터링된 컨테이너: {container_names}")
    
    result4 = await payout_checker.check_all_payouts(container_names)
    logger.info(f"필터링된 컨테이너 결과: {result4}")

async def test_summary_data_extraction():
    """summary_data에서 컨테이너 추출 테스트"""
    logger.info("\n=== 테스트 5: summary_data 구조 테스트 ===")
    
    # 실제 summary_data 구조 시뮬레이션
    summary_data = {
        'system': {
            'cpu_percent': 45.2,
            'memory_percent': 62.1
        },
        'containers': [
            {
                'name': '3node0',
                'cpu_percent': 12.5,
                'memory_percent': 25.3,
                'network_rx_mb': 100.5,
                'network_tx_mb': 50.2
            },
            {
                'name': '3node1',
                'cpu_percent': 15.2,
                'memory_percent': 28.1,
                'network_rx_mb': 105.3,
                'network_tx_mb': 52.1
            }
        ],
        'configured_nodes': ['3node0', '3node1', '3node2']
    }
    
    # main.py의 컨테이너 추출 로직
    containers = summary_data.get('containers', [])
    logger.debug(f"Summary data keys: {summary_data.keys()}")
    logger.debug(f"Total containers in summary: {len(containers)}")
    logger.debug(f"Container names in summary: {[c.get('name') for c in containers]}")
    
    container_names = [c.get('name') for c in containers 
                      if c.get('name') and c.get('name').startswith(('node', '3node'))]
    logger.debug(f"Filtered node container names: {container_names}")
    
    # 컨테이너 목록이 비어있으면 configured_nodes 사용
    if not container_names and summary_data.get('configured_nodes'):
        container_names = summary_data.get('configured_nodes', [])
        logger.info(f"Using configured_nodes as fallback: {container_names}")
    
    return container_names

async def main():
    """메인 테스트 실행"""
    try:
        # Era 전환 테스트
        await test_era_transition()
        
        # Summary data 추출 테스트
        container_names = await test_summary_data_extraction()
        logger.info(f"\n최종 추출된 컨테이너 목록: {container_names}")
        
    except Exception as e:
        logger.error(f"테스트 중 오류 발생: {e}", exc_info=True)

if __name__ == "__main__":
    asyncio.run(main())