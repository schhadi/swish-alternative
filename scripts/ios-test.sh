#!/usr/bin/env bash
# Run the iOS unit and UI tests on a simulator. Same command CI uses. Usage: scripts/ios-test.sh ["iPhone 16"]
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${1:-iPhone 16}"
xcodebuild test \
  -project ios/QuidApp.xcodeproj \
  -scheme QuidApp \
  -destination "platform=iOS Simulator,name=${DEVICE}" \
  CODE_SIGNING_ALLOWED=NO
