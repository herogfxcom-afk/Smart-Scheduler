#!/bin/bash
# Apply database migrations
alembic upgrade head

# Start the application
uvicorn main:app --host 0.0.0.0 --port $PORT
