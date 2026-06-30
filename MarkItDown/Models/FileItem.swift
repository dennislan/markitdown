import Foundation

struct FileItem: Identifiable {
    let id: UUID
    let url: URL
    let fileName: String
    let fileExtension: String
    let fileSize: Int64
    var status: ConversionStatus
    var errorMessage: String?
    var outputURL: URL?

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.fileName = url.lastPathComponent
        self.fileExtension = url.pathExtension.lowercased()
        self.fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        self.status = .pending
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var outputFileName: String {
        url.deletingPathExtension().lastPathComponent + ".md"
    }
}
