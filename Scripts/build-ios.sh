#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$(mktemp -d)"
for archive in "${ROOT_DIR}"/Vendor/FFmpegKitNext/*.xcframework.zip; do
  unzip -q -o "${archive}" -d "${VENDOR_DIR}"
done

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
    "${ROOT_DIR}/Sources/HLSRemuxCore/RemuxCommand.swift"

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

swift test --package-path "${ROOT_DIR}"
check_target iphonesimulator arm64-apple-ios16.0-simulator ios-arm64-simulator
check_target iphoneos arm64-apple-ios16.0 ios-arm64
