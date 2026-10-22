#!/bin/bash
# Builds Grover.app from the Swift package.
#   GROVER_SIGN_IDENTITY="Grover Dev" scripts/build-app.sh   # sign with a stable identity
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)

APP=Grover.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Grover" "$APP/Contents/MacOS/Grover"
cp Resources/Info.plist "$APP/Contents/Info.plist"
find Resources -maxdepth 1 -type f ! -name Info.plist -exec cp {} "$APP/Contents/Resources/" \;

IDENTITY="${GROVER_SIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" --identifier com.yav.grover "$APP"

echo "Built $(pwd)/$APP (signed with: ${IDENTITY})"
if [ "$IDENTITY" = "-" ]; then
    cat <<'NOTE'
Note: ad-hoc signing changes the app's identity on every build, so macOS may
forget the Accessibility permission that fn+Space needs. To avoid re-granting it,
create a self-signed code-signing certificate named "Grover Dev" in Keychain Access
(Certificate Assistant > Create a Certificate, type: Code Signing) and build with
  GROVER_SIGN_IDENTITY="Grover Dev" scripts/build-app.sh
NOTE
fi
