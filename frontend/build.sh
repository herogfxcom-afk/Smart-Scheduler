#!/bin/bash
# Exit on error
set -e

# Disable flutter analytics and root warnings
export FLUTTER_NO_ANALYTICS=1
export PUB_CACHE=$HOME/.pub-cache

# Fix for "dubious ownership" in some CI environments
git config --global --add safe.directory "*" || true

if [ ! -d "flutter" ]; then
  echo "Cloning Flutter SDK..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1
fi

echo "Adding Flutter to PATH..."
export PATH="$PATH:`pwd`/flutter/bin"

# Initialize flutter without triggering root exit
# Use || true to prevent non-zero exit codes from doctor in CI
flutter doctor || true
flutter config --no-analytics
flutter config --enable-web

echo "Fetching dependencies..."
flutter pub get

# Clean before build to avoid cache issues
flutter clean || true
flutter pub get

echo "Building for Web..."
# Always build. If API_URL is provided by Vercel environment, use it. 
# Otherwise, use the production fallback.
if [ -n "$API_URL" ]; then
  echo "Using environment API_URL: $API_URL"
  flutter build web --release --no-tree-shake-icons --verbose --dart-define=API_URL=$API_URL
else
  echo "Using fallback production API_URL"
  flutter build web --release --no-tree-shake-icons --verbose --dart-define=API_URL=https://smart-scheduler-production-2006.up.railway.app
fi
