import Foundation

struct ConversionConfig {
    let outputStrategy: OutputStrategy
    let customOutputDirectory: URL?
    let sourceBaseDirectory: URL?
    let concurrency: Int

    init(outputStrategy: OutputStrategy = .sameDirectory,
         customOutputDirectory: URL? = nil,
         sourceBaseDirectory: URL? = nil,
         concurrency: Int = 4) {
        self.outputStrategy = outputStrategy
        self.customOutputDirectory = customOutputDirectory
        self.sourceBaseDirectory = sourceBaseDirectory
        self.concurrency = max(1, min(8, concurrency))
    }
}

actor ConversionScheduler {
    private let proxy = MarkItDownProxy()
    private let fileManager = FileManagerService()

    func convert(files: [FileItem], config: ConversionConfig,
                 onStatusUpdate: @escaping @Sendable (UUID, ConversionStatus, URL?, String?) -> Void) async {
        let semaphore = AsyncSemaphore(value: config.concurrency)

        await withTaskGroup(of: Void.self) { group in
            for file in files {
                let config = config
                group.addTask {
                    await semaphore.wait()
                    defer { semaphore.signal() }

                    await MainActor.run {
                        onStatusUpdate(file.id, .converting, nil, nil)
                    }

                    do {
                        let markdown = try await self.proxy.convertFile(file.url.path)

                        guard let outputURL = self.fileManager.resolveOutputURL(
                            for: file, strategy: config.outputStrategy,
                            customDirectory: config.customOutputDirectory,
                            sourceBaseDirectory: config.sourceBaseDirectory
                        ) else {
                            await MainActor.run {
                                onStatusUpdate(file.id, .failed, nil, "无法确定输出路径")
                            }
                            return
                        }

                        try self.fileManager.writeMarkdown(markdown, to: outputURL)

                        await MainActor.run {
                            onStatusUpdate(file.id, .completed, outputURL, nil)
                        }
                    } catch {
                        await MainActor.run {
                            onStatusUpdate(file.id, .failed, nil, error.localizedDescription)
                        }
                    }
                }
            }
        }
    }
}
