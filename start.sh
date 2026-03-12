#!/bin/bash
# Apply database migrations
# We use 'stamp head' ONLY ONCE to sync existing tables with Alembic
alembic stamp head || true
alembic upgrade head
if [ $? -ne 0 ]; then
  echo "❌ Database migration failed! Aborting startup."
  exit 1
fi

# Start the application
uvicorn main:app --host 0.0.0.0 --port $PORT
