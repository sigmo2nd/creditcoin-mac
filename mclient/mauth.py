#!/usr/bin/env python3
# mauth.py - Creditcoin 모니터링 인증 전용 스크립트
import asyncio
import logging
import os
import sys
import json
import getpass
import aiohttp
from pathlib import Path
from typing import Optional
import nest_asyncio

# asyncio 이벤트 루프 중첩 허용
nest_asyncio.apply()

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# ANSI 색상 코드
COLOR_RESET = "\x1B[0m"
COLOR_RED = "\x1B[31m"
COLOR_GREEN = "\x1B[32m"
COLOR_YELLOW = "\x1B[33m"
COLOR_BLUE = "\x1B[34m"
COLOR_CYAN = "\x1B[36m"

# 토큰 저장 경로
TOKEN_FILE_PATH = "/app/data/.auth_token"

async def handle_tty_authentication(auth_api_url: str, force_reauth: bool = False) -> Optional[str]:
    """TTY 모드에서 인증 처리 (토큰 확인 및 로그인)"""
    print("")
    print(f"{COLOR_YELLOW}====================================================={COLOR_RESET}")
    print(f"{COLOR_YELLOW}        Creditcoin 모니터링 서버 인증{COLOR_RESET}")
    print(f"{COLOR_YELLOW}====================================================={COLOR_RESET}")
    print("")
    
    # 강제 재인증 옵션 확인
    if force_reauth:
        print(f"{COLOR_YELLOW}강제 재인증 모드로 실행합니다.{COLOR_RESET}")
        if os.path.exists(TOKEN_FILE_PATH):
            try:
                os.remove(TOKEN_FILE_PATH)
                print(f"{COLOR_GREEN}기존 토큰을 삭제했습니다.{COLOR_RESET}")
            except Exception as e:
                logger.debug(f"토큰 삭제 오류: {e}")
        print("")
    
    # 기존 토큰 확인
    if os.path.exists(TOKEN_FILE_PATH) and not force_reauth:
        try:
            with open(TOKEN_FILE_PATH, 'r') as f:
                token = f.read().strip()
                if token:
                    print(f"{COLOR_GREEN}기존 인증 정보 확인:{COLOR_RESET}")
                    print(f"  토큰: {token[:20]}...")
                    print("")
                    
                    # 토큰 검증
                    print(f"{COLOR_BLUE}토큰 유효성 검증 중...{COLOR_RESET}")
                    is_valid = await verify_token(auth_api_url, token)
                    
                    if is_valid:
                        print(f"{COLOR_GREEN}✓ 인증 성공!{COLOR_RESET}")
                        print(f"{COLOR_GREEN}기존 토큰이 유효하여 재사용합니다.{COLOR_RESET}")
                        print("")
                        print(f"{COLOR_CYAN}재인증을 원하시면 다음 명령어를 사용하세요:{COLOR_RESET}")
                        print(f"{COLOR_BLUE}mauth --force{COLOR_RESET}")
                        print("")
                        return token
                    else:
                        print(f"{COLOR_RED}✗ 토큰이 만료되었거나 유효하지 않습니다.{COLOR_RESET}")
                        print(f"{COLOR_YELLOW}새로 로그인이 필요합니다.{COLOR_RESET}")
                        print("")
        except Exception as e:
            logger.debug(f"토큰 파일 읽기 오류: {e}")
    
    # URL 정보 출력
    from urllib.parse import urlparse
    parsed_url = urlparse(auth_api_url)
    print(f"{COLOR_BLUE}서버 정보:{COLOR_RESET}")
    print(f"  주소: {parsed_url.hostname}")
    print(f"  포트: {parsed_url.port}")
    print(f"  프로토콜: {parsed_url.scheme.upper()}")
    print("")
    
    # 로그인 시도
    max_attempts = 3
    for attempt in range(max_attempts):
        print(f"{COLOR_YELLOW}====================================================={COLOR_RESET}")
        print(f"{COLOR_YELLOW}로그인 [{attempt + 1}/{max_attempts}]{COLOR_RESET}")
        print(f"{COLOR_YELLOW}====================================================={COLOR_RESET}")
        print("")
        print(f"{COLOR_CYAN}💡 Tab 키로 다음 필드로 이동할 수 있습니다.{COLOR_RESET}")
        print("")
        
        # 사용자 입력 (prompt_toolkit 사용)
        try:
            # prompt_toolkit import
            try:
                from prompt_toolkit import prompt
                from prompt_toolkit.key_binding import KeyBindings
                from prompt_toolkit.keys import Keys
                
                # Tab 키 바인딩 설정
                bindings = KeyBindings()
                
                @bindings.add(Keys.Tab)
                def _(event):
                    # Tab을 누르면 현재 입력값을 유지하고 다음 필드로
                    event.app.exit(result=event.app.current_buffer.text)
                
                # prompt_toolkit에서는 ANSI 색상을 HTML 스타일로 변환해야 함
                from prompt_toolkit.formatted_text import HTML
                
                # 이메일 입력
                email = prompt(HTML('<ansicyan>이메일: </ansicyan>'), key_bindings=bindings).strip()
                if not email:
                    print(f"{COLOR_RED}이메일을 입력해주세요.{COLOR_RESET}")
                    continue
                
                # 비밀번호 입력
                password = prompt(HTML('<ansicyan>비밀번호: </ansicyan>'), is_password=True, key_bindings=bindings).strip()
                if not password:
                    print(f"{COLOR_RED}비밀번호를 입력해주세요.{COLOR_RESET}")
                    continue
                    
            except ImportError:
                # prompt_toolkit이 없으면 기본 input 사용
                print(f"{COLOR_YELLOW}주의: prompt_toolkit이 설치되지 않아 기본 입력 모드를 사용합니다.{COLOR_RESET}")
                print(f"{COLOR_YELLOW}한글 입력 시 백스페이스가 제대로 작동하지 않을 수 있습니다.{COLOR_RESET}")
                
                email = input(f"{COLOR_CYAN}이메일: {COLOR_RESET}")
                if not email:
                    print(f"{COLOR_RED}이메일을 입력해주세요.{COLOR_RESET}")
                    continue
                    
                password = getpass.getpass(f"{COLOR_CYAN}비밀번호: {COLOR_RESET}")
                if not password:
                    print(f"{COLOR_RED}비밀번호를 입력해주세요.{COLOR_RESET}")
                    continue
                    
        except (KeyboardInterrupt, EOFError):
            print(f"\n{COLOR_YELLOW}로그인이 취소되었습니다.{COLOR_RESET}")
            return None
        
        # 로그인 요청
        print("")
        print(f"{COLOR_BLUE}인증 서버에 연결 중...{COLOR_RESET}")
        token = await login_request(auth_api_url, email, password)
        
        if token:
            # 토큰 저장
            try:
                os.makedirs(os.path.dirname(TOKEN_FILE_PATH), exist_ok=True)
                with open(TOKEN_FILE_PATH, 'w') as f:
                    f.write(token)
                os.chmod(TOKEN_FILE_PATH, 0o600)  # 읽기 권한 제한
                print("")
                print(f"{COLOR_GREEN}====================================================={COLOR_RESET}")
                print(f"{COLOR_GREEN}✓ 인증 성공!{COLOR_RESET}")
                print(f"{COLOR_GREEN}====================================================={COLOR_RESET}")
                print("")
                print(f"{COLOR_GREEN}토큰이 안전하게 저장되었습니다.{COLOR_RESET}")
                print(f"  경로: {TOKEN_FILE_PATH}")
                print("")
                return token
            except Exception as e:
                logger.error(f"토큰 저장 실패: {e}")
                print(f"{COLOR_YELLOW}⚠️  토큰을 저장할 수 없지만 계속 진행합니다.{COLOR_RESET}")
                return token
        else:
            print("")
            print(f"{COLOR_RED}✗ 인증 실패{COLOR_RESET}")
            print(f"{COLOR_RED}이메일 또는 비밀번호를 확인하세요.{COLOR_RESET}")
            if attempt < max_attempts - 1:
                print("")
                print(f"{COLOR_YELLOW}다시 시도하려면 엔터를 누르세요...{COLOR_RESET}")
                input()
    
    print("")
    print(f"{COLOR_RED}====================================================={COLOR_RESET}")
    print(f"{COLOR_RED}최대 로그인 시도 횟수를 초과했습니다.{COLOR_RESET}")
    print(f"{COLOR_RED}====================================================={COLOR_RESET}")
    return None

