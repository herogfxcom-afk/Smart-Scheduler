#!/bin/bash
# Exit on error
set -e

# Disable flutter analytics and root warnings
export FLUTTER_NO_ANALYTICS=1
export PUB_CACHE=$HOME/.pub-cache

if [ ! -d "flutter" ]; then
  echo "Cloning Flutter SDK..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1
fi

echo "Adding Flutter to PATH..."
export PATH="$PATH:`pwd`/flutter/bin"

# Initialize flutter without triggering root exit
flutter doctor
flutter config --enable-web

echo "Fetching dependencies..."
flutter pub get

echo "Building for Web..."
if [ -n "$API_URL" ]; then
  # Clean before build
flutter clean
flutter pub get

# Build web - DO NOT USE --wasm, it is experimental and fails on Vercel stable flutter
# We use the RailWay URL as a fallback if API_URL is not provided
flutter build web --release --dart-define=API_URL=https://smart-scheduler-production-2006.up.railway.app
fi
