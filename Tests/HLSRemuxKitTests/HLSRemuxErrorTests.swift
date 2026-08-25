import Foundation
import Testing
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
}
