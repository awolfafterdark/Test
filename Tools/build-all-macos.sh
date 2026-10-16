#!/usr/bin/env bash
# Complete local macOS build: rootless tweak .deb + on-device TrollStore .ipa.
# TARGET_BUNDLE_IDS, APP_DISPLAY_NAME, and ICON_JPG_URL are optional inputs.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
command -v xcodebuild >/dev/null || { echo 'Full Xcode is required.' >&2; exit 1; }
command -v brew >/dev/null || { echo 'Homebrew is required.' >&2; exit 1; }
for formula in make dpkg ldid xcodegen; do
  if ! brew list --versions "$formula" >/dev/null 2>&1; then brew install "$formula"; fi
done
export PATH="$(brew --prefix make)/libexec/gnubin:$PATH"

theos="$root/.build/theos"
if [ ! -d "$theos/.git" ]; then
  mkdir -p "$root/.build"
  git clone https://github.com/theos/theos.git "$theos"
fi
git -C "$theos" fetch origin 304e0799973e8145f32e4ca2de6c747a84b758ce
git -C "$theos" checkout --detach 304e0799973e8145f32e4ca2de6c747a84b758ce
git -C "$theos" submodule update --init --recursive
export THEOS="$theos"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
version="$(xcrun --sdk iphoneos --show-sdk-version)"
mkdir -p "$theos/sdks"
ln -sfn "$sdk" "$theos/sdks/iPhoneOS${version}.sdk"

original_filter="$(mktemp)"
cp PickerPatcher.plist "$original_filter"
restore_filter() { cp "$original_filter" PickerPatcher.plist; rm -f "$original_filter"; }
trap restore_filter EXIT
python3 configure-target.py "${TARGET_BUNDLE_IDS:-dev.pickerpatcher.demo}"
gmake clean package FINALPACKAGE=1
mkdir -p dist
cp packages/*.deb dist/
bash Tools/build-embedded.sh "$root/dist"
xcrun clang -O2 -Wall -Wextra -DPP_STANDALONE Core/MachOInject.c -o dist/pp-inject
python3 Tests/test_macho_inject.py

original_plist="$(mktemp)"
cp PatcherApp/Info.plist "$original_plist"
restore_sources() {
  cp "$original_plist" PatcherApp/Info.plist
  rm -f "$original_plist"
  restore_filter
}
trap restore_sources EXIT
python3 Tools/configure_app.py "${APP_DISPLAY_NAME:-PickerPatcher}"
if [ -n "${ICON_JPG_URL:-}" ]; then
  curl --fail --location --proto '=https' --proto-redir '=https' \
    --max-time 90 --max-filesize 10000000 "$ICON_JPG_URL" -o "$root/.build/custom-icon.jpg"
  sips -g format "$root/.build/custom-icon.jpg" | grep -qi 'format: jpeg'
  swift Tools/make_app_icon.swift "$root/.build/custom-icon.jpg"
else
  swift Tools/make_app_icon.swift
fi

mkdir -p PatcherApp/Resources
(cd dist && ditto -c -k --keepParent PickerPatcherEmbedded.framework ../PatcherApp/Resources/Payload.zip)
cp Core/MachOInject.c Core/MachOInject.h PatcherApp/Sources/
(cd PatcherApp && xcodegen generate --spec project.yml)
xcodebuild -project PatcherApp/PickerPatcherApp.xcodeproj -scheme PickerPatcherApp \
  -configuration Release -sdk iphoneos -derivedDataPath "$root/.build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO build
app="$root/.build/DerivedData/Build/Products/Release-iphoneos/PickerPatcherApp.app"
test -f "$app/PickerPatcherApp"
test -f "$app/Payload.zip"
test -f "$app/Assets.car"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict "$app"
package="$root/.build/ipa/Payload"
mkdir -p "$package"
rm -rf "$package/PickerPatcherApp.app"
cp -R "$app" "$package/"
(cd "$root/.build/ipa" && ditto -c -k --keepParent Payload "$root/dist/PickerPatcherApp-TrollStore.ipa")
unzip -t "$root/dist/PickerPatcherApp-TrollStore.ipa" >/dev/null
echo "Built $root/dist/PickerPatcherApp-TrollStore.ipa and rootless .deb in $root/dist"
