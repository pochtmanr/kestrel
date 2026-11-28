#!/usr/bin/env bash
# Raw App Store screenshots from the simulators, straight into the screenshot studio.
#
#   scripts/capture-screenshots.sh                 # iPhone + iPad
#   scripts/capture-screenshots.sh iphone          # one device
#   scripts/capture-screenshots.sh duo             # iPhone Duo: unfold it first (see below)
#   SKIP_BUILD=1 scripts/capture-screenshots.sh    # reuse the last build
#
# Builds the signed Debug app (never CODE_SIGNING_ALLOWED=NO: see AGENTS.md), boots each simulator in
# dark mode with a clean 9:41 status bar, launches the `-demo` wallet once per slide with the matching
# `-route`, and saves fastlane/screenshot-studio/assets/shots/<locale>/<device>/<slide>.png.
#
# iPhone Duo: simctl can't unfold the simulator. Open it from Xcode (Window > Devices and Simulators),
# unfold it so the inner display is on, then run with `duo`; shots come from the inner display (3).
# The `widget` slide needs a home screen with the widget placed by hand: capture it yourself.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCALE="${LOCALE:-en-US}"
BUNDLE_ID="com.simnetiq.kestrel"
APP="$ROOT/build/Build/Products/Debug-iphonesimulator/Kestrel.app"
SHOTS="$ROOT/fastlane/screenshot-studio/assets/shots/$LOCALE"
WAIT="${WAIT:-10}"

simulator_for() {
  case "$1" in
    iphone) echo "iPhone 18 Pro Max" ;;
    ipad)   echo "iPad Pro 13-inch (M5)" ;;
    duo)    echo "iPhone Duo" ;;
    *) echo "unknown device: $1" >&2; exit 1 ;;
  esac
}

# slide id | launch arguments
SLIDES=(
  "home|-demo"
  "send|-demo -route send -sendPreview amount"
  "receive|-demo -route receive"
  "activity|-demo -route activity"
  "coin|-demo -route coin-trx"
  "transfer|-demo -route transfer"
  "security|-demo -route lock"
  "welcome|-welcome"
)

DEVICES=("$@")
[ ${#DEVICES[@]} -eq 0 ] && DEVICES=(iphone ipad)

if [ -z "${SKIP_BUILD:-}" ]; then
  echo "Building signed Debug app…"
  xcodebuild -project "$ROOT/Kestrel.xcodeproj" -scheme Kestrel \
    -destination "platform=iOS Simulator,name=$(simulator_for iphone)" \
    -derivedDataPath "$ROOT/build" build -quiet
fi
[ -d "$APP" ] || { echo "No app at $APP" >&2; exit 1; }

for device in "${DEVICES[@]}"; do
  sim="$(simulator_for "$device")"
  out="$SHOTS/$device"
  mkdir -p "$out"
  display_args=()
  [ "$device" = duo ] && display_args=(--display=3)

  echo "== $device ($sim)"
  xcrun simctl boot "$sim" 2>/dev/null || true
  xcrun simctl bootstatus "$sim" -b >/dev/null
  xcrun simctl ui "$sim" appearance dark
  xcrun simctl status_bar "$sim" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  xcrun simctl install "$sim" "$APP"

  for entry in "${SLIDES[@]}"; do
    slide="${entry%%|*}"
    read -r -a args <<< "${entry#*|}"
    xcrun simctl launch --terminate-running-process "$sim" "$BUNDLE_ID" "${args[@]}" >/dev/null
    # The first launch after an install is slow; the splash alone takes 1.5 s.
    sleep "$WAIT"
    xcrun simctl io "$sim" screenshot ${display_args[@]+"${display_args[@]}"} "$out/$slide.png" >/dev/null 2>&1
    echo "   $slide  $(sips -g pixelWidth -g pixelHeight "$out/$slide.png" | awk '/pixel/ {printf "%s ", $2}')"
  done
  xcrun simctl status_bar "$sim" clear
done

echo "Done. Next: cd fastlane/screenshot-studio && node server.mjs   (or: node server.mjs export …)"
