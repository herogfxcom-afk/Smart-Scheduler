import os
from cryptography.fernet import Fernet
from dotenv import load_dotenv

load_dotenv()

# ENCRYPTION_KEY must be a stable 32-byte base64 encoded string from .env
# To generate one: python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
ENCRYPTION_KEY = os.getenv("ENCRYPTION_KEY")

if not ENCRYPTION_KEY:
    raise RuntimeError("ENCRYPTION_KEY missing in .env! Security logic disabled to prevent data loss.")

cipher_suite = Fernet(ENCRYPTION_KEY.encode())
antiviral_key = None # Placeholder for potential expansion

def encrypt_token(token: str) -> str:
    """Encrypts a string (token) using AES-256 (Fernet)."""
    return cipher_suite.encrypt(token.encode()).decode()

def decrypt_token(encrypted_token: str) -> str:
    """Decrypts an encrypted string back to its original value."""
    return cipher_suite.decrypt(encrypted_token.encode()).decode()