async def verify_token(auth_api_url: str, token: str) -> bool:
    """토큰 유효성 검증"""
    try:
        # URL에서 /login/을 /verify/로 변경
        verify_url = auth_api_url.replace('/login/', '/verify/')
        
        # SSL 검증 설정 확인
        ssl_verify = os.getenv('SSL_VERIFY', 'true').lower() == 'true'
        logger.debug(f"SSL_VERIFY 환경변수: {os.getenv('SSL_VERIFY')}, ssl_verify: {ssl_verify}")
        
        # SSL 컨텍스트 생성
        if verify_url.startswith('https') and not ssl_verify:
            import ssl as ssl_module
            ssl_context = ssl_module.create_default_context()
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl_module.CERT_NONE
            connector = aiohttp.TCPConnector(ssl=ssl_context)
            logger.debug("SSL 인증서 검증 비활성화")
        else:
            connector = aiohttp.TCPConnector()
        
        async with aiohttp.ClientSession(connector=connector) as session:
            headers = {'Authorization': f'Token {token}'}
            async with session.get(verify_url, headers=headers) as response:
                return response.status == 200
    except Exception as e:
        logger.debug(f"토큰 검증 중 오류: {e}")
        return False

async def login_request(auth_api_url: str, email: str, password: str) -> Optional[str]:
    """로그인 요청"""
    try:
        # SSL 검증 설정 확인
        ssl_verify = os.getenv('SSL_VERIFY', 'true').lower() == 'true'
        
        # SSL 컨텍스트 생성
        if auth_api_url.startswith('https') and not ssl_verify:
            import ssl as ssl_module
            ssl_context = ssl_module.create_default_context()
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl_module.CERT_NONE
            connector = aiohttp.TCPConnector(ssl=ssl_context)
            logger.debug("SSL 인증서 검증 비활성화")
        else:
            connector = aiohttp.TCPConnector()
        
        async with aiohttp.ClientSession(connector=connector) as session:
            login_data = {
                'email': email,
                'password': password
            }
            
            async with session.post(auth_api_url, json=login_data) as response:
                if response.status == 200:
                    data = await response.json()
                    if data.get('success'):
                        return data.get('token')
                    else:
                        logger.debug(f"로그인 실패: {data.get('message', '알 수 없는 오류')}")
                        return None
                else:
                    logger.debug(f"로그인 실패: HTTP {response.status}")
                    return None
    except Exception as e:
        logger.error(f"로그인 요청 중 오류: {e}")
        return None

