#!/bin/bash
# Build the project generated from project.yml (unsigned) to keep project.yml valid (used by CI).
set -euo pipefail
xcodebuild -project LiteKey.xcodeproj -scheme LiteKey -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build
