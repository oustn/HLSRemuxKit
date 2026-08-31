#!/usr/bin/env bash
set -euo pipefail

# Rebuild the vendor payload from source. A source rebuild is required because
# dSYM files cannot be generated from the stripped binaries currently shipped.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-${ROOT_DIR}/Vendor/FFmpegKitNext-rebuilt}"
SOURCE_REF="${FFMPEG_KIT_NEXT_REF:-v8.1.1}"
SOURCE_URL="${FFMPEG_KIT_NEXT_URL:-https://github.com/arthenica/ffmpeg-kit-next.git}"
SOURCE_PROXY="${FFMPEG_KIT_NEXT_PROXY:-${HTTPS_PROXY:-${https_proxy:-}}}"
BUILD_ROOT="$(mktemp -d)"
cleanup() {
  if [[ "${KEEP_FFMPEG_BUILD_ROOT:-0}" == "1" ]]; then
    echo "Preserving failed build tree at ${BUILD_ROOT}" >&2
  else
    rm -rf -- "${BUILD_ROOT}"
  fi
}
trap cleanup EXIT

# Resolve the destination before changing into the cloned source tree.
mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"

command -v xcrun >/dev/null || { echo "error: Xcode command line tools are required" >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo "error: xcodebuild is required" >&2; exit 1; }
command -v dsymutil >/dev/null || { echo "error: dsymutil is required" >&2; exit 1; }
for tool in pkg-config autoreconf automake; do
  command -v "${tool}" >/dev/null || { echo "error: ${tool} is required by FFmpegKitNext" >&2; exit 1; }
done
SED_BIN="${SED:-sed}"
command -v "${SED_BIN}" >/dev/null || { echo "error: GNU sed is required; set SED to its executable" >&2; exit 1; }
if ! "${SED_BIN}" --version >/dev/null 2>&1; then
  echo "error: FFmpegKitNext v8.1.1 requires GNU sed (install it and set SED, or use the project's Nix shell)" >&2
  exit 1
fi
export SED="${SED_BIN}"

git_args=(git)
if [[ -n "${SOURCE_PROXY}" ]]; then
  git_args+=( -c "http.proxy=${SOURCE_PROXY}" -c "https.proxy=${SOURCE_PROXY}" )
  # FFmpegKitNext itself clones pinned dependency repositories. Propagate the
  # proxy through the environment so those nested clones use the same route.
  export HTTP_PROXY="${SOURCE_PROXY}" HTTPS_PROXY="${SOURCE_PROXY}"
  export http_proxy="${SOURCE_PROXY}" https_proxy="${SOURCE_PROXY}"
fi
"${git_args[@]}" clone --depth 1 --branch "${SOURCE_REF}" "${SOURCE_URL}" "${BUILD_ROOT}/ffmpeg-kit-next"
cd "${BUILD_ROOT}/ffmpeg-kit-next"

# Keep only the two slices consumed by HLSRemuxKit. -d sets -g and disables
# FFmpeg's strip step, which is the prerequisite for a real dsymutil output.
scripts/start-ios.sh -x -d --no-bitcode --target=16.0 \
  --no-output-redirection \
  --enable-ios-videotoolbox \
  --disable-armv7 --disable-armv7s --disable-i386 \
  --disable-arm64e --disable-x86-64 \
  --disable-arm64-mac-catalyst --disable-x86-64-mac-catalyst

prebuilt="${BUILD_ROOT}/ffmpeg-kit-next/prebuilt"
xcf_dir="$(find "${prebuilt}" -maxdepth 1 -type d -name 'bundle-apple-xcframework-ios-*' -print -quit)"
[[ -n "${xcf_dir}" ]] || { echo "error: FFmpegKitNext did not produce xcframeworks" >&2; exit 1; }

frameworks=(ffmpegkit libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale)
slices=(ios-arm64 ios-arm64-simulator)

for name in "${frameworks[@]}"; do
  source_xcf="${xcf_dir}/${name}.xcframework"
  output_xcf="${BUILD_ROOT}/${name}.xcframework"
  args=(xcodebuild -create-xcframework)
  for slice in "${slices[@]}"; do
    framework="${source_xcf}/${slice}/${name}.framework"
    binary="${framework}/${name}"
    [[ -f "${binary}" ]] || { echo "error: missing ${binary}" >&2; exit 1; }
    # Keep Apple's conventional name so xcodebuild places it under the
    # slice's dSYMs/<name>.framework.dSYM directory.
    dsym="${BUILD_ROOT}/${name}-${slice}.framework.dSYM"
    xcrun dsymutil "${binary}" -o "${dsym}"
    args+=( -framework "${framework}" -debug-symbols "${dsym}" )
  done

  args+=( -output "${output_xcf}" )
  "${args[@]}"
  ditto -c -k --sequesterRsrc --keepParent "${output_xcf}" "${OUT_DIR}/${name}.xcframework.zip"
done

"${ROOT_DIR}/Scripts/verify-vendor-dsym.sh" "${OUT_DIR}"
echo "Built and verified dSYM-enabled archives in ${OUT_DIR}"