async def main():
    """메인 함수"""
    # 환경변수에서 서버 주소 읽기
    ws_host = os.getenv('WS_SERVER_HOST')
    
    if not ws_host:
        print(f"{COLOR_RED}오류: WS_SERVER_HOST가 설정되지 않았습니다.{COLOR_RESET}")
        return 1
    
    # 환경변수에서 AUTH_API_URL 사용 (없으면 기본값 생성)
    auth_api_url = os.getenv('AUTH_API_URL')
    if not auth_api_url:
        ws_port = os.getenv('WS_SERVER_PORT', '8080')
        ws_mode = os.getenv('WS_MODE', 'ws')
        protocol = 'https' if ws_mode == 'wss' else 'http'
        auth_api_url = f"{protocol}://{ws_host}:{ws_port}/api/auth/login/"
    else:
        # AUTH_API_URL이 /login/으로 끝나지 않으면 추가
        if not auth_api_url.endswith('/login/'):
            auth_api_url = auth_api_url.rstrip('/') + '/login/'
    
    # TTY 확인
    if not sys.stdin.isatty():
        print(f"{COLOR_RED}오류: 인증을 위해서는 대화형 터미널이 필요합니다.{COLOR_RESET}")
        print("docker run -it 옵션을 사용하거나 docker compose run을 사용하세요.")
        return 1
    
    # 명령줄 인자 확인
    force_reauth = "--force" in sys.argv or "-f" in sys.argv
    
    # 인증 처리
    token = await handle_tty_authentication(auth_api_url, force_reauth)
    
    if token:
        print(f"{COLOR_GREEN}====================================================={COLOR_RESET}")
        print(f"{COLOR_GREEN}모든 준비가 완료되었습니다!{COLOR_RESET}")
        print(f"{COLOR_GREEN}====================================================={COLOR_RESET}")
        print("")
        print(f"{COLOR_YELLOW}다음 명령어로 모니터링을 시작하세요:{COLOR_RESET}")
        print(f"{COLOR_BLUE}mcup{COLOR_RESET}")
        print("")
        print(f"{COLOR_CYAN}명령어가 작동하지 않으면:{COLOR_RESET}")
        print(f"{COLOR_BLUE}updatez{COLOR_RESET}")
        print("")
        return 0
    else:
        print("")
        print(f"{COLOR_RED}인증에 실패했습니다.{COLOR_RESET}")
        print(f"{COLOR_YELLOW}다시 시도하려면:{COLOR_RESET}")
        print(f"{COLOR_BLUE}mauth{COLOR_RESET}")
        print("")
        return 1

if __name__ == "__main__":
    try:
        exit_code = asyncio.run(main())
        sys.exit(exit_code)
    except KeyboardInterrupt:
        print(f"\n{COLOR_YELLOW}프로그램이 중단되었습니다.{COLOR_RESET}")
        sys.exit(0)