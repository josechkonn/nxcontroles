#!/bin/zsh
# Builds "NX Controles.app" (the keyboard map editor for nxnative's Mac games) next to this script, or in the folder given as $1.
# Needs the Xcode command line tools (swiftc). Usage: ./build.sh [output folder]
set -euo pipefail
here=${0:A:h}
out=${1:-$here}
app="$out/NX Controles.app"
rm -rf "$app"; mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -O -parse-as-library -target arm64-apple-macos14 -o "$app/Contents/MacOS/NXControles" "$here"/Sources/*.swift
[[ -f "$here/AppIcon.icns" ]] && cp "$here/AppIcon.icns" "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>NX Controles</string>
  <key>CFBundleDisplayName</key><string>NX Controles</string>
  <key>CFBundleIdentifier</key><string>com.nxnative.controles</string>
  <key>CFBundleExecutable</key><string>NXControles</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>NX Controles usa Bluetooth para enlazar tus teléfonos y mandos inalámbricos.</string>
  <key>NSBluetoothPeripheralUsageDescription</key><string>NX Controles usa Bluetooth para enlazar tus teléfonos y mandos inalámbricos.</string>
  <key>NSLocalNetworkUsageDescription</key><string>NX Controles usa la red local para conectar mandos móviles con NX Remote.</string>
</dict></plist>
EOF
codesign --force --sign - "$app"
echo "OK: $app"

if [[ -d "/Volumes/Externo/Applications" && "$out" != "/Volumes/Externo/Applications" ]]; then
  rm -rf "/Volumes/Externo/Applications/NX Controles.app"
  cp -R "$app" "/Volumes/Externo/Applications/"
  codesign --force --sign - "/Volumes/Externo/Applications/NX Controles.app"
  echo "Synced to /Volumes/Externo/Applications/NX Controles.app"
fi
