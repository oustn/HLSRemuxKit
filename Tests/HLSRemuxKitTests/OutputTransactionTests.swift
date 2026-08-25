import Foundation
import Testing
@testable import HLSRemuxCore

struct OutputTransactionTests {
    @Test func allocatesUniqueTemporaryMP4BesideDestination() throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("result.mp4")

        let first = OutputTransaction(destination: destination)
        let second = OutputTransaction(destination: destination)

        #expect(first.temporaryURL.deletingLastPathComponent() == directory)
        #expect(first.temporaryURL.pathExtension == "mp4")
        #expect(first.temporaryURL != second.temporaryURL)
    }

    @Test func commitAtomicallyReplacesExistingDestination() throws {
        let transaction = try makeTransaction(existingDestination: Data("old".utf8))
        defer { try? FileManager.default.removeItem(at: transaction.destination.deletingLastPathComponent()) }
        try Data("new".utf8).write(to: transaction.temporaryURL)

        try transaction.commit()

        #expect(try Data(contentsOf: transaction.destination) == Data("new".utf8))
        #expect(!FileManager.default.fileExists(atPath: transaction.temporaryURL.path))
    }

    @Test func commitMovesOutputWhenDestinationDoesNotExist() throws {
        let transaction = try makeTransaction(existingDestination: nil)
        defer { try? FileManager.default.removeItem(at: transaction.destination.deletingLastPathComponent()) }
        try Data("new".utf8).write(to: transaction.temporaryURL)

        try transaction.commit()

        #expect(try Data(contentsOf: transaction.destination) == Data("new".utf8))
        #expect(!FileManager.default.fileExists(atPath: transaction.temporaryURL.path))
    }

    @Test func rollbackPreservesExistingDestination() throws {
        let transaction = try makeTransaction(existingDestination: Data("old".utf8))
        defer { try? FileManager.default.removeItem(at: transaction.destination.deletingLastPathComponent()) }
        try Data("partial".utf8).write(to: transaction.temporaryURL)

        transaction.rollback()

        #expect(try Data(contentsOf: transaction.destination) == Data("old".utf8))
        #expect(!FileManager.default.fileExists(atPath: transaction.temporaryURL.path))
    }

    @Test func commitReportsMissingTemporaryOutput() throws {
        let transaction = try makeTransaction(existingDestination: Data("old".utf8))
        defer { try? FileManager.default.removeItem(at: transaction.destination.deletingLastPathComponent()) }

        #expect(throws: OutputTransactionError.outputMissing(transaction.temporaryURL)) {
            try transaction.commit()
        }
        #expect(try Data(contentsOf: transaction.destination) == Data("old".utf8))
    }

    private func makeTransaction(existingDestination data: Data?) throws -> OutputTransaction {
        let directory = try makeTestDirectory()
        let destination = directory.appendingPathComponent("result.mp4")
        if let data {
            try data.write(to: destination)
        }
        return OutputTransaction(destination: destination)
    }

    private func makeTestDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HLSRemuxKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
