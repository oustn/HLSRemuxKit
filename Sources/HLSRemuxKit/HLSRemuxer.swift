import Foundation
import HLSRemuxCore
#if canImport(ffmpegkit)
import ffmpegkit
#endif

public struct HLSRemuxProgress: Sendable, Equatable {
    public let processedBytes: Int64
    public let elapsedSeconds: Double
    public let speed: Double

    public init(processedBytes: Int64, elapsedSeconds: Double, speed: Double) {
        self.processedBytes = processedBytes
        self.elapsedSeconds = elapsedSeconds
        self.speed = speed
    }
}

public struct HLSRemuxResult: Sendable, Equatable {
    public let outputURL: URL
    public let sizeBytes: Int64
    public let durationSeconds: Double

    public init(outputURL: URL, sizeBytes: Int64, durationSeconds: Double) {
        self.outputURL = outputURL
        self.sizeBytes = sizeBytes
        self.durationSeconds = durationSeconds
    }
}

public enum HLSRemuxError: LocalizedError, Sendable, Equatable {
    case inputMissing(URL)
    case outputParentUnavailable(URL)
    case failed(String)
    case cancelled
    case outputMissing(URL)

    public var errorDescription: String? {
        switch self {
        case .inputMissing(let url): return "封装输入不存在：\(url.lastPathComponent)"
        case .outputParentUnavailable(let url): return "无法创建输出目录：\(url.path)"
        case .failed(let message): return "无损封装失败：\(message)"
        case .cancelled: return "无损封装已取消"
        case .outputMissing(let url): return "封装没有生成输出文件：\(url.lastPathComponent)"
        }
    }
}

public final class HLSRemuxer: @unchecked Sendable {
    private let lock = NSLock()
#if canImport(ffmpegkit)
    private var activeSession: FFmpegSession?
#endif

    public init() {}

    public func remuxTS(
        input: URL,
        output: URL,
        progress: (@Sendable (HLSRemuxProgress) -> Void)? = nil
    ) async throws -> HLSRemuxResult {
        try await execute(input: input, output: output, kind: .transportStream, progress: progress)
    }

    public func remuxFMP4Playlist(
        input: URL,
        output: URL,
        progress: (@Sendable (HLSRemuxProgress) -> Void)? = nil
    ) async throws -> HLSRemuxResult {
        try await execute(input: input, output: output, kind: .fragmentedMP4Playlist, progress: progress)
    }

    public func cancel() {
#if canImport(ffmpegkit)
        lock.lock()
        let session = activeSession
        lock.unlock()
        session?.cancel()
#endif
    }

    private func execute(
        input: URL,
        output: URL,
        kind: RemuxInputKind,
        progress: (@Sendable (HLSRemuxProgress) -> Void)?
    ) async throws -> HLSRemuxResult {
#if canImport(ffmpegkit)
        guard FileManager.default.fileExists(atPath: input.path) else {
            throw HLSRemuxError.inputMissing(input)
        }
        do {
            try FileManager.default.createDirectory(
                at: output.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw HLSRemuxError.outputParentUnavailable(output.deletingLastPathComponent())
        }
        try? FileManager.default.removeItem(at: output)

        let arguments = RemuxCommand.arguments(input: input, output: output, kind: kind)
        let start = Date()

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let complete: FFmpegSessionCompleteCallback = { [weak self] session in
                    guard let session else {
                        self?.clear()
                        continuation.resume(throwing: HLSRemuxError.failed("FFmpeg 会话没有返回结果"))
                        return
                    }
                    self?.clear()
                    let state = session.getState()
                    if state == SessionState.completed,
                       let returnCode = session.getReturnCode(),
                       returnCode.isValueSuccess(),
                       FileManager.default.fileExists(atPath: output.path) {
                        let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value ?? 0
                        continuation.resume(returning: HLSRemuxResult(
                            outputURL: output,
                            sizeBytes: size,
                            durationSeconds: Date().timeIntervalSince(start)
                        ))
                    } else if state == SessionState.completed,
                              let returnCode = session.getReturnCode(),
                              returnCode.isValueCancel() {
                        try? FileManager.default.removeItem(at: output)
                        continuation.resume(throwing: HLSRemuxError.cancelled)
                    } else {
                        try? FileManager.default.removeItem(at: output)
                        let details = session.getFailStackTrace() ?? session.getOutput() ?? "未知错误"
                        continuation.resume(throwing: HLSRemuxError.failed(details))
                    }
                }
                let statistics: StatisticsCallback? = progress.map { callback in
                    { statistics in
                        guard let statistics else { return }
                        callback(HLSRemuxProgress(
                            processedBytes: Int64(statistics.getSize()),
                            elapsedSeconds: statistics.getTime() / 1000,
                            speed: statistics.getSpeed()
                        ))
                    }
                }
                guard let session = FFmpegKit.execute(
                    withArgumentsAsync: arguments,
                    withCompleteCallback: complete,
                    withLogCallback: nil,
                    withStatisticsCallback: statistics
                ) else {
                    continuation.resume(throwing: HLSRemuxError.failed("无法创建 FFmpeg 会话"))
                    return
                }
                self.set(session: session)
                progress?(HLSRemuxProgress(processedBytes: 0, elapsedSeconds: 0, speed: 0))
            }
        }, onCancel: { [weak self] in
            self?.cancel()
        })
#else
        _ = (input, output, kind, progress)
        throw HLSRemuxError.failed("HLSRemuxKit 的 FFmpeg 二进制仅支持 iOS 目标")
#endif
    }

#if canImport(ffmpegkit)
    private func set(session: FFmpegSession) {
        lock.lock()
        activeSession = session
        lock.unlock()
    }

    private func clear() {
        lock.lock()
        activeSession = nil
        lock.unlock()
    }
#endif
}
