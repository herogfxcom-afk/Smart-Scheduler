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
flutter config --no-analytics > /dev/null

echo "Fetching dependencies..."
flutter pub get

echo "Building for Web..."
if [ -n "$API_URL" ]; then
  flutter build web --release --no-tree-shake-icons --verbose --dart-define=API_URL=$API_URL
else
  flutter build web --release --no-tree-shake-icons --verbose
fi
