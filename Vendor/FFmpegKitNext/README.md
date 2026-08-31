# FFmpegKitNext binary supply

The eight archives in this directory are the FFmpegKitNext wrapper 8.1.1
with FFmpeg 8.1.2 libraries. The historical 2026-07-31 payload was stripped
before publication and does **not** contain usable dSYM files. It must not be
used for a release that is expected to have symbolicated TestFlight crashes.

Build a replacement payload from source on a macOS machine with Xcode:

```sh
./Scripts/build-ffmpegkitnext-with-dsym.sh Vendor/FFmpegKitNext-rebuilt
./Scripts/verify-vendor-dsym.sh Vendor/FFmpegKitNext-rebuilt
```

The build is pinned to the upstream `v8.1.1` tag, uses debug/no-strip flags,
creates a dSYM for every `ios-arm64` and `ios-arm64-simulator` framework, and
passes each symbol bundle to `xcodebuild -create-xcframework -debug-symbols`.
Copy the eight verified ZIPs from `Vendor/FFmpegKitNext-rebuilt` over this
directory only after reviewing their checksums. The verifier compares every
dSYM UUID with its binary and rejects empty or mismatched symbols; it never
attempts to synthesize symbols from a stripped binary.

The original source/vendor provenance remains documented in
`LICENSES/NOTICE.md`.
