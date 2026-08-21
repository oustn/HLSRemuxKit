import Foundation
import Testing
@testable import HLSRemuxCore

struct RemuxCommandTests {
    @Test func transportStreamCommandCopiesAllStreamsIntoMP4() {
        let input = URL(fileURLWithPath: "/tmp/input with spaces.ts")
        let output = URL(fileURLWithPath: "/tmp/output with spaces.mp4")

        let arguments = RemuxCommand.arguments(input: input, output: output, kind: .transportStream)

        #expect(arguments == [
            "-y", "-hide_banner", "-loglevel", "error",
            "-i", "/tmp/input with spaces.ts",
            "-map", "0", "-c", "copy", "-movflags", "+faststart",
            "/tmp/output with spaces.mp4"
        ])
    }

    @Test func fragmentedMP4PlaylistAllowsLocalSegmentProtocols() {
        let arguments = RemuxCommand.arguments(
            input: URL(fileURLWithPath: "/tmp/index.m3u8"),
            output: URL(fileURLWithPath: "/tmp/media.mp4"),
            kind: .fragmentedMP4Playlist
        )

        #expect(arguments.contains("-protocol_whitelist"))
        #expect(arguments.contains("file,crypto,data"))
        #expect(arguments.contains("-c"))
        #expect(arguments.contains("copy"))
        #expect(!arguments.contains("libx264"))
    }
}
