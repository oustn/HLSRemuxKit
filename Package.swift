// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HLSRemuxKit",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "HLSRemuxKit", targets: ["HLSRemuxKit"])
    ],
    targets: [
        .target(
            name: "HLSRemuxCore",
            path: "Sources/HLSRemuxCore"
        ),
        .binaryTarget(
            name: "FFmpegKit",
            path: "Vendor/FFmpegKitNext/ffmpegkit.xcframework.zip"
        ),
        .binaryTarget(
            name: "libavcodec",
            path: "Vendor/FFmpegKitNext/libavcodec.xcframework.zip"
        ),
        .binaryTarget(
            name: "libavdevice",
            path: "Vendor/FFmpegKitNext/libavdevice.xcframework.zip"
        ),
        .binaryTarget(
            name: "libavfilter",
            path: "Vendor/FFmpegKitNext/libavfilter.xcframework.zip"
        ),
        .binaryTarget(
            name: "libavformat",
            path: "Vendor/FFmpegKitNext/libavformat.xcframework.zip"
        ),
        .binaryTarget(
            name: "libavutil",
            path: "Vendor/FFmpegKitNext/libavutil.xcframework.zip"
        ),
        .binaryTarget(
            name: "libswresample",
            path: "Vendor/FFmpegKitNext/libswresample.xcframework.zip"
        ),
        .binaryTarget(
            name: "libswscale",
            path: "Vendor/FFmpegKitNext/libswscale.xcframework.zip"
        ),
        .target(
            name: "HLSRemuxKit",
            dependencies: [
                "HLSRemuxCore",
                "FFmpegKit",
                "libavcodec",
                "libavdevice",
                "libavfilter",
                "libavformat",
                "libavutil",
                "libswresample",
                "libswscale"
            ],
            path: "Sources/HLSRemuxKit",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("VideoToolbox"),
                .linkedLibrary("c++")
            ]
        ),
        .testTarget(
            name: "HLSRemuxKitTests",
            dependencies: ["HLSRemuxCore"],
            path: "Tests/HLSRemuxKitTests"
        )
    ]
)
