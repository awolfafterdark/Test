#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
output_root="${1:-$project_root/dist}"
framework="$output_root/PickerPatcherEmbedded.framework"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
compiler="$(xcrun --sdk iphoneos --find clang)"
mkdir -p "$framework"
"$compiler" -arch arm64 -miphoneos-version-min=15.0 -isysroot "$sdk" \
  -fobjc-arc -fmodules -O2 -Wall -Wextra -dynamiclib \
  -install_name '@rpath/PickerPatcherEmbedded.framework/PickerPatcherEmbedded' \
  -framework Foundation -framework UIKit -framework UniformTypeIdentifiers -framework ImageIO -framework AVFoundation \
  "$project_root/Core/PickerPatcher.m" -o "$framework/PickerPatcherEmbedded"
cp "$project_root/Embedded/Info.plist" "$framework/Info.plist"
echo "Built $framework"
