#!/usr/bin/env python3
# clear_token.py - 토큰 삭제 스크립트
import os
import sys

# ANSI 색상 코드
COLOR_RESET = "\x1B[0m"
COLOR_RED = "\x1B[31m"
COLOR_GREEN = "\x1B[32m"
COLOR_YELLOW = "\x1B[33m"

# 토큰 저장 경로
TOKEN_FILE_PATH = "/app/data/.auth_token"

def main():
    """토큰 삭제"""
    if os.path.exists(TOKEN_FILE_PATH):
        try:
            os.remove(TOKEN_FILE_PATH)
            print(f"{COLOR_GREEN}✓ 토큰이 삭제되었습니다.{COLOR_RESET}")
            print(f"{COLOR_YELLOW}다시 인증하려면: mauth{COLOR_RESET}")
        except Exception as e:
            print(f"{COLOR_RED}✗ 토큰 삭제 실패: {e}{COLOR_RESET}")
            return 1
    else:
        print(f"{COLOR_YELLOW}삭제할 토큰이 없습니다.{COLOR_RESET}")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())