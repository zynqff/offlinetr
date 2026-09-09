import Foundation
import CryptoKit

actor ModelStore {
    private let modelsDirectory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        modelsDirectory = base.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    func localURL(fileName: String) -> URL {
        modelsDirectory.appendingPathComponent(fileName)
    }

    func exists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: localURL(fileName: fileName).path)
    }

    func remove(fileName: String) throws {
        let url = localURL(fileName: fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func verify(url: URL, expectedSize: Int64, expectedSHA256: String?) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attrs[.size] as? NSNumber, expectedSize > 0, size.int64Value != expectedSize {
            throw ModelStoreError.integrity
        }
        if let expectedSHA256, !expectedSHA256.isEmpty {
            let data = try Data(contentsOf: url)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard hash.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
                throw ModelStoreError.integrity
            }
        }
    }

    func commit(downloadedFile: URL, fileName: String) throws -> URL {
        let destination = localURL(fileName: fileName)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: downloadedFile, to: destination)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = destination
        try? mutable.setResourceValues(values)
        return destination
    }
}

enum ModelStoreError: LocalizedError {
    case integrity
    var errorDescription: String? { "Файл модели не прошёл проверку целостности." }
}
