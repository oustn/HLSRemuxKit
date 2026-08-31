#!/usr/bin/env bash
set -euo pipefail

# Validate the symbols shipped with the binary targets. This intentionally
# fails for the historical archives in this repository: they were stripped
# before distribution and therefore cannot be repaired after the fact.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="${1:-${ROOT_DIR}/Vendor/FFmpegKitNext}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf -- "${WORK_DIR}"' EXIT

frameworks=(ffmpegkit libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale)
slices=(ios-arm64 ios-arm64-simulator)
failures=0

die() {
  echo "error: $*" >&2
  failures=$((failures + 1))
}

for name in "${frameworks[@]}"; do
  archive="${VENDOR_DIR}/${name}.xcframework.zip"
  if [[ ! -f "${archive}" ]]; then
    die "missing archive: ${archive}"
    continue
  fi

  unpacked="${WORK_DIR}/${name}"
  mkdir -p "${unpacked}"
  unzip -q "${archive}" -d "${unpacked}"
  xcf="${unpacked}/${name}.xcframework"

  for slice in "${slices[@]}"; do
    binary="${xcf}/${slice}/${name}.framework/${name}"
    if [[ ! -f "${binary}" ]]; then
      die "${name}: missing ${slice} binary"
      continue
    fi

    archs="$(lipo -archs "${binary}")"
    if [[ " ${archs} " != *" arm64 "* ]]; then
      die "${name}/${slice}: expected arm64, found ${archs}"
    fi

    expected="$(xcrun dwarfdump --uuid "${binary}" | awk '/UUID:/ {print $2}')"
    if [[ -z "${expected}" ]]; then
      die "${name}/${slice}: binary has no UUID"
      continue
    fi

    dsym="${xcf}/${slice}/dSYMs/${name}.framework.dSYM"
    if [[ ! -d "${dsym}" ]]; then
      dsym="$(find "${xcf}/${slice}/dSYMs" -maxdepth 1 -type d -name "${name}-*.framework.dSYM" -print -quit 2>/dev/null)"
    fi
    if [[ ! -d "${dsym}" ]]; then
      dsym="${xcf}/${slice}/${name}.framework.dSYM"
    fi
    if [[ ! -d "${dsym}" ]]; then
      dsym="${xcf}/${slice}/${name}.dSYM"
    fi
    if [[ ! -d "${dsym}" ]]; then
      dsym="${xcf}/${slice}/${name}.framework/${name}.dSYM"
    fi
    if [[ ! -d "${dsym}" ]]; then
      die "${name}/${slice}: missing dSYM (expected ${name}.framework.dSYM)"
      continue
    fi

    dwarf="${dsym}/Contents/Resources/DWARF/${name}"
    if [[ ! -f "${dwarf}" ]]; then
      die "${name}/${slice}: dSYM has no DWARF/${name}"
      continue
    fi

    actual="$(xcrun dwarfdump --uuid "${dwarf}" | awk '/UUID:/ {print $2}')"
    if [[ "${actual}" != "${expected}" ]]; then
      die "${name}/${slice}: dSYM UUID ${actual:-<none>} does not match binary ${expected}"
      continue
    fi
    debug_info="$(xcrun dwarfdump --debug-info "${dwarf}")"
    if [[ "${debug_info}" != *".debug_info contents:"* ]] || [[ "${debug_info}" != *"DW_TAG_compile_unit"* ]]; then
      die "${name}/${slice}: dSYM contains no DWARF debug info"
      continue
    fi

    echo "ok: ${name}/${slice} UUID ${expected}"
  done
done

if (( failures > 0 )); then
  echo "error: ${failures} dSYM validation failure(s)" >&2
  exit 1
fi
