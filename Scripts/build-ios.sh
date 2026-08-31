#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$(mktemp -d)"
INTEGRATION_DERIVED="$(mktemp -d)"
RESULT_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf -- "${VENDOR_DIR}" "${INTEGRATION_DERIVED}" "${RESULT_ROOT}"
}
trap cleanup EXIT

# TestFlight requires UUID-matched symbols for every embedded binary. Fail
# before compiling if the vendored payload is still the historical stripped
# build; see build-ffmpegkitnext-with-dsym.sh for the source rebuild.
"${ROOT_DIR}/Scripts/verify-vendor-dsym.sh" "${ROOT_DIR}/Vendor/FFmpegKitNext"

for archive in "${ROOT_DIR}"/Vendor/FFmpegKitNext/*.xcframework.zip; do
  unzip -q -o "${archive}" -d "${VENDOR_DIR}"
done

select_simulator() {
  local requested_id="${HLS_REMUX_SIMULATOR_ID:-}"
  local devices_json
  local selected
  devices_json="$(xcrun simctl list devices available -j)"

  selected="$(ruby -rjson -e '
    requested = ARGV[0]
    devices = JSON.parse(STDIN.read).fetch("devices").values.flatten
    devices.select! { |device| device.fetch("isAvailable", true) }
    device = if requested.empty?
      devices.find { |item| item["name"].include?("iPhone") && item["state"] == "Booted" } ||
        devices.find { |item| item["name"].include?("iPhone") }
    else
      devices.find { |item| item["udid"] == requested }
    end
    puts [device["udid"], device["state"], device["name"]].join("|") if device
  ' "${requested_id}" <<<"${devices_json}")"

  if [[ -z "${selected}" ]]; then
    if [[ -n "${requested_id}" ]]; then
      echo "error: requested iOS simulator is unavailable: ${requested_id}" >&2
    else
      echo "error: no available iPhone simulator was found" >&2
    fi
    return 1
  fi

  IFS='|' read -r SIMULATOR_ID SIMULATOR_STATE SIMULATOR_NAME <<<"${selected}"
  if [[ "${SIMULATOR_STATE}" != "Booted" ]]; then
    xcrun simctl boot "${SIMULATOR_ID}"
    xcrun simctl bootstatus "${SIMULATOR_ID}" -b
  fi
  echo "Using iOS simulator: ${SIMULATOR_NAME} (${SIMULATOR_ID})"
}

check_target() {
  local sdk_name="$1"
  local target="$2"
  local slice="$3"
  local sdk_path
  local scratch
  sdk_path="$(xcrun --sdk "${sdk_name}" --show-sdk-path)"
  scratch="$(mktemp -d)"

  xcrun swiftc \
    -target "${target}" \
    -sdk "${sdk_path}" \
    -emit-module \
    -emit-module-path "${scratch}/HLSRemuxCore.swiftmodule" \
    -module-name HLSRemuxCore \
    "${ROOT_DIR}"/Sources/HLSRemuxCore/*.swift

  local framework_flags=()
  for framework in ffmpegkit libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale; do
    framework_flags+=("-F" "${VENDOR_DIR}/${framework}.xcframework/${slice}")
  done

  xcrun swiftc \
    -target "${target}" \
    -sdk "${sdk_path}" \
    -typecheck \
    -I "${scratch}" \
    "${framework_flags[@]}" \
    "${ROOT_DIR}/Sources/HLSRemuxKit/HLSRemuxer.swift"
}

if [[ "${HLS_REMUX_SKIP_INTEGRATION:-0}" != "1" ]]; then
  select_simulator
fi

swift test --package-path "${ROOT_DIR}"
check_target iphonesimulator arm64-apple-ios16.0-simulator ios-arm64-simulator
check_target iphoneos arm64-apple-ios16.0 ios-arm64

if [[ "${HLS_REMUX_SKIP_INTEGRATION:-0}" == "1" ]]; then
  echo "Skipping iOS simulator integration tests (HLS_REMUX_SKIP_INTEGRATION=1)."
  exit 0
fi

xcodebuild test -quiet \
  -scheme HLSRemuxKit \
  -derivedDataPath "${INTEGRATION_DERIVED}" \
  -resultBundlePath "${RESULT_ROOT}/Integration.xcresult" \
  -destination "platform=iOS Simulator,id=${SIMULATOR_ID},arch=arm64" \
  -only-testing:HLSRemuxKitIntegrationTests

xcrun xcresulttool get test-results summary \
  --path "${RESULT_ROOT}/Integration.xcresult"
