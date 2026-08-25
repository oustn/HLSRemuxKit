import Foundation
import Testing
@testable import HLSRemuxCore
@testable import HLSRemuxKit

struct HLSRemuxErrorTests {
    @Test func operationInProgressHasActionableDescription() {
        #expect(HLSRemuxError.operationInProgress.errorDescription == "已有无损封装任务正在运行")
    }

    @Test func URLBearingErrorsRemainEquatable() {
        let url = URL(fileURLWithPath: "/tmp/media.ts")

        #expect(HLSRemuxError.inputMissing(url) == .inputMissing(url))
        #expect(HLSRemuxError.outputParentUnavailable(url) == .outputParentUnavailable(url))
        #expect(HLSRemuxError.outputMissing(url) == .outputMissing(url))
    }

    @Test func successfulSessionWithoutTemporaryOutputMapsToOutputMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HLSRemuxErrorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("output.mp4")
        let transaction = OutputTransaction(destination: output)

        #expect(throws: HLSRemuxError.outputMissing(output)) {
            try HLSRemuxer.installSuccessfulOutput(
                transaction: transaction,
                output: output,
                startedAt: Date()
            )
        }
    }
}
