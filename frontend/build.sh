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
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run
