# substrate_utils.py
import hashlib
import binascii
from typing import Optional

def blake2_128_concat(data: bytes) -> bytes:
    """Blake2 128-bit hash with concatenated data"""
    h = hashlib.blake2b(data, digest_size=16)
    return h.digest() + data

def twox_128(data: bytes) -> bytes:
    """Two XX 128-bit hash"""
    # 간단한 구현 (실제로는 xxhash 사용)
    h1 = hashlib.blake2b(data, digest_size=8, key=b'0')
    h2 = hashlib.blake2b(data, digest_size=8, key=b'1')
    return h1.digest() + h2.digest()

def decode_hex_string(hex_str: str) -> str:
    """Hex 문자열을 디코딩"""
    if hex_str.startswith('0x'):
        hex_str = hex_str[2:]
    try:
        return binascii.unhexlify(hex_str).decode('utf-8', errors='ignore')
    except:
        return hex_str

def encode_account_id(account_hex: str) -> str:
    """AccountId를 SS58 형식으로 인코딩 (간단 버전)"""
    # Creditcoin은 SS58 prefix 42를 사용할 가능성이 높음
    # 실제 구현은 더 복잡하지만 여기서는 hex 그대로 반환
    if account_hex.startswith('0x'):
        return account_hex
    return '0x' + account_hex

def extract_validator_from_storage_key(storage_key: str, prefix_length: int = 96) -> Optional[str]:
    """스토리지 키에서 검증인 AccountId 추출"""
    try:
        # 0x 제거
        if storage_key.startswith('0x'):
            storage_key = storage_key[2:]
        
        # prefix와 hash 제거하고 AccountId 추출
        # 일반적으로 AccountId는 32 bytes (64 hex chars)
        account_hex = storage_key[prefix_length:prefix_length+64]
        
        if len(account_hex) == 64:
            return '0x' + account_hex
        
        return None
    except:
        return None