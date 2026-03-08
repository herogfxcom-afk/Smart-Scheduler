"""
This script triggers a redeploy on Railway using their GraphQL API.
Get your Railway token from: railway.com → Account Settings → Tokens
"""
import requests
import json

# Get token from railway CLI config
import os
import subprocess

# Get token from railway CLI
result = subprocess.run(["railway", "whoami"], capture_output=True, text=True)
print("Railway user:", result.stdout.strip())

# Try to get the token
token_result = subprocess.run(["railway", "auth", "token"], capture_output=True, text=True)
print("Token result:", token_result.stdout.strip(), token_result.stderr.strip())
