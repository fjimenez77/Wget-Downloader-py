#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p ../dist
dist="$(cd ../dist && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
app="$stage/Wget Downloader.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
iconset="$stage/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
xcrun swiftc -parse-as-library -O -target arm64-apple-macos13.0 \
  -module-cache-path "$stage/modules" Downloader.swift -o "$app/Contents/MacOS/Downloader"
vendor=vendor/libxls
xcrun clang -O2 -target arm64-apple-macos13.0 -I"$vendor" -I"$vendor/include" \
  ReadLegacyExcel.c "$vendor"/src/*.c -liconv -o "$app/Contents/MacOS/ReadLegacyExcel"
cp "$vendor/LICENSE" "$app/Contents/Resources/libxls-LICENSE"
cp ../LICENSE ../downloads_template.xlsx "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.fjimenez77.wget-downloader</string>
<key>CFBundleName</key><string>Wget Downloader</string>
<key>CFBundleExecutable</key><string>Downloader</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.6.1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleVersion</key><string>11</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Felix J. (@fjimenez77) and contributors</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict>
  <key>NSExceptionDomains</key><dict>
    <key>ip-api.com</key><dict><key>NSExceptionAllowsInsecureHTTPLoads</key><true/></dict>
  </dict>
</dict>
</dict></plist>
PLIST
codesign --force --sign - "$app/Contents/MacOS/ReadLegacyExcel"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
mkdir "$stage/image"
cp ../LICENSE "$stage/image/Apache-2.0 License.txt"
cp "$vendor/LICENSE" "$stage/image/libxls BSD-2-Clause License.txt"
cat > "$stage/image/About Wget Downloader.txt" <<'CREDITS'
Wget Downloader for macOS

Created by Felix J. (@fjimenez77) and contributors.
Copyright © 2026 Felix J. (@fjimenez77) and contributors.

Wget Downloader is licensed under the Apache License, Version 2.0.
The bundled libxls reader is licensed under the BSD 2-Clause License.
Both full license texts are included on this disk image.

Open Wget Downloader on GitHub.webloc to visit the original repository.
CREDITS
cat > "$stage/image/Wget Downloader on GitHub.webloc" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>URL</key><string>https://github.com/fjimenez77/Wget-Downloader-py</string>
</dict></plist>
PLIST
mv "$app" "$stage/image/"
ln -s /Applications "$stage/image/Applications"
hdiutil create -ov -volname "Wget Downloader" -srcfolder "$stage/image" -format UDZO "$dist/Wget Downloader.dmg"
hdiutil verify "$dist/Wget Downloader.dmg"
