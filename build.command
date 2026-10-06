#!/bin/zsh
set -eu
cd "${0:A:h}"
APP="$PWD/NAS Icon Bridge.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
TASK_CACHE=${NAS_ICON_BUILD_CACHE:-$(mktemp -d "${TMPDIR:-/tmp}/NASIconBridge-build.XXXXXX")}
if [[ -z "${NAS_ICON_BUILD_CACHE:-}" ]]; then trap 'rm -rf "$TASK_CACHE"' EXIT; fi
mkdir -p "$TASK_CACHE"
xcrun swiftc -module-cache-path "$TASK_CACHE" -swift-version 5 -O -target "$(uname -m)-apple-macosx13.0" Source/Localization.swift Source/Engine.swift Source/App.swift Source/SelfTest.swift Source/main.swift -o "$APP/Contents/MacOS/NASIconBridge" -framework AppKit -framework SwiftUI
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Translations.json "$APP/Contents/Resources/Translations.json"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>NASIconBridge</string>
<key>CFBundleIdentifier</key><string>local.kevin.NASIconBridge</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleName</key><string>NAS Icon Bridge</string>
<key>CFBundleDisplayName</key><string>NAS Icon Bridge</string>
<key>CFBundleVersion</key><string>14</string>
<key>CFBundleShortVersionString</key><string>1.0.1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 SPARKY. Created by Kevin. Home use only. No commercial use.</string>
<key>CFBundleDevelopmentRegion</key><string>zh-Hant</string>
<key>CFBundleLocalizations</key><array><string>zh-Hant</string><string>en</string></array>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
print "App 已建立：$APP"
