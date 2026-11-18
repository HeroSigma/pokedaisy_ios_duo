#!/bin/sh
# Builds the iPhone app's C side (ios/core: the companion, the session, mGBA) for arm64 iPhones and merges it into one
# static library, ios/build/lib/libpokedaisy_core.a, for the Xcode project (ios/project.yml). Needs a Mac with Xcode and
# CMake, and the mGBA submodule: git submodule update --init third_party/mgba
set -eu
here=$(cd "$(dirname "$0")" && pwd)
build="$here/build/core"
lib="$here/build/lib"
mkdir -p "$build" "$lib"
cmake -S "$here/core" -B "$build" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_BUILD_TYPE=Release
cmake --build "$build" --target pokedaisy_ios --config Release -j "$(sysctl -n hw.ncpu)"
mgba=$(find "$build" -name 'libmgba.a' | head -n 1)
core=$(find "$build" -name 'libpokedaisy_ios.a' | head -n 1)
if [ -z "$mgba" ] || [ -z "$core" ]; then
    echo "build_core.sh: libmgba.a or libpokedaisy_ios.a wasn't built" >&2
    exit 1
fi
libtool -static -o "$lib/libpokedaisy_core.a" "$core" "$mgba"
echo "built $lib/libpokedaisy_core.a"
