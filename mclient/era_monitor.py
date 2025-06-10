# era_monitor.py
import logging
import json
import time
from typing import Dict, Any, Optional
from command_handler import CommandHandler

logger = logging.getLogger(__name__)

class EraMonitor:
    """Era 전환 감지 및 검증인 활성화 모니터링"""
    
    def __init__(self, websocket_client=None):
        self.previous_era = {}  # {node_name: era_number}
        self.websocket_client = websocket_client
        self.command_handler = CommandHandler()
        self.known_validators = {}  # {node_name: validator_account} - 이미 알려진 검증인
        
    async def check_era_transition(self, payout_info: Dict[str, Any]) -> Dict[str, Any]:
        """Era 전환 감지 및 모든 노드의 검증인 상태 체크"""
        transitions = {}
        payout_checks = payout_info.get('payout_checks', {})
        
        for node_name, info in payout_checks.items():
            current_era = info.get('current_era')
            if current_era is None:
                continue
                
            # 이전 Era와 비교
            if node_name in self.previous_era:
                previous = self.previous_era[node_name]
                if current_era > previous:
                    logger.info(f"{node_name}: Era 전환 감지 {previous} → {current_era}")
                    transitions[node_name] = {
                        'previous_era': previous,
                        'current_era': current_era
                    }
                    
                    # Era 변경 시 모든 노드의 검증인 상태 체크
                    await self._check_validator_status(node_name, current_era)
            
            # Era 업데이트
            self.previous_era[node_name] = current_era
        
        return transitions
    
    async def _check_validator_status(self, node_name: str, current_era: int):
        """노드의 검증인 상태 체크"""
        try:
            logger.info(f"{node_name}: Era {current_era} - 검증인 상태 확인 중...")
            
            # find_validator 명령 실행 (로그에서 먼저 빠르게 확인)
            command_data = {
                'command': 'find_validator',
                'target': node_name,
                'params': {
                    'deep_search': False  # 로그만 확인 (빠름)
                }
            }
            
            result = await self.command_handler.handle_command(command_data)
            
            if result['data']['status'] == 'completed':
                validator_data = result['data']['result']
                validator_account = validator_data.get('validator_account')
                
                # 새로운 검증인 발견
                if validator_account and validator_account != self.known_validators.get(node_name):
                    previous_validator = self.known_validators.get(node_name)
                    
                    if previous_validator:
                        logger.info(f"{node_name}: 검증인 변경 감지! {previous_validator} → {validator_account}")
                        event_type = "validator_changed"
                    else:
                        logger.info(f"{node_name}: 새 검증인 활성화! Account: {validator_account}")
                        event_type = "validator_activated"
                    
                    # 알려진 검증인 목록 업데이트
                    self.known_validators[node_name] = validator_account
                    
                    # 서버에 알림 전송
                    if self.websocket_client:
                        notification = {
                            "type": event_type,
                            "data": {
                                "node": node_name,
                                "era": current_era,
                                "validator_account": validator_account,
                                "previous_validator": previous_validator,
                                "is_authority": validator_data.get('is_authority', False),
                                "timestamp": int(time.time() * 1000)
                            }
                        }
                        
                        try:
                            await self.websocket_client.send_message(json.dumps(notification))
                            logger.info(f"검증인 상태 알림 전송 완료: {node_name}")
                        except Exception as e:
                            logger.error(f"검증인 상태 알림 전송 실패: {e}")
                
                # 검증인이 없어진 경우
                elif not validator_account and node_name in self.known_validators:
                    logger.info(f"{node_name}: 검증인 비활성화 감지")
                    previous_validator = self.known_validators.pop(node_name)
                    
                    if self.websocket_client:
                        notification = {
                            "type": "validator_deactivated",
                            "data": {
                                "node": node_name,
                                "era": current_era,
                                "previous_validator": previous_validator,
                                "timestamp": int(time.time() * 1000)
                            }
                        }
                        
                        try:
                            await self.websocket_client.send_message(json.dumps(notification))
                        except Exception as e:
                            logger.error(f"검증인 비활성화 알림 전송 실패: {e}")
                            
        except Exception as e:
            logger.error(f"{node_name}: 검증인 상태 체크 중 오류: {e}")