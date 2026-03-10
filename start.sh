#!/bin/bash
# Apply database migrations
# We use 'stamp head' ONLY ONCE to sync existing tables with Alembic
alembic stamp head || true
alembic upgrade head

# Start the application
uvicorn main:app --host 0.0.0.0 --port $PORT
