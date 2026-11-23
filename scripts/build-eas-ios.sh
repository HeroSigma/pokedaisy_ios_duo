#!/usr/bin/env bash
# Custom EAS Build: native SwiftUI + mGBA C core, unsigned IPA for Sideloadly.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== EAS native iOS build environment =="
uname -a
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version

if ! command -v cmake >/dev/null 2>&1; then
  echo "Installing CMake"
  brew install cmake
fi
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing XcodeGen"
  brew install xcodegen
fi

if [ ! -f third_party/mgba/CMakeLists.txt ]; then
  echo "Fetching mGBA submodule"
  git submodule update --init --depth 1 third_party/mgba
fi
test -f third_party/mgba/CMakeLists.txt || { echo "mGBA source missing" >&2; exit 1; }

echo "== Compile the arm64 C core =="
sh ios/build_core.sh

echo "== Generate Xcode project =="
xcodegen generate --spec ios/project.yml

echo "== Compile unsigned iPhone app =="
mkdir -p artifacts
xcodebuild -project ios/PokeDaisy.xcodeproj -scheme PokeDaisy \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$PWD/ios/build/eas-derived" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build > artifacts/xcodebuild.log 2>&1 || {
    grep -E "error:" artifacts/xcodebuild.log | head -60 || true
    tail -80 artifacts/xcodebuild.log || true
    exit 1
  }

echo "== Package unsigned IPA =="
app="$PWD/ios/build/eas-derived/Build/Products/Release-iphoneos/PokeDaisy.app"
test -d "$app"
mkdir -p artifacts/ipa/Payload
cp -R "$app" artifacts/ipa/Payload/
(cd artifacts/ipa && zip -qry ../PokeDaisy-iOS-unsigned.ipa Payload)
test -s artifacts/PokeDaisy-iOS-unsigned.ipa
ls -lh artifacts/PokeDaisy-iOS-unsigned.ipa
echo "Unsigned IPA ready; Sideloadly will sign it for the user's device."
