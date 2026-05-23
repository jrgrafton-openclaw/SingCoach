#!/usr/bin/env bash
# Build a debug SingCoach .app and install it on the connected iPhone.
#
# Why this exists:
#   - project.yml is the source of truth for signing (Automatic + Apple Development).
#   - `fastlane beta` mutates pbxproj to manual distribution signing for TestFlight,
#     and that edit persists. Without this script you'd have to flip signing back to
#     Automatic in the Xcode UI before each dev install.
#   - This script regenerates pbxproj from project.yml first → clean Dev signing,
#     then builds for the connected device and installs via devicectl.
#
# Usage: ./scripts/install-on-device.sh

set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"

# Step 1 — Regenerate project from project.yml to ensure clean Dev signing
echo "→ Regenerating project from project.yml…"
xcodegen generate >/dev/null

# Step 2 — Find the first connected iPhone (parse JSON for robustness — text output
# has terminal escape codes that break awk).
DEVICES_JSON=/tmp/singcoach-devices.json
xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null 2>&1
DEVICE_ID=$(python3 -c "
import json
with open('$DEVICES_JSON') as f:
    data = json.load(f)
for d in data.get('result', {}).get('devices', []):
    name = d.get('deviceProperties', {}).get('name', '')
    state = d.get('connectionProperties', {}).get('tunnelState', '')
    if 'iPhone' in name and state == 'connected':
        print(d['hardwareProperties']['udid'])
        break
")
if [[ -z "${DEVICE_ID}" ]]; then
    echo "❌ No connected iPhone detected. Plug in the phone and unlock it." >&2
    exit 1
fi
echo "→ Building for device ${DEVICE_ID}…"

# Step 3 — Build with Automatic provisioning (fetches/creates Dev profile if missing)
LOG=/tmp/xcodebuild-dev.log
if ! xcodebuild \
    -scheme SingCoach \
    -destination "platform=iOS,id=${DEVICE_ID}" \
    -configuration Debug \
    -allowProvisioningUpdates \
    build >"$LOG" 2>&1; then
    tail -50 "$LOG" >&2
    echo "❌ xcodebuild failed (full log: $LOG)" >&2
    exit 1
fi

# Step 4 — Locate the built .app and install
APP_PATH="$(ls -dt ~/Library/Developer/Xcode/DerivedData/SingCoach-*/Build/Products/Debug-iphoneos/SingCoach.app 2>/dev/null | head -1)"
if [[ -z "${APP_PATH:-}" || ! -d "$APP_PATH" ]]; then
    echo "❌ Built SingCoach.app not found in DerivedData" >&2
    exit 1
fi
echo "→ Installing $APP_PATH onto device…"
xcrun devicectl device install app --device "${DEVICE_ID}" "$APP_PATH"

echo "→ Launching com.jrgrafton.singcoach on device…"
xcrun devicectl device process launch --device "${DEVICE_ID}" com.jrgrafton.singcoach

echo "✅ Installed & launched SingCoach (Debug) on ${DEVICE_ID}"
