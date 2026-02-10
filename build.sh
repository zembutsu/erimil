#!/bin/bash
# Erimil build script
# Usage: ./build.sh [build|clean|run]
set -e
cd "$(dirname "$0")"

PROJECT="./Erimil/Erimil.xcodeproj"
SCHEME="Erimil"

case "${1:-build}" in
  build)
    echo "🔨 Building..."
    xcodebuild build -project "$PROJECT" -scheme "$SCHEME" 2>&1 | tail -3
    ;;
  clean)
    echo "🧹 Clean & Build..."
    xcodebuild clean build -project "$PROJECT" -scheme "$SCHEME" 2>&1 | tail -3
    ;;
  run)
    echo "🚀 Build & Run..."
    xcodebuild build -project "$PROJECT" -scheme "$SCHEME" 2>&1 | tail -3
    open "$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null | grep -m1 ' BUILT_PRODUCTS_DIR' | awk '{print $3}')/Erimil.app"
    ;;
  *)
    echo "Usage: $0 [build|clean|run]"
    echo "  build  Incremental build (default)"
    echo "  clean  Clean & rebuild (use when changes don't take effect)"
    echo "  run    Build & launch app"
    exit 1
    ;;
esac
