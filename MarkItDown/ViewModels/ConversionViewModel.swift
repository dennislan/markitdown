import SwiftUI
import AppKit

class ConversionViewModel: ObservableObject {
    @Published var files: [FileItem] = []
    @Published var outputStrategy: OutputStrategy = .sameDirectory {
        didSet { UserDefaults.standard.set(outputStrategy.rawValue, forKey: "outputStrategy") }
    }
    @Published var customOutputDirectory: URL?
    @Published var isConverting = false
    @Published var startTime: Date?
    @Published var toastMessage: String?

    private let scheduler = ConversionScheduler()
    private let fileManager = FileManagerService()

    init() {
        if let saved = UserDefaults.standard.string(forKey: "outputStrategy"),
           let strategy = OutputStrategy(rawValue: saved) {
            self.outputStrategy = strategy
        }
        if let savedPath = UserDefaults.standard.url(forKey: "customOutputDirectory") {
            self.customOutputDirectory = savedPath
        }
    }

    var progress: Double {
        guard !files.isEmpty else { return 0 }
        let completed = files.filter { $0.status == .completed || $0.status == .failed }.count
        return Double(completed) / Double(files.count)
    }

    var progressText: String {
        let completed = files.filter { $0.status == .completed }.count
        let failed = files.filter { $0.status == .failed }.count
        let total = files.count
        if total == 0 { return "" }
        var text = "\(completed)/\(total) 已完成"
        if failed > 0 { text += " (\(failed) 失败)" }
        if isConverting {
            let pct = Int(progress * 100)
            text += " (\(pct)%)"
        }
        return text
    }

    var elapsedTimeString: String {
        guard let start = startTime else { return "0s" }
        let interval = Date().timeIntervalSince(start)
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }

    func addFilesFromURLs(_ urls: [URL]) {
        let newItems = fileManager.processURLs(urls)
        let existingPaths = Set(files.map { $0.url.resolvingSymlinksInPath().path })
        let uniqueItems = newItems.filter { !existingPaths.contains($0.url.resolvingSymlinksInPath().path) }

        if uniqueItems.count < newItems.count {
            let skipped = newItems.count - uniqueItems.count
            showToast("已跳过 \(skipped) 个重复文件")
        }

        let validItems = uniqueItems.filter { FileManagerService.isSupportedFormat($0.url) }
        let unsupportedSkipped = uniqueItems.count - validItems.count
        if unsupportedSkipped > 0 {
            showToast("已跳过 \(unsupportedSkipped) 个不支持的格式")
        }

        files.append(contentsOf: validItems)
    }

    func selectFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = FileManagerService.supportedUTTypes

        guard panel.runModal() == .OK else { return }
        addFilesFromURLs(panel.urls)
    }

    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        addFilesFromURLs([url])
    }

    func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        customOutputDirectory = url
        UserDefaults.standard.set(url, forKey: "customOutputDirectory")
    }

    func startConversion() {
        guard !files.isEmpty, !isConverting else { return }

        let pendingFiles = files.filter { $0.status == .pending || $0.status == .failed }
        guard !pendingFiles.isEmpty else { return }

        isConverting = true
        startTime = Date()

        let sourceBase = inferSourceBaseDirectory(from: pendingFiles)

        let config = ConversionConfig(
            outputStrategy: outputStrategy,
            customOutputDirectory: customOutputDirectory,
            sourceBaseDirectory: sourceBase,
            concurrency: Int(UserDefaults.standard.double(forKey: "concurrency").rounded())
        )

        Task { @MainActor in
            await scheduler.convert(files: pendingFiles, config: config) { [weak self] itemId, status, outputURL, error in
                guard let self else { return }
                guard let index = self.files.firstIndex(where: { $0.id == itemId }) else { return }
                var file = self.files[index]
                file.status = status
                file.outputURL = outputURL
                file.errorMessage = error
                self.files[index] = file
                self.objectWillChange.send()

                if self.files.allSatisfy({ $0.status == .completed || $0.status == .failed }) {
                    self.isConverting = false

                    if UserDefaults.standard.bool(forKey: "autoOpenOutput") {
                        self.openOutputFolder()
                    }

                    if UserDefaults.standard.bool(forKey: "sendNotification") {
                        let completed = self.files.filter { $0.status == .completed }.count
                        let failed = self.files.filter { $0.status == .failed }.count
                        NotificationService.send(title: "转换完成", body: "成功 \(completed) 个" + (failed > 0 ? "，失败 \(failed) 个" : ""))
                    }
                }
            }
        }
    }

    func retryFile(_ file: FileItem) {
        guard let index = files.firstIndex(where: { $0.id == file.id }) else { return }
        var updated = files[index]
        updated.status = .pending
        updated.errorMessage = nil
        files[index] = updated
        objectWillChange.send()

        if !isConverting {
            startConversion()
        }
    }

    func removeFile(_ file: FileItem) {
        files.removeAll { $0.id == file.id }
    }

    func clearFiles() {
        if isConverting { return }
        files.removeAll()
        startTime = nil
    }

    func openOutputFolder() {
        switch outputStrategy {
        case .sameDirectory:
            if let firstCompleted = files.first(where: { $0.status == .completed && $0.outputURL != nil }),
               let outputURL = firstCompleted.outputURL {
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            }
        case .customDirectory, .customDirectoryPreserveStructure:
            if let dir = customOutputDirectory {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
            }
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.toastMessage = nil
        }
    }

    private func inferSourceBaseDirectory(from files: [FileItem]) -> URL? {
        guard !files.isEmpty else { return nil }
        let directories = Set(files.map { $0.url.deletingLastPathComponent() })
        if directories.count == 1 { return directories.first }
        var common = files[0].url.deletingLastPathComponent().path
        for file in files.dropFirst() {
            let dir = file.url.deletingLastPathComponent().path
            while !dir.hasPrefix(common) && !common.isEmpty {
                common = String(common.dropLast(1))
            }
        }
        return common.isEmpty ? nil : URL(fileURLWithPath: common)
    }
}
