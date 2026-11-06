#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build -c release --disable-sandbox --cache-path .build/cache
APP="$PWD/dist/CloudLens.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/CloudLens "$APP/Contents/MacOS/CloudLens"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CloudLens</string>
<key>CFBundleIdentifier</key><string>app.cloudlens.viewer</string>
<key>CFBundleName</key><string>CloudLens</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --sign "${CLOUDLENS_SIGN_IDENTITY:--}" --entitlements CloudLens.entitlements "$APP"
echo "Built: $APP"
