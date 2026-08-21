# HLSRemuxKit

Reusable iOS 16 Swift Package for lossless local HLS remuxing.

The package currently supports:

- MPEG-TS to MP4 with stream copy.
- Fragmented-MP4 HLS playlist (`.m3u8` + `.m4s`/init segment) to MP4 with stream copy.
- Cancellation and optional progress callbacks.

It does not decode or re-encode. The bundled FFmpegKitNext-derived binaries are LGPL-licensed and target arm64 iOS devices and arm64 iOS simulators. They intentionally do not include x86_64 simulator slices.

## Usage

```swift
let remuxer = HLSRemuxer()
let result = try await remuxer.remuxTS(input: tsURL, output: mp4URL)
print(result.outputURL, result.sizeBytes)
```

For a local fMP4 playlist, call `remuxFMP4Playlist(input:output:progress:)`.

Add the package from its private GitHub repository when authenticated as a collaborator, or use a local package reference while developing it alongside a consuming application.

## Validation

```bash
./Scripts/build-ios.sh
```

The script runs host unit tests and type-checks the arm64 iOS device and Apple Silicon simulator slices. The bundled binaries intentionally do not contain an x86_64 simulator slice.

## Replacing the vendor binaries

The public Swift API only depends on FFmpegKit's execute and cancel calls. A future build produced from `ffmpeg-kit-next` can replace the archives in `Vendor/FFmpegKitNext` as long as it keeps the same framework names and iOS 16-compatible arm64 slices. Run `Scripts/build-ios.sh` to execute host tests and type-check both iOS slices.

See `LICENSES/NOTICE.md` for the vendor release and LGPL obligations.
