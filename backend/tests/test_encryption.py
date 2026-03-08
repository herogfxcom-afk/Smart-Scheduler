import pytest
from backend.encryption import encrypt_token, decrypt_token

def test_encryption_decryption():
    test_token = "ya29.a0AfH6SMC..."
    encrypted = encrypt_token(test_token)
    assert encrypted != test_token
    assert len(encrypted) > len(test_token)
    
    decrypted = decrypt_token(encrypted)
    assert decrypted == test_token

def test_different_tokens():
    token1 = "token1"
    token2 = "token2"
    assert encrypt_token(token1) != encrypt_token(token2)
