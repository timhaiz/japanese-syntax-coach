import Darwin
import Foundation

struct DownloadedTextbookStore {
    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Textbooks", isDirectory: true)
    }

    func load(id: String) throws -> TextbookPackage? {
        let url = try fileURL(id: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let package = try JSONDecoder().decode(TextbookPackage.self, from: Data(contentsOf: url))
        guard package.textbook.id == id else { throw CocoaError(.fileReadCorruptFile) }
        return package
    }

    func save(_ package: TextbookPackage) throws {
        let url = try fileURL(id: package.textbook.id)
        let data = try JSONEncoder().encode(package)
        _ = try JSONDecoder().decode(TextbookPackage.self, from: data)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL)
        guard rename(temporaryURL.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func remove(id: String) throws {
        let url = try fileURL(id: id)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    func contains(id: String) -> Bool {
        (try? load(id: id)) != nil
    }

    private func fileURL(id: String) throws -> URL {
        guard id.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", options: .regularExpression) != nil else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return directory.appendingPathComponent(id).appendingPathExtension("json")
    }
}
