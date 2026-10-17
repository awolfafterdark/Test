#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
output_root="${1:-$project_root/dist}"
framework="$output_root/PickerPatcherEmbedded.framework"
sdk_name="${PP_SDK:-iphoneos}"
sdk="$(xcrun --sdk "$sdk_name" --show-sdk-path)"
if [ "$sdk_name" = iphonesimulator ]; then
  architecture="$(uname -m)"
  target="${architecture}-apple-ios15.0-simulator"
else
  architecture=arm64
  target=arm64-apple-ios15.0
fi
compiler="$(xcrun --sdk "$sdk_name" --find clang)"
mkdir -p "$framework"
"$compiler" -arch "$architecture" -target "$target" -isysroot "$sdk" \
  -fobjc-arc -fmodules -O2 -Wall -Wextra -dynamiclib \
  -install_name '@rpath/PickerPatcherEmbedded.framework/PickerPatcherEmbedded' \
  -framework Foundation -framework UIKit -framework UniformTypeIdentifiers -framework ImageIO -framework AVFoundation -framework PhotosUI -framework WebKit \
  "$project_root/Core/PickerPatcher.m" -o "$framework/PickerPatcherEmbedded"
cp "$project_root/Embedded/Info.plist" "$framework/Info.plist"
echo "Built $framework"
