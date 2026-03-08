#!/bin/bash
# Exit on error
set -e

echo "Cloning Flutter SDK..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1

echo "Adding Flutter to PATH..."
export PATH="$PATH:`pwd`/flutter/bin"
flutter --version

echo "Fetching dependencies..."
flutter pub get

echo "Building for Web..."
if [ -n "$API_URL" ]; then
  flutter build web --release --no-tree-shake-icons --no-wasm-dry-run --dart-define=API_URL=$API_URL
else
  flutter build web --release --no-tree-shake-icons --no-wasm-dry-run
fi
