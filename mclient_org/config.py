# 컨테이너에 접속
docker exec -it mclient bash

# config.py 파일 완전히 새로 작성
cat > /app/config.py << 'EOF'
import os
from pydantic_settings import BaseSettings
from pydantic import Field
from typing import Optional

class Settings(BaseSettings):
    # 기본 설정 (환경 변수에서 M_ 접두사를 사용하여 충돌 방지)
    SERVER_ID: str = Field(default="server1")
    NODE_NAMES: str = Field(default="node,3node")
    MONITOR_INTERVAL: int = Field(default=5)
    
    # WebSocket 설정
    WS_MODE: str = Field(default="auto")  # auto, ws, wss, wss_internal, custom
    WS_SERVER_URL: Optional[str] = Field(default=None)
    WS_SERVER_HOST: str = Field(default="localhost")  # 새로 추가된 서버 호스트 설정
    
    # Docker 설정
    CREDITCOIN_DIR: str = Field(default=os.path.expanduser("~/creditcoin-mac"))
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        env_prefix = "M_"  # 모든 환경 변수에 M_ 접두사 사용

# 싱글톤 설정 인스턴스
settings = Settings()

# 설정 확인용 함수
def print_settings():
    print(f"Server ID: {settings.SERVER_ID}")
    print(f"Node Names: {settings.NODE_NAMES}")
    print(f"Monitor Interval: {settings.MONITOR_INTERVAL}")
    print(f"WebSocket Mode: {settings.WS_MODE}")
    print(f"WebSocket URL: {settings.WS_SERVER_URL}")
    print(f"WebSocket Host: {settings.WS_SERVER_HOST}")
    print(f"Creditcoin Directory: {settings.CREDITCOIN_DIR}")

# WebSocket URL 결정 함수
def get_websocket_url():
    # 커스텀 모드에서 설정된 URL 사용
    if settings.WS_MODE == "custom" and settings.WS_SERVER_URL:
        return settings.WS_SERVER_URL
    
    # 환경 변수에서 설정된 서버 호스트 사용
    server_host = settings.WS_SERVER_HOST
    
    # 기본 URL 설정 (환경 변수 서버 호스트 사용)
    base_urls = {
        "ws": f"ws://{server_host}:8080/ws",
        "wss": f"wss://{server_host}:8443/ws",
        "wss_internal": f"wss://{server_host}:8443/ws"
    }
    
    # auto 모드인 경우 wss -> wss_internal -> ws 순으로 시도
    if settings.WS_MODE == "auto":
        return "auto"  # 자동 연결 로직은 websocket_client에서 구현
    
    # 모드에 해당하는 URL 반환 (없으면 ws 모드 기본값 사용)
    return base_urls.get(settings.WS_MODE, base_urls["ws"])
EOF

# 캐시 제거
rm -rf /app/__pycache__

# 컨테이너 나가기
exit
