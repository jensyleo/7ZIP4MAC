#!/bin/zsh
# Rebuilds the patched lsar/unar shipped in App/Resources/Engine/ from the
# upstream sources. Needs Xcode and network access. Output: ./out/{lsar,unar}
set -euo pipefail
here="${0:A:h}"
cd "$here"
XAD_URL="https://github.com/MacPaw/XADMaster/archive/refs/tags/v1.10.7.tar.gz"
XAD_SHA="3d766dc1856d04a8fb6de9942a6220d754d0fa7eae635d5287e7b1cf794c4f45"
UD_URL="https://github.com/MacPaw/universal-detector/archive/refs/tags/1.1.tar.gz"
UD_SHA="8e8532111d0163628eb828a60d67b53133afad3f710b1967e69d3b8eee28a811"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
fetch() { curl -fsSL "$1" -o "$work/$3"; [[ "$(shasum -a 256 "$work/$3" | cut -d' ' -f1)" == "$2" ]] || { echo "checksum mismatch: $1"; exit 1; }; }
fetch "$XAD_URL" "$XAD_SHA" xad.tgz
fetch "$UD_URL" "$UD_SHA" ud.tgz
mkdir "$work/src" && tar xzf "$work/xad.tgz" -C "$work/src" && tar xzf "$work/ud.tgz" -C "$work/src"
mv "$work/src/universal-detector-1.1" "$work/src/UniversalDetector"   # XADMaster expects ../UniversalDetector
cd "$work/src/XADMaster-1.10.7"
patch -p1 < "$here/password-stdin.patch"
patch -p1 < "$here/build-xcode-libcxx.patch"
mkdir build
for target in XADMaster unar lsar; do
  xcodebuild -target "$target" -project XADMaster.xcodeproj SYMROOT="$PWD/build" \
    -configuration Release MACOSX_DEPLOYMENT_TARGET=26.0 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
done
mkdir -p "$here/out" && cp build/Release/lsar build/Release/unar "$here/out/"
echo "Built: $here/out/{lsar,unar}"
