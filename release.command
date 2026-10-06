#!/bin/zsh
set -eu
cd "${0:A:h}"
./build.command
TASK_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' 'NAS Icon Bridge.app/Contents/Info.plist')
TASK_ARCH=$(uname -m)
TASK_STAGE=$(mktemp -d "${TMPDIR:-/tmp}/NASIconBridge-release.XXXXXX")
trap 'rm -rf "$TASK_STAGE"' EXIT
mkdir -p "$TASK_STAGE/app/NASIconBridge/backup" "$TASK_STAGE/source/NASIconBridge" "$TASK_STAGE/packages" dist
/usr/bin/ditto --norsrc --noextattr --noacl 'NAS Icon Bridge.app' "$TASK_STAGE/app/NASIconBridge/NAS Icon Bridge.app"
cp README.md TECHNICAL.md LICENSE "$TASK_STAGE/app/NASIconBridge/"
for TASK_ITEM in Source Assets Resources README.md TECHNICAL.md LICENSE RELEASE.md CHANGELOG.md build.command release.command .gitignore; do
    /usr/bin/ditto --norsrc --noextattr --noacl "$TASK_ITEM" "$TASK_STAGE/source/NASIconBridge/$TASK_ITEM"
done
/usr/bin/find "$TASK_STAGE/app" "$TASK_STAGE/source" -name .DS_Store -delete
TASK_APP_ZIP="NASIconBridge-${TASK_VERSION}-macOS-${TASK_ARCH}.zip"
TASK_SOURCE_ZIP="NASIconBridge-${TASK_VERSION}-source.zip"
/usr/bin/ditto -c -k --norsrc --noextattr --noacl --keepParent "$TASK_STAGE/app/NASIconBridge" "$TASK_STAGE/packages/$TASK_APP_ZIP"
/usr/bin/ditto -c -k --norsrc --noextattr --noacl --keepParent "$TASK_STAGE/source/NASIconBridge" "$TASK_STAGE/packages/$TASK_SOURCE_ZIP"
(cd "$TASK_STAGE/packages" && shasum -a 256 "$TASK_APP_ZIP" "$TASK_SOURCE_ZIP" > SHA256SUMS.txt)
# Replace each output with a newly created file so old archive attributes cannot survive.
for TASK_FILE in "$TASK_APP_ZIP" "$TASK_SOURCE_ZIP" SHA256SUMS.txt; do
    TASK_OUTPUT=$(mktemp "dist/.release.XXXXXX")
    cat "$TASK_STAGE/packages/$TASK_FILE" > "$TASK_OUTPUT"
    chmod 644 "$TASK_OUTPUT"
    mv -f "$TASK_OUTPUT" "dist/$TASK_FILE"
done
print "Release: dist/$TASK_APP_ZIP"
print "Source: dist/$TASK_SOURCE_ZIP"
print "Checksums: dist/SHA256SUMS.txt"
