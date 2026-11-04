#!/bin/bash
# Boots a simulator, installs Canary and screenshots each screen.
#
#   bash ios/ci/shoot.sh "<device type name>" <path/to/Canary.app> <out dir>
#
# Screens are opened with the debug launch arguments in Canary/App/DebugLaunch.swift.
# On iPhone Duo the hinge is moved with the third-party `hinge` CLI through
# duo_pose.py (both MIT), because simctl has no fold or rotation command.
# Runs on macOS's bash 3.2: no `set -u`, no associative arrays.

set -o pipefail

DEVICE="$1"
APP="$2"
OUT="$3"
BUNDLE=com.danleech.canary
PINS="oil,equity-stress,uk-rates,ebola,global-temp"
SLUG=$(echo "$DEVICE" | tr 'A-Z ' 'a-z-')
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT"

log() { echo "▸ $*"; }

read -r DT RT < <(python3 - "$DEVICE" <<'PY'
import json, subprocess, sys
name = sys.argv[1]
types = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devicetypes", "-j"]))["devicetypes"]
dt = next(t["identifier"] for t in types if t["name"] == name)
runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"]))["runtimes"]
ok = [r for r in runtimes
      if r.get("isAvailable") and r.get("platform") == "iOS"
      and any(s["identifier"] == dt for s in r.get("supportedDeviceTypes", []))]
ok.sort(key=lambda r: [int(p) for p in r["version"].split(".")])
print(dt, ok[-1]["identifier"])
PY
)
log "device type $DT, runtime $RT"

UDID=$(xcrun simctl create "CI $DEVICE" "$DT" "$RT")
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true
xcrun simctl ui "$UDID" appearance light
xcrun simctl install "$UDID" "$APP"
xcrun simctl io "$UDID" enumerate > "$OUT/$SLUG-displays.txt" 2>&1 || true

SIT=$(curl -fsSL https://canary.danleech.com/api/v1/status.json \
  | python3 -c "import json,sys; s=json.load(sys.stdin).get('situations') or []; print(s[0]['id'] if s else '')" || true)

DISPLAY_ARG=""

launch() {
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" -CanaryPins "$PINS" "$@" >/dev/null
}

# shot <name> <seconds to wait> [launch arguments…]
# Waits, then polls until the app has drawn: a blank launch screen compresses to a
# small PNG for its pixel count, a drawn screen doesn't. Then waits a moment more for animations.
shot() {
  local name="$1" wait="$2" file tries=0 size=0 px=0
  shift 2
  file="$OUT/$SLUG-$name.png"
  launch "$@"
  sleep "$wait"
  while :; do
    xcrun simctl io "$UDID" screenshot $DISPLAY_ARG "$file" >/dev/null 2>&1
    size=$(stat -f%z "$file" 2>/dev/null || echo 0)
    # Bytes per thousand pixels: blank launch screens measured ~23, drawn screens 38+.
    px=$(sips -g pixelWidth -g pixelHeight "$file" 2>/dev/null | awk '/pixel/ {p = p ? p * $2 : $2} END {print p + 0}')
    [ "${px:-0}" -gt 0 ] && [ $((size * 1000 / px)) -gt 30 ] && break
    [ "$tries" -ge 20 ] && break
    tries=$((tries + 1))
    sleep 1
  done
  sleep 1.5
  xcrun simctl io "$UDID" screenshot $DISPLAY_ARG "$file" >/dev/null 2>&1
  log "$name ($size bytes after $tries retries)"
}

screens() {
  local p="$1"
  shot "${p}summary" 5
  shot "${p}browse" 4 -CanaryTab browse
  shot "${p}domain" 4 -CanaryRoute canary://domain/energy
  shot "${p}signal" 4 -CanaryRoute canary://signal/oil
  shot "${p}world" 4 -CanaryRoute canary://world
  shot "${p}plus" 4 -CanarySheet plus
}

if [ "$DEVICE" = "iPhone Duo" ]; then
  POSE="python3 $HERE/duo_pose.py --device $UDID"
  $POSE status > "$OUT/$SLUG-status.txt" 2>&1 || true
  # First launch on whichever display is active, to fill the cache.
  launch
  sleep 15
  for pose in closed flat flat-portrait book closed-landscape tabletop; do
    if ! $POSE set "$pose" >> "$OUT/$SLUG-status.txt" 2>&1; then
      log "pose $pose not reached"
      continue
    fi
    case "$pose" in
      closed*) DISPLAY_ARG="--display=1" ;;
      *) DISPLAY_ARG="--display=3" ;;
    esac
    sleep 2
    screens "$pose-"
    if [ "$pose" = "flat" ]; then
      shot "flat-changes" 4 -CanaryTab changes
      shot "flat-search" 4 -CanaryTab search
      [ -n "$SIT" ] && shot "flat-situation" 4 -CanaryRoute "canary://situation/$SIT"
      shot "flat-settings" 4 -CanarySheet settings
      xcrun simctl ui "$UDID" appearance dark
      shot "flat-summary-dark" 4
      shot "flat-signal-dark" 4 -CanaryRoute canary://signal/oil
      xcrun simctl ui "$UDID" appearance light
    fi
  done
else
  shot summary 10
  shot browse 4 -CanaryTab browse
  shot domain 4 -CanaryRoute canary://domain/energy
  shot changes 4 -CanaryTab changes
  shot search 4 -CanaryTab search
  shot signal 4 -CanaryRoute canary://signal/oil
  shot signal-uk 4 -CanaryRoute canary://signal/uk-rates
  shot world 4 -CanaryRoute canary://world
  [ -n "$SIT" ] && shot situation 4 -CanaryRoute "canary://situation/$SIT"
  shot plus 4 -CanarySheet plus
  shot settings 4 -CanarySheet settings
  shot pins 4 -CanarySheet pins
  xcrun simctl ui "$UDID" appearance dark
  shot summary-dark 4
  shot browse-dark 4 -CanaryTab browse
  shot signal-dark 4 -CanaryRoute canary://signal/oil
  shot world-dark 4 -CanaryRoute canary://world
  xcrun simctl ui "$UDID" appearance light
  xcrun simctl ui "$UDID" content_size accessibility-extra-large
  shot summary-ax 4
  shot signal-ax 4 -CanaryRoute canary://signal/oil
  xcrun simctl ui "$UDID" content_size large
fi

# Logs and any crash reports, for blank or missing screens.
xcrun simctl spawn "$UDID" log show --last 30m --style compact \
  --predicate 'process == "Canary"' > "$OUT/$SLUG-log.txt" 2>&1 || true
cp ~/Library/Logs/DiagnosticReports/Canary* "$OUT/" 2>/dev/null || true
ls -1 "$OUT"
