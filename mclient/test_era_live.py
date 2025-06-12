#!/usr/bin/env python3
"""
실제 환경에서 Era 전환 감지 테스트
"""
import asyncio
import logging
import os
import sys
from dotenv import load_dotenv

# 현재 디렉토리를 Python 경로에 추가
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from payout_checker import PayoutChecker
from era_monitor import EraMonitor
from websocket_client import WebSocketClient

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

async def test_live_era_detection():
    """실제 환경에서 Era 전환 감지 테스트"""
    
    # 환경 변수 로드
    load_dotenv('.env.mclient')
    
    # 노드 목록 가져오기
    node_names = os.getenv('NODE_NAMES', '3node0,3node1,3node2').split(',')
    node_names = [n.strip() for n in node_names if n.strip()]
    
    logger.info(f"테스트할 노드: {node_names}")
    
    # PayoutChecker 초기화
    payout_checker = PayoutChecker()
    
    # 현재 Era 체크
    logger.info("\n=== 현재 Era 상태 체크 ===")
    payout_info = await payout_checker.check_all_payouts(node_names)
    
    logger.info("페이아웃 체크 결과:")
    for node, info in payout_info.get('payout_checks', {}).items():
        if 'error' in info:
            logger.error(f"  {node}: 오류 - {info['error']}")
        else:
            logger.info(f"  {node}: Era {info.get('current_era', '?')}, 동기화: {info.get('synced', False)}")
    
    # EraMonitor로 전환 체크
    websocket_client = None  # 테스트용이므로 실제 연결 없이
    era_monitor = EraMonitor(websocket_client)
    
    # 초기 Era 저장
    logger.info("\n=== Era 모니터 초기화 ===")
    transitions = await era_monitor.check_era_transition(payout_info)
    logger.info(f"초기 Era 상태 저장됨")
    
    # 10초 후 다시 체크 (실제로는 Era가 바뀌지 않겠지만 로직 테스트)
    logger.info("\n=== 10초 후 재체크 ===")
    await asyncio.sleep(10)
    
    payout_info2 = await payout_checker.check_all_payouts(node_names)
    transitions2 = await era_monitor.check_era_transition(payout_info2)
    
    if transitions2:
        logger.info(f"Era 전환 감지됨: {transitions2}")
    else:
        logger.info("Era 전환 없음")
    
    # 수동으로 Era 전환 시뮬레이션
    logger.info("\n=== Era 전환 시뮬레이션 ===")
    # 실제 환경에서는 Era가 변경될 때만 이런 상황이 발생
    if payout_info2.get('payout_checks'):
        for node, info in payout_info2['payout_checks'].items():
            if 'current_era' in info and not info.get('error'):
                # Era를 인위적으로 증가시켜 테스트
                info['current_era'] = info['current_era'] + 1
                logger.info(f"시뮬레이션: {node}의 Era를 {info['current_era']}로 변경")
                break
    
    transitions3 = await era_monitor.check_era_transition(payout_info2)
    if transitions3:
        logger.info(f"시뮬레이션된 Era 전환 감지: {transitions3}")

async def main():
    """메인 실행"""
    try:
        await test_live_era_detection()
    except KeyboardInterrupt:
        logger.info("테스트 중단됨")
    except Exception as e:
        logger.error(f"테스트 중 오류: {e}", exc_info=True)

if __name__ == "__main__":
    asyncio.run(main())