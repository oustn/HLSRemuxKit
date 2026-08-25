import Foundation

public enum OutputTransactionError: Error, Sendable, Equatable {
    case outputMissing(URL)
}

public struct OutputTransaction: @unchecked Sendable {
    public let destination: URL
    public let temporaryURL: URL

    private let fileManager: FileManager

    public init(destination: URL, fileManager: FileManager = .default) {
        self.destination = destination
        self.fileManager = fileManager

        let baseName = destination.deletingPathExtension().lastPathComponent
        let temporaryName = ".\(baseName).\(UUID().uuidString).remux.mp4"
        self.temporaryURL = destination.deletingLastPathComponent()
            .appendingPathComponent(temporaryName, isDirectory: false)
    }

    public func commit() throws {
        guard fileManager.fileExists(atPath: temporaryURL.path) else {
            throw OutputTransactionError.outputMissing(temporaryURL)
        }

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destination)
        }
    }

    public func rollback() {
        try? fileManager.removeItem(at: temporaryURL)
    }
}
