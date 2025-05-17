#!/usr/bin/env python3
import os
from pydantic_settings import BaseSettings
from pydantic import Field
from typing import Optional

class Settings(BaseSettings):
    # 기본 설정
    SERVER_ID: str = Field(default="server1")
    NODE_NAMES: str = Field(default="node,3node")
    MONITOR_INTERVAL: int = Field(default=5)
    
    # WebSocket 설정
    WS_MODE: str = Field(default="auto")  # auto, ws, wss, wss_internal, custom
    WS_SERVER_URL: Optional[str] = Field(default=None)
    WS_SERVER_HOST: str = Field(default="192.168.0.24")  # 서버 호스트
    WS_PORT_WS: int = Field(default=8080)  # WS 포트
    WS_PORT_WSS: int = Field(default=8443)  # WSS 포트
    
    # Docker 설정
    CREDITCOIN_DIR: str = Field(default=os.path.expanduser("~/creditcoin-mac"))
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        # 환경 변수 접두사 없애서 직접 사용
        env_prefix = ""

# 싱글톤 설정 인스턴스
settings = Settings()

# 설정 확인용 함수
def print_settings():
    print(f"=== 현재 설정 ===")
    print(f"Server ID: {settings.SERVER_ID}")
    print(f"Node Names: {settings.NODE_NAMES}")
    print(f"Monitor Interval: {settings.MONITOR_INTERVAL}초")
    print(f"WebSocket 모드: {settings.WS_MODE}")
    
    if settings.WS_MODE == "custom" and settings.WS_SERVER_URL:
        print(f"WebSocket URL: {settings.WS_SERVER_URL} (커스텀)")
    else:
        print(f"WebSocket 호스트: {settings.WS_SERVER_HOST}")
        print(f"WebSocket 포트(WS): {settings.WS_PORT_WS}")
        print(f"WebSocket 포트(WSS): {settings.WS_PORT_WSS}")
    
    print(f"Creditcoin 디렉토리: {settings.CREDITCOIN_DIR}")
    print(f"================")

# WebSocket URL 결정 함수
def get_websocket_url():
    """설정에 따라 WebSocket URL 결정"""
    # 1. 커스텀 모드에서 명시적으로 설정된 URL 사용
    if settings.WS_MODE == "custom" and settings.WS_SERVER_URL:
        return settings.WS_SERVER_URL
    
    # 2. 기본 URL 설정 (설정값으로부터 동적 생성)
    base_urls = {
        "ws": f"ws://{settings.WS_SERVER_HOST}:{settings.WS_PORT_WS}/ws",
        "wss": f"wss://{settings.WS_SERVER_HOST}:{settings.WS_PORT_WSS}/ws",
        "wss_internal": f"wss://{settings.WS_SERVER_HOST}:{settings.WS_PORT_WSS}/ws"
    }
    
    # 3. auto 모드인 경우 자동 연결 로직 사용
    if settings.WS_MODE == "auto":
        return "auto"  # 자동 연결 로직은 websocket_client에서 구현
    
    # 4. 모드에 해당하는 URL 반환 (없으면 ws 모드 기본값 사용)
    url = base_urls.get(settings.WS_MODE, base_urls["ws"])
    return url
