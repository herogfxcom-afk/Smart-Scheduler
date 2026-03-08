FROM python:3.10-slim

# Install dependencies for Flutter
RUN apt-get update && apt-get install -y \
    git \
    curl \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the entire frontend directory
COPY . .

# Ensure build.sh is executable
RUN chmod +x build.sh

# Run the build script
# We expect API_URL to be passed as an environment variable during build if possible,
# but Flutter web can also read it at runtime if we inject it or use dart-define at build time.
# In Railway, we'll use the API_URL env var during the build.
RUN ./build.sh

# Expose the port (Railway uses 8080 by default)
EXPOSE 8080

# Command to serve the static files
CMD ["python3", "-m", "http.server", "8080", "--directory", "build/web"]
