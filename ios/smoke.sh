#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import sys,json;d=[v for vs in json.load(sys.stdin)["devices"].values() for v in vs if "iPhone" in v["name"]];d.sort(key=lambda v:v["name"]!="iPhone 16 Pro");print(d[0]["udid"])')
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" "$ROOT/ios/out/simulator/Payload/Reloaded.app"
xcrun simctl launch "$DEVICE" com.lixarx.reloaded.ios --smoke-test
CONTAINER=$(xcrun simctl get_app_container "$DEVICE" com.lixarx.reloaded.ios data)
mkdir -p "$ROOT/ios/out/verification"
for i in $(seq 1 120); do
  if [[ ! -f "$ROOT/ios/out/verification/simulator.png" ]] && grep -q IOS_SMOKE_OK "$CONTAINER/Documents/emulator.log" 2>/dev/null; then
    xcrun simctl io "$DEVICE" screenshot "$ROOT/ios/out/verification/simulator.png"
  fi
  if [[ -f "$CONTAINER/Documents/smoke-result.txt" ]]; then break; fi
  sleep 1
done
if [[ ! -f "$ROOT/ios/out/verification/simulator.png" ]]; then
  xcrun simctl io "$DEVICE" screenshot "$ROOT/ios/out/verification/simulator.png"
fi
cp "$CONTAINER/Documents/emulator.log" "$ROOT/ios/out/verification/" || true
cp "$CONTAINER/Documents/smoke-result.txt" "$ROOT/ios/out/verification/" || true
cat "$ROOT/ios/out/verification/emulator.log" || true
test "$(cat "$ROOT/ios/out/verification/smoke-result.txt")" = PASS
