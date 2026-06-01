import Foundation

/// CSV ファイルへ追記保存する軽量ロガー
final class CSVLogger {
    private let headers: [String]
    private let fileURL: URL
    private let queue = DispatchQueue(label: "CSVLogger.queue")
    private var fileHandle: FileHandle?
    private var buffer = ""

    init(fileURL: URL, headers: [String]) throws {
        self.fileURL = fileURL
        self.headers = headers

        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        fileHandle = try FileHandle(forWritingTo: fileURL)
        try writeLine(headers)
    }

    deinit {
        try? close()
    }

    func appendRow(_ row: [String: String]) throws {
        let values = headers.map { key in
            escape(row[key] ?? "")
        }
        try writeLine(values)
    }

    func appendRawLine(_ values: [String]) throws {
        try writeLine(values.map(escape))
    }

    func flush() throws {
        try queue.sync {
            try flushLocked()
        }
    }

    func close() throws {
        try queue.sync {
            try flushLocked()
            try fileHandle?.synchronize()
            try fileHandle?.close()
            fileHandle = nil
        }
    }

    private func writeLine(_ values: [String]) throws {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.buffer.append(values.joined(separator: ","))
            self.buffer.append("\n")
        }
    }

    private func flushLocked() throws {
        guard let fileHandle else { return }
        guard !buffer.isEmpty else { return }
        guard let data = buffer.data(using: .utf8) else { return }
        fileHandle.seekToEndOfFile()
        fileHandle.write(data)
        buffer.removeAll(keepingCapacity: true)
    }

    private func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
