#if os(iOS)
import AVFoundation
import XCTest
@testable import HLSRemuxKit

final class HLSRemuxKitIntegrationTests: XCTestCase {
    func testTransportStreamProducesMP4WithVideoAndAudio() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let input = try fixtureURL("sample", extension: "ts")
        let output = workspace.appendingPathComponent("transport-stream.mp4")

        let result = try await HLSRemuxer().remuxTS(input: input, output: output)

        try await assertPlayableAudioVideo(result)
    }

    func testFragmentedMP4PlaylistProducesMP4WithVideoAndAudio() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let inputDirectory = try fixtureURL("fmp4", extension: nil)
        let localInputDirectory = workspace.appendingPathComponent("fmp4", isDirectory: true)
        try FileManager.default.copyItem(at: inputDirectory, to: localInputDirectory)
        let input = localInputDirectory.appendingPathComponent("index.m3u8")
        let output = workspace.appendingPathComponent("fragmented.mp4")

        let result = try await HLSRemuxer().remuxFMP4Playlist(input: input, output: output)

        try await assertPlayableAudioVideo(result)
    }

    func testFailedRemuxPreservesExistingDestination() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let input = workspace.appendingPathComponent("invalid.m3u8")
        let output = workspace.appendingPathComponent("existing.mp4")
        let existingData = Data("existing output".utf8)
        try Data("#EXTM3U\n#EXTINF:1,\nmissing.m4s\n".utf8).write(to: input)
        try existingData.write(to: output)

        do {
            _ = try await HLSRemuxer().remuxFMP4Playlist(input: input, output: output)
            XCTFail("Expected invalid playlist remux to fail")
        } catch let error as HLSRemuxError {
            guard case .failed = error else {
                return XCTFail("Expected failed error, got \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: output), existingData)
        XCTAssertTrue(try temporaryOutputs(in: workspace).isEmpty)
    }

    func testCancellationPreservesExistingDestinationAndRemovesTemporaryOutput() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let input = try makeExpandedPlaylist(in: workspace, segmentCount: 2_000)
        let output = workspace.appendingPathComponent("existing.mp4")
        let existingData = Data("existing output".utf8)
        try existingData.write(to: output)
        let remuxer = HLSRemuxer()
        let didCancel = LockedFlag()

        do {
            _ = try await remuxer.remuxFMP4Playlist(input: input, output: output) { progress in
                if progress.processedBytes > 0 && didCancel.setIfFalse() {
                    remuxer.cancel()
                }
            }
            XCTFail("Expected remux to be cancelled")
        } catch let error as HLSRemuxError {
            XCTAssertEqual(error, .cancelled)
        }

        XCTAssertEqual(try Data(contentsOf: output), existingData)
        XCTAssertTrue(try temporaryOutputs(in: workspace).isEmpty)
    }

    func testMissingInputReportsInputMissing() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let input = workspace.appendingPathComponent("missing.ts")
        let output = workspace.appendingPathComponent("output.mp4")

        do {
            _ = try await HLSRemuxer().remuxTS(input: input, output: output)
            XCTFail("Expected missing input error")
        } catch let error as HLSRemuxError {
            XCTAssertEqual(error, .inputMissing(input))
        }
    }

    func testUncreatableOutputParentReportsOutputParentUnavailable() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let input = try fixtureURL("sample", extension: "ts")
        let parentFile = workspace.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: parentFile)
        let output = parentFile.appendingPathComponent("output.mp4")

        do {
            _ = try await HLSRemuxer().remuxTS(input: input, output: output)
            XCTFail("Expected output parent error")
        } catch let error as HLSRemuxError {
            XCTAssertEqual(error, .outputParentUnavailable(output.deletingLastPathComponent()))
        }
    }

    func testOverlappingCallReportsOperationInProgress() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let input = try makeExpandedPlaylist(in: workspace, segmentCount: 2_000)
        let firstOutput = workspace.appendingPathComponent("first.mp4")
        let secondOutput = workspace.appendingPathComponent("second.mp4")
        let remuxer = HLSRemuxer()
        let started = expectation(description: "first remux started")
        let didSignal = LockedFlag()
        let firstTask = Task {
            try await remuxer.remuxFMP4Playlist(input: input, output: firstOutput) { progress in
                if progress.processedBytes > 0 && didSignal.setIfFalse() {
                    started.fulfill()
                }
            }
        }

        await fulfillment(of: [started], timeout: 5)
        do {
            _ = try await remuxer.remuxFMP4Playlist(input: input, output: secondOutput)
            XCTFail("Expected overlapping operation error")
        } catch let error as HLSRemuxError {
            XCTAssertEqual(error, .operationInProgress)
        }

        remuxer.cancel()
        do {
            _ = try await firstTask.value
            XCTFail("Expected first remux to be cancelled")
        } catch let error as HLSRemuxError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    private func assertPlayableAudioVideo(_ result: HLSRemuxResult) async throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path))
        XCTAssertGreaterThan(result.sizeBytes, 0)

        let asset = AVURLAsset(url: result.outputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertFalse(videoTracks.isEmpty)
        XCTAssertFalse(audioTracks.isEmpty)
    }

    private func fixtureURL(_ name: String, extension pathExtension: String?) throws -> URL {
        let url = Bundle.module.url(
            forResource: name,
            withExtension: pathExtension,
            subdirectory: "Fixtures"
        )
        return try XCTUnwrap(url, "Missing fixture: \(name)")
    }

    private func makeWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HLSRemuxKitIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeExpandedPlaylist(in workspace: URL, segmentCount: Int) throws -> URL {
        let fixtureDirectory = try fixtureURL("fmp4", extension: nil)
        let inputDirectory = workspace.appendingPathComponent("expanded-fmp4", isDirectory: true)
        try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: fixtureDirectory.appendingPathComponent("init.mp4"),
            to: inputDirectory.appendingPathComponent("init.mp4")
        )
        try FileManager.default.copyItem(
            at: fixtureDirectory.appendingPathComponent("segment0.m4s"),
            to: inputDirectory.appendingPathComponent("segment0.m4s")
        )

        var playlist = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:3
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXT-X-MAP:URI="init.mp4"

        """
        for _ in 0..<segmentCount {
            playlist += "#EXTINF:2.000000,\nsegment0.m4s\n"
        }
        playlist += "#EXT-X-ENDLIST\n"

        let playlistURL = inputDirectory.appendingPathComponent("index.m3u8")
        try Data(playlist.utf8).write(to: playlistURL)
        return playlistURL
    }

    private func temporaryOutputs(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(".remux.mp4") }
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func setIfFalse() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !storage else { return false }
        storage = true
        return true
    }
}
#endif
