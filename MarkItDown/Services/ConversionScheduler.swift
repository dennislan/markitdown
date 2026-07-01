import Foundation

struct ConversionConfig {
    let outputStrategy: OutputStrategy
    let customOutputDirectory: URL?
    let sourceBaseDirectory: URL?
    let concurrency: Int

    // Advanced settings
    let enableLLM: Bool
    let llmApiKey: String?
    let llmModel: String
    let enableOCR: Bool
    let enableAzure: Bool
    let azureEndpoint: String?
    let azureApiKey: String?
    let customLLMPrompt: String

    init(outputStrategy: OutputStrategy = .sameDirectory,
         customOutputDirectory: URL? = nil,
         sourceBaseDirectory: URL? = nil,
         concurrency: Int = 4,
         enableLLM: Bool = false,
         llmApiKey: String? = nil,
         llmModel: String = "gpt-4o",
         enableOCR: Bool = false,
         enableAzure: Bool = false,
         azureEndpoint: String? = nil,
         azureApiKey: String? = nil,
         customLLMPrompt: String = "") {
        self.outputStrategy = outputStrategy
        self.customOutputDirectory = customOutputDirectory
        self.sourceBaseDirectory = sourceBaseDirectory
        self.concurrency = max(1, min(8, concurrency))
        self.enableLLM = enableLLM
        self.llmApiKey = llmApiKey
        self.llmModel = llmModel
        self.enableOCR = enableOCR
        self.enableAzure = enableAzure
        self.azureEndpoint = azureEndpoint
        self.azureApiKey = azureApiKey
        self.customLLMPrompt = customLLMPrompt
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
                        let markdown = try await self._convertWithOptions(
                            file.url.path,
                            config: config
                        )

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

    private func _convertWithOptions(
        _ filePath: String,
        config: ConversionConfig
    ) async throws -> String {
        // If any advanced option is enabled, use the advanced path
        let anyAdvancedEnabled = config.enableLLM && config.llmApiKey != nil && !config.llmApiKey!.isEmpty
            || config.enableOCR
            || (config.enableAzure && config.azureApiKey != nil && !config.azureApiKey!.isEmpty)

        if anyAdvancedEnabled {
            return try await self.proxy.convertFileWithOptions(
                filePath,
                enableLLM: config.enableLLM,
                llmApiKey: config.llmApiKey,
                llmModel: config.llmModel,
                enableOCR: config.enableOCR,
                enableAzure: config.enableAzure,
                azureEndpoint: config.azureEndpoint,
                azureApiKey: config.azureApiKey,
                customPrompt: config.customLLMPrompt
            )
        }

        // Fallback to basic conversion
        return try await self.proxy.convertFile(filePath)
    }
}
