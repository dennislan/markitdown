import Foundation
import UniformTypeIdentifiers

struct FileManagerService {
    static let supportedExtensions: Set<String> = [
        "pdf", "docx", "doc", "pptx", "ppt", "xlsx", "xls",
        "csv", "json", "xml", "html", "htm",
        "jpg", "jpeg", "png", "gif", "bmp", "tiff",
        "wav", "mp3", "epub", "zip", "msg", "eml"
    ]

    static let supportedUTTypes: [UTType] = {
        var types: [UTType] = []
        for ext in supportedExtensions {
            if let utType = UTType(filenameExtension: ext) {
                types.append(utType)
            }
        }
        return types
    }()

    static func isSupportedFormat(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    func processURLs(_ urls: [URL]) -> [FileItem] {
        var items: [FileItem] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                items.append(contentsOf: scanDirectory(url))
            } else {
                items.append(FileItem(url: url))
            }
        }
        return items
    }

    private func scanDirectory(_ directoryURL: URL) -> [FileItem] {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var items: [FileItem] = []
        for case let url as URL in enumerator {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                if Self.isSupportedFormat(url) {
                    items.append(FileItem(url: url))
                }
            }
        }
        return items
    }

    func resolveOutputURL(for file: FileItem, strategy: OutputStrategy, customDirectory: URL?, sourceBaseDirectory: URL?) -> URL? {
        switch strategy {
        case .sameDirectory:
            return file.url.deletingLastPathComponent().appendingPathComponent(file.outputFileName)

        case .customDirectory:
            guard let dir = customDirectory else { return nil }
            return dir.appendingPathComponent(file.outputFileName)

        case .customDirectoryPreserveStructure:
            guard let dir = customDirectory, let base = sourceBaseDirectory else { return nil }
            let relativePath = file.url.deletingLastPathComponent().path
                .replacingOccurrences(of: base.path + "/", with: "")
                .replacingOccurrences(of: base.path, with: "")
            let outputDir = dir.appendingPathComponent(relativePath)
            try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            return outputDir.appendingPathComponent(file.outputFileName)
        }
    }

    func writeMarkdown(_ content: String, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
