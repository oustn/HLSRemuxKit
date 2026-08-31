# HLSRemuxKit

Reusable iOS 16 Swift Package for lossless local HLS remuxing.

The package currently supports:

- MPEG-TS to MP4 with stream copy.
- Fragmented-MP4 HLS playlist (`.m3u8` + `.m4s`/init segment) to MP4 with stream copy.
- Cancellation and optional progress callbacks.
- Transactional output replacement that preserves an existing destination on failure or cancellation.

It does not decode or re-encode. One `HLSRemuxer` runs one operation at a time; create separate instances for intentional concurrency. The bundled FFmpegKitNext wrapper 8.1.1 with FFmpeg 8.1.2 libraries is LGPL-licensed and targets arm64 iOS devices and arm64 iOS simulators. It intentionally does not include x86_64 simulator slices.

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

The script runs host unit tests, type-checks the arm64 iOS device and Apple Silicon simulator slices, selects or boots an available iPhone simulator, and runs real TS/fMP4 integration tests. The integration tests verify audio and video tracks, failure preservation, cancellation cleanup, and public error behavior.

Set `HLS_REMUX_SIMULATOR_ID` to select a specific available simulator. Environments intentionally lacking an iOS simulator can run compile-only validation with:

```bash
HLS_REMUX_SKIP_INTEGRATION=1 ./Scripts/build-ios.sh
```

Physical-device execution remains an optional manual validation step. The automated script compiles the device slice but does not claim to run tests on a device. The bundled binaries intentionally do not contain an x86_64 simulator slice.

## Replacing the vendor binaries

The public Swift API only depends on FFmpegKit's execute and cancel calls. A future build produced from `ffmpeg-kit-next` can replace the archives in `Vendor/FFmpegKitNext` as long as it keeps the same framework names and iOS 16-compatible arm64 slices. Run `Scripts/build-ios.sh` after replacement to execute host tests, check both iOS slices, and run the simulator integration suite.

### Binary symbols

The archives must include UUID-matched dSYM bundles for both supported slices. `Scripts/build-ios.sh` rejects stripped vendor archives before compiling. To produce a replacement payload, build FFmpegKitNext from the pinned source tag with `Scripts/build-ffmpegkitnext-with-dsym.sh`, then copy only the output that passes `Scripts/verify-vendor-dsym.sh` into `Vendor/FFmpegKitNext`. See `Vendor/FFmpegKitNext/README.md` for the supply procedure. dSYM files cannot be reconstructed from the historical stripped binaries.

See `LICENSES/NOTICE.md` for the vendor release and LGPL obligations.
