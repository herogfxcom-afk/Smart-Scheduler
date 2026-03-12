import sys
import os

# Add the project root to the sys.path to allow imports like 'from main import app'
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from main import app
