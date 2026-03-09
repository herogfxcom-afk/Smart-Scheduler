FROM python:3.11-slim

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy all backend files
COPY . .

# Expose port
EXPOSE 8080

# Start FastAPI with uvicorn
CMD uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}
