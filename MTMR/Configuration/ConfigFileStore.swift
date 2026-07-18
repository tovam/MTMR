import Foundation

protocol ConfigFileStoring: Sendable {
    func read(from url: URL) throws -> Data
    func writeAtomically(_ data: Data, to url: URL) throws
}

struct FileConfigStore: ConfigFileStoring {
    func read(from url: URL) throws -> Data {
        try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
    }
}
