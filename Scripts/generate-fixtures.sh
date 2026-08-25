#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE_DIR="${ROOT_DIR}/Tests/HLSRemuxKitIntegrationTests/Fixtures"
STAGING_DIR="$(mktemp -d)"
STAGING_FMP4_DIR="${STAGING_DIR}/fmp4"
trap 'rm -rf "${STAGING_DIR}"' EXIT

for tool in ffmpeg ffprobe; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: ${tool} is required to generate media fixtures" >&2
    exit 1
  fi
done

mkdir -p "${STAGING_FMP4_DIR}"

ffmpeg -v error -y \
  -f lavfi -i "testsrc2=size=320x180:rate=24" \
  -f lavfi -i "sine=frequency=1000:sample_rate=48000" \
  -t 2 -shortest \
  -c:v libx264 -pix_fmt yuv420p -g 48 -keyint_min 48 -sc_threshold 0 \
  -c:a aac -b:a 96k -map_metadata -1 \
  -f mpegts "${STAGING_DIR}/sample.ts"

ffmpeg -v error -y \
  -i "${STAGING_DIR}/sample.ts" -map 0 -c copy -bsf:a aac_adtstoasc \
  -hls_time 2 -hls_list_size 0 -hls_playlist_type vod \
  -hls_flags independent_segments \
  -hls_segment_type fmp4 \
  -hls_fmp4_init_filename init.mp4 \
  -hls_segment_filename "${STAGING_FMP4_DIR}/segment%d.m4s" \
  "${STAGING_FMP4_DIR}/index.m3u8"

validate_streams() {
  local input="$1"
  local codecs
  codecs="$(ffprobe -v error -show_entries stream=codec_name,codec_type -of csv=p=0 "${input}")"
  if ! grep -q "h264,video" <<<"${codecs}"; then
    echo "error: ${input} does not contain H.264 video" >&2
    exit 1
  fi
  if ! grep -q "aac,audio" <<<"${codecs}"; then
    echo "error: ${input} does not contain AAC audio" >&2
    exit 1
  fi
}

validate_streams "${STAGING_DIR}/sample.ts"
validate_streams "${STAGING_FMP4_DIR}/index.m3u8"

fixture_bytes="$(find "${STAGING_DIR}" -type f -exec stat -f %z {} + | awk '{ total += $1 } END { print total + 0 }')"
if (( fixture_bytes > 1048576 )); then
  echo "error: generated fixtures are ${fixture_bytes} bytes; limit is 1048576" >&2
  exit 1
fi

mkdir -p "${FIXTURE_DIR}/fmp4"
cp "${STAGING_DIR}/sample.ts" "${FIXTURE_DIR}/sample.ts"
cp "${STAGING_FMP4_DIR}/index.m3u8" "${FIXTURE_DIR}/fmp4/index.m3u8"
cp "${STAGING_FMP4_DIR}/init.mp4" "${FIXTURE_DIR}/fmp4/init.mp4"
cp "${STAGING_FMP4_DIR}/segment0.m4s" "${FIXTURE_DIR}/fmp4/segment0.m4s"

echo "Generated and validated H.264/AAC fixtures (${fixture_bytes} bytes)."
