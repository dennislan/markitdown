import Foundation

actor MarkItDownProxy {
    private let pythonURL: URL
    private let sitePackagesPath: String

    init() {
        // Resolve Python from the app bundle's embedded Resources directory.
        // During development (not from a .app bundle), fall back to the local venv.
        let bundleURL = Bundle.main.bundleURL
        let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources/python")

        if FileManager.default.fileExists(atPath: resourcesURL.path) {
            self.pythonURL = resourcesURL.appendingPathComponent("markitdown-env/bin/python3")
            self.sitePackagesPath = resourcesURL.path + "/markitdown-env/lib/python3.14/site-packages"
        } else {
            // Development fallback: use local venv
            let envPath = "/Users/dennis/AIProjects/markitdown/markitdown-env"
            self.pythonURL = URL(fileURLWithPath: "\(envPath)/bin/python3")
            self.sitePackagesPath = "\(envPath)/lib/python3.14/site-packages"
        }
    }

    // MARK: - Public async entry points (capture actor state, dispatch to nonisolated workers)

    func convertFile(_ filePath: String) async throws -> String {
        let pyURL = pythonURL
        let spPath = sitePackagesPath
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self._runConvert(filePath: filePath, pythonURL: pyURL, sitePackagesPath: spPath)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func convertFileWithLLM(_ filePath: String, apiKey: String, model: String) async throws -> String {
        let pyURL = pythonURL
        let spPath = sitePackagesPath
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self._runConvertWithLLM(filePath: filePath, apiKey: apiKey, model: model, pythonURL: pyURL, sitePackagesPath: spPath)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func convertFileWithOptions(
        _ filePath: String,
        enableLLM: Bool,
        llmApiKey: String?,
        llmModel: String,
        enableOCR: Bool,
        enableAzure: Bool,
        azureEndpoint: String?,
        azureApiKey: String?,
        customPrompt: String
    ) async throws -> String {
        let pyURL = pythonURL
        let spPath = sitePackagesPath
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self._runConvertWithOptions(
                        filePath: filePath,
                        enableLLM: enableLLM,
                        llmApiKey: llmApiKey,
                        llmModel: llmModel,
                        enableOCR: enableOCR,
                        enableAzure: enableAzure,
                        azureEndpoint: azureEndpoint,
                        azureApiKey: azureApiKey,
                        customPrompt: customPrompt,
                        pythonURL: pyURL,
                        sitePackagesPath: spPath
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Static helpers (for AdvancedSettingsConfig)

    static func pythonBinaryURL() -> URL {
        let bundleURL = Bundle.main.bundleURL
        let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources/python")
        if FileManager.default.fileExists(atPath: resourcesURL.path) {
            return resourcesURL.appendingPathComponent("markitdown-env/bin/python3")
        }
        let envPath = "/Users/dennis/AIProjects/markitdown/markitdown-env"
        return URL(fileURLWithPath: "\(envPath)/bin/python3")
    }

    static func runSilentPython(pythonURL: URL, script: String) throws -> String {
        let process = Process()
        process.executableURL = pythonURL
        process.arguments = ["-c", script]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw MarkItDownError.conversionFailed("Python error: \(errorOutput)")
        }

        return String(data: outputData, encoding: .utf8) ?? ""
    }

    // MARK: - Nonisolated private conversion implementations

    private nonisolated func _runConvert(
        filePath: String,
        pythonURL: URL,
        sitePackagesPath: String
    ) throws -> String {
        // Legacy .doc files are not supported by markitdown — fall back to macOS textutil.
        if filePath.lowercased().hasSuffix(".doc") {
            return try _convertWithTextutil(filePath: filePath)
        }

        let escapedPath = filePath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        import sys
        sys.path.insert(0, "\(sitePackagesPath)")
        from markitdown import MarkItDown
        md = MarkItDown(enable_plugins=False)
        result = md.convert("\(escapedPath)", keep_data_uris=True)
        sys.stdout.write(result.text_content)
        """

        return try _runPython(script: script, filePath: filePath, pythonURL: pythonURL)
    }

    private nonisolated func _runConvertWithLLM(
        filePath: String,
        apiKey: String,
        model: String,
        pythonURL: URL,
        sitePackagesPath: String
    ) throws -> String {
        // Legacy .doc files are not supported by markitdown — fall back to macOS textutil.
        if filePath.lowercased().hasSuffix(".doc") {
            return try _convertWithTextutil(filePath: filePath)
        }

        let escapedPath = filePath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedKey = apiKey.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escapedModel = model.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        import sys
        sys.path.insert(0, "\(sitePackagesPath)")
        from markitdown import MarkItDown
        from openai import OpenAI
        client = OpenAI(api_key="\(escapedKey)")
        md = MarkItDown(llm_client=client, llm_model="\(escapedModel)")
        result = md.convert("\(escapedPath)", keep_data_uris=True)
        sys.stdout.write(result.text_content)
        """

        return try _runPython(script: script, filePath: filePath, pythonURL: pythonURL)
    }

    private nonisolated func _runConvertWithOptions(
        filePath: String,
        enableLLM: Bool,
        llmApiKey: String?,
        llmModel: String,
        enableOCR: Bool,
        enableAzure: Bool,
        azureEndpoint: String?,
        azureApiKey: String?,
        customPrompt: String,
        pythonURL: URL,
        sitePackagesPath: String
    ) throws -> String {
        // Legacy .doc files are not supported by markitdown — fall back to macOS textutil.
        if filePath.lowercased().hasSuffix(".doc") {
            return try _convertWithTextutil(filePath: filePath)
        }

        let escapedPath = filePath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

        var parts = [String]()
        parts.append("import sys")
        parts.append("sys.path.insert(0, \"\(sitePackagesPath)\")")
        parts.append("from markitdown import MarkItDown")

        // Build kwargs list for MarkItDown constructor
        var kwargs = [String]()

        // --- LLM Image Description ---
        if enableLLM, let apiKey = llmApiKey, !apiKey.isEmpty {
            let escapedKey = apiKey.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let escapedModel = llmModel.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

            kwargs.append("llm_client=__llm_client")
            kwargs.append("llm_model=\"\(escapedModel)\"")

            parts.append("from openai import OpenAI")
            parts.append("__llm_client = OpenAI(api_key=\"\(escapedKey)\")")
        }

        // --- Azure Document Intelligence ---
        if enableAzure, let endpoint = azureEndpoint, !endpoint.isEmpty,
           let azureKey = azureApiKey, !azureKey.isEmpty {
            let escapedEndpoint = endpoint.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let escapedAzureKey = azureKey.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

            kwargs.append("azure_endpoint=\"\(escapedEndpoint)\"")
            kwargs.append("azure_api_key=\"\(escapedAzureKey)\"")

            parts.append("from azure.ai.documentintelligence import DocumentIntelligenceClient")
            parts.append("from azure.core.credentials import AzureKeyCredential")
            parts.append("__azure_client = DocumentIntelligenceClient(")
            parts.append("    endpoint=\"\(escapedEndpoint)\",")
            parts.append("    credential=AzureKeyCredential(\"\(escapedAzureKey)\")")
            parts.append(")")
        }

        // --- OCR Plugin ---
        if enableOCR {
            kwargs.append("enable_plugins=True")
        }

        // Build the MarkItDown constructor call
        if kwargs.isEmpty {
            parts.append("md = MarkItDown(enable_plugins=False)")
        } else {
            let kwargStr = kwargs.joined(separator: ", ")
            parts.append("md = MarkItDown(\(kwargStr))")
        }

        // --- Execute conversion ---
        if enableLLM && !customPrompt.isEmpty {
            let escapedPrompt = customPrompt.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            parts.append("")
            parts.append("__custom_prompt = \"\(escapedPrompt)\"")
            parts.append("_result = md.convert(\"\(escapedPath)\", keep_data_uris=True)")
            parts.append("_text = _result.text_content")
            parts.append("# Inject custom prompt into image description section")
            parts.append("__marker = '\\n---\\n[Image Description]\\n---\\n'")
            parts.append("if __marker in _text:")
            parts.append("    _text = _text.replace(__marker, __custom_prompt + __marker)")
            parts.append("elif '[LLM image description]' in _text:")
            parts.append("    _text = _text.replace('[LLM image description]', __custom_prompt)")
            parts.append("_result._text_content = _text")
            parts.append("sys.stdout.write(_result.text_content)")
        } else {
            parts.append("result = md.convert(\"\(escapedPath)\", keep_data_uris=True)")
            parts.append("sys.stdout.write(result.text_content)")
        }

        let script = parts.joined(separator: "\n")
        return try _runPython(script: script, filePath: filePath, pythonURL: pythonURL)
    }

    /// Fallback converter for legacy .doc files using macOS textutil.
    private nonisolated func _convertWithTextutil(filePath: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "txt", "-stdout", filePath]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw MarkItDownError.conversionFailed(
                "文件: \(filePath)\n无法启动 textutil: \(error.localizedDescription)"
            )
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw MarkItDownError.conversionFailed(
                "文件: \(filePath)\n" +
                "textutil 失败 (退出码: \(process.terminationStatus))\n" +
                (errorOutput.isEmpty ? "" : "stderr:\n\(errorOutput.prefix(500))")
            )
        }

        guard let output = String(data: outputData, encoding: .utf8) else {
            throw MarkItDownError.conversionFailed(
                "文件: \(filePath)\n无法解码 textutil 输出"
            )
        }

        return output
    }

    private nonisolated func _runPython(
        script: String,
        filePath: String,
        pythonURL: URL
    ) throws -> String {
        let process = Process()
        process.executableURL = pythonURL
        process.arguments = ["-c", script]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            let hint = pythonURL.path.contains("Contents/Resources")
                ? "\n\n请重新构建应用 (Product → Build) 以确保 Python 环境已正确嵌入。"
                : "\n\n请确认 markitdown-env 已正确安装"
            throw MarkItDownError.conversionFailed(
                "无法启动 Python 进程: \(error.localizedDescription)\n" +
                "Python 路径: \(pythonURL.path)\(hint)"
            )
        }

        // Read stdout/stderr BEFORE waitUntilExit to avoid pipe-buffer deadlock.
        // macOS pipe buffer is ~64KB; if the subprocess writes more than that,
        // it blocks on write() and never exits, so waitUntilExit() would hang
        // forever. Reading first drains the pipe and lets the subprocess finish.
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let lines = errorOutput.components(separatedBy: "\n").filter { !$0.isEmpty }
            let lastLines = lines.suffix(10).joined(separator: "\n")
            throw MarkItDownError.conversionFailed(
                "文件: \(filePath)\n" +
                "退出码: \(process.terminationStatus)\n" +
                (lastLines.isEmpty ? "" : "Python 错误:\n\(lastLines)")
            )
        }

        if !errorOutput.isEmpty, let output = String(data: outputData, encoding: .utf8), output.isEmpty {
            throw MarkItDownError.conversionFailed(
                "文件: \(filePath)\n" +
                "转换输出为空\n" +
                "stderr:\n\(errorOutput.prefix(500))"
            )
        }

        guard let output = String(data: outputData, encoding: .utf8) else {
            throw MarkItDownError.conversionFailed(
                "文件: \(filePath)\n无法解码 Python 输出 (stdout size: \(outputData.count) bytes)"
            )
        }

        return output
    }
}

enum MarkItDownError: LocalizedError {
    case conversionFailed(String)
    case pythonNotFound
    case invalidInput

    var errorDescription: String? {
        switch self {
        case .conversionFailed(let msg): return msg
        case .pythonNotFound: return "未找到 Python 运行时，请确认 markitdown-env 已安装"
        case .invalidInput: return "无效输入"
        }
    }
}
