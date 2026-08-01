import Foundation
import PDFKit
import Vision

actor MarkItDownProxy {
    private let pythonURL: URL
    private let sitePackagesPath: String
    private let pptConverterPath: String?

    init() {
        let runtime = Self.resolveRuntime()
        self.pythonURL = runtime?.pythonURL ?? URL(fileURLWithPath: "/usr/bin/false")
        self.sitePackagesPath = runtime?.sitePackagesPath ?? ""
        self.pptConverterPath = runtime?.pptConverterSource?.path
    }

    // MARK: - Runtime resolution (embedded bundle first, repo venv as dev fallback)

    private struct PythonRuntime {
        let pythonURL: URL
        let sitePackagesPath: String
        /// Absolute path to PptConverter.py, when available.
        let pptConverterSource: URL?
    }

    /// Locates the Python runtime in priority order:
    /// 1. App-bundle embedded runtime (produced by the "Embed Python Runtime"
    ///    Xcode build phase and build_release.sh).
    /// 2. Repo-local `markitdown-env` during development, derived from this
    ///    source file's own path — no machine-specific absolute paths.
    private static func resolveRuntime() -> PythonRuntime? {
        let fm = FileManager.default

        let resourcesURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/python")
        let bundledVenv = resourcesURL.appendingPathComponent("markitdown-env")
        if fm.fileExists(atPath: bundledVenv.path) {
            return makeRuntime(venvDir: bundledVenv, pptConverterDir: resourcesURL)
        }

        let sourceFile = URL(fileURLWithPath: #filePath) // …/MarkItDown/Services/MarkItDownProxy.swift
        let repoRoot = sourceFile
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // MarkItDown
            .deletingLastPathComponent() // repo root
        let devVenv = repoRoot.appendingPathComponent("markitdown-env")
        if fm.fileExists(atPath: devVenv.path) {
            let pptDir = repoRoot.appendingPathComponent("MarkItDown/Resources")
            return makeRuntime(venvDir: devVenv, pptConverterDir: pptDir)
        }

        return nil
    }

    private static func makeRuntime(venvDir: URL, pptConverterDir: URL?) -> PythonRuntime {
        let version = pythonVersion(venvDir: venvDir)
        let pythonURL = venvDir.appendingPathComponent("bin/python3")
        let sitePackagesPath = venvDir
            .appendingPathComponent("lib/python\(version)/site-packages")
            .path
        let pptSource: URL?
        if let dir = pptConverterDir {
            // Converter is copied next to the venv (Contents/Resources/python/)
            // by embed-python.sh; the Xcode Resources phase puts it one level
            // up (Contents/Resources/). Check both so either build layout works.
            let candidates = [dir, dir.deletingLastPathComponent()]
            pptSource = Self.firstExistingFile(named: "PptConverter.py", in: candidates)
        } else {
            pptSource = nil
        }
        return PythonRuntime(
            pythonURL: pythonURL,
            sitePackagesPath: sitePackagesPath,
            pptConverterSource: pptSource
        )
    }

    private static func firstExistingFile(named name: String, in dirs: [URL]) -> URL? {
        for dir in dirs {
            let candidate = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Reads `version = x.y` from the venv's pyvenv.cfg; falls back to "3.14".
    private static func pythonVersion(venvDir: URL) -> String {
        guard let content = try? String(contentsOf: venvDir.appendingPathComponent("pyvenv.cfg"), encoding: .utf8) else {
            return "3.14"
        }
        for line in content.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == "version" {
                return parts[1]
            }
        }
        return "3.14"
    }

    // MARK: - Public async entry points (capture actor state, dispatch to nonisolated workers)

    func convertFile(_ filePath: String) async throws -> String {
        let pyURL = pythonURL
        let spPath = sitePackagesPath
        let pptPath = pptConverterPath
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self._runConvert(filePath: filePath, pythonURL: pyURL, sitePackagesPath: spPath, pptConverterPath: pptPath)
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
        let pptPath = pptConverterPath
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self._runConvertWithLLM(filePath: filePath, apiKey: apiKey, model: model, pythonURL: pyURL, sitePackagesPath: spPath, pptConverterPath: pptPath)
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
        let pptPath = pptConverterPath
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
                        sitePackagesPath: spPath,
                        pptConverterPath: pptPath
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Static helpers (for AdvancedSettingsConfig)

    static func pythonBinaryURL() -> URL? {
        resolveRuntime()?.pythonURL
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
        sitePackagesPath: String,
        pptConverterPath: String?
    ) throws -> String {
        // Legacy .doc files are not supported by markitdown — fall back to macOS textutil.
        if filePath.lowercased().hasSuffix(".doc") {
            return try _convertWithTextutil(filePath: filePath)
        }

        // Legacy .ppt files need a custom converter. .pdf files go through the
        // default markitdown path; garbled-text detection + OCR fallback now
        // live in Swift (postProcessPDFResult).
        let isPpt = filePath.lowercased().hasSuffix(".ppt")
        if isPpt {
            return try _runConvertWithConverter(
                filePath: filePath,
                converterModule: "PptConverter",
                converterSourcePath: pptConverterPath,
                envKey: "MARKITDOWN_PPT_CONVERTER_PATH",
                enableLLM: false,
                llmApiKey: nil,
                llmModel: "",
                enableOCR: false,
                enableAzure: false,
                azureEndpoint: nil,
                azureApiKey: nil,
                customPrompt: "",
                pythonURL: pythonURL,
                sitePackagesPath: sitePackagesPath
            )
        }

        let escapedPath = filePath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

        var parts = [String]()
        parts.append("import sys, tempfile, os")
        parts.append("sys.path.insert(0, \"\(sitePackagesPath)\")")
        parts.append("from markitdown import MarkItDown")

        parts.append("")
        parts.append("md = MarkItDown(enable_plugins=False)")
        parts.append("result = md.convert(\"\(escapedPath)\", keep_data_uris=True)")
        parts.append("sys.stdout.write(result.text_content)")

        let script = parts.joined(separator: "\n")
        let output = try _runPython(script: script, filePath: filePath, pythonURL: pythonURL)
        if filePath.lowercased().hasSuffix(".pdf") {
            return try postProcessPDFResult(output, filePath: filePath)
        }
        return output
    }

    private nonisolated func _runConvertWithLLM(
        filePath: String,
        apiKey: String,
        model: String,
        pythonURL: URL,
        sitePackagesPath: String,
        pptConverterPath: String?
    ) throws -> String {
        // Legacy .doc files are not supported by markitdown — fall back to macOS textutil.
        if filePath.lowercased().hasSuffix(".doc") {
            return try _convertWithTextutil(filePath: filePath)
        }

        // Legacy .ppt files need a custom converter. .pdf files go through the
        // default markitdown path; garbled-text detection + OCR fallback now
        // live in Swift (postProcessPDFResult).
        let isPpt = filePath.lowercased().hasSuffix(".ppt")
        if isPpt {
            return try _runConvertWithConverter(
                filePath: filePath,
                converterModule: "PptConverter",
                converterSourcePath: pptConverterPath,
                envKey: "MARKITDOWN_PPT_CONVERTER_PATH",
                enableLLM: true,
                llmApiKey: apiKey,
                llmModel: model,
                enableOCR: false,
                enableAzure: false,
                azureEndpoint: nil,
                azureApiKey: nil,
                customPrompt: "",
                pythonURL: pythonURL,
                sitePackagesPath: sitePackagesPath
            )
        }

        let escapedPath = filePath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

        var parts = [String]()
        parts.append("import sys")
        parts.append("sys.path.insert(0, \"\(sitePackagesPath)\")")
        parts.append("from markitdown import MarkItDown")

        var kwargs = [String]()
        if !apiKey.isEmpty {
            let escapedKey = apiKey.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let escapedModel = model.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            kwargs.append("llm_client=__llm_client")
            kwargs.append("llm_model=\"\(escapedModel)\"")
            parts.append("from openai import OpenAI")
            parts.append("__llm_client = OpenAI(api_key=\"\(escapedKey)\")")
        }

        if kwargs.isEmpty {
            parts.append("md = MarkItDown(enable_plugins=False)")
        } else {
            let kwargStr = kwargs.joined(separator: ", ")
            parts.append("md = MarkItDown(\(kwargStr))")
        }

        parts.append("result = md.convert(\"\(escapedPath)\", keep_data_uris=True)")
        parts.append("sys.stdout.write(result.text_content)")

        let script = parts.joined(separator: "\n")
        let output = try _runPython(script: script, filePath: filePath, pythonURL: pythonURL)
        if filePath.lowercased().hasSuffix(".pdf") {
            return try postProcessPDFResult(output, filePath: filePath)
        }
        return output
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
        sitePackagesPath: String,
        pptConverterPath: String?
    ) throws -> String {
        // Legacy .doc files are not supported by markitdown — fall back to macOS textutil.
        if filePath.lowercased().hasSuffix(".doc") {
            return try _convertWithTextutil(filePath: filePath)
        }

        // Legacy .ppt files need a custom converter. .pdf files go through the
        // default markitdown path; garbled-text detection + OCR fallback now
        // live in Swift (postProcessPDFResult).
        let isPpt = filePath.lowercased().hasSuffix(".ppt")
        if isPpt {
            return try _runConvertWithConverter(
                filePath: filePath,
                converterModule: "PptConverter",
                converterSourcePath: pptConverterPath,
                envKey: "MARKITDOWN_PPT_CONVERTER_PATH",
                enableLLM: enableLLM,
                llmApiKey: llmApiKey,
                llmModel: llmModel,
                enableOCR: enableOCR,
                enableAzure: enableAzure,
                azureEndpoint: azureEndpoint,
                azureApiKey: azureApiKey,
                customPrompt: customPrompt,
                pythonURL: pythonURL,
                sitePackagesPath: sitePackagesPath
            )
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
        let output = try _runPython(script: script, filePath: filePath, pythonURL: pythonURL)
        if filePath.lowercased().hasSuffix(".pdf") {
            return try postProcessPDFResult(output, filePath: filePath)
        }
        return output
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

    /// Detects whether markitdown's PDF extraction produced garbled text that
    /// needs an OCR fallback. Mirrors RobustPdfConverter._is_garbled:
    /// (cid:NNN) placeholders, U+FFFD replacement chars, or illegal controls.
    private nonisolated func isGarbledPDFText(_ text: String) -> Bool {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        let cidPattern = #"\(cid:\d+\)"#
        let cidCount = matches(of: cidPattern, in: text)
        if cidCount >= 3 {
            return true
        }
        if text.contains("\u{FFFD}") {
            return true
        }
        let controlPattern = #"[\x{00}-\x{08}\x{0B}\x{0E}-\x{1F}\x{7F}]"#
        return matches(of: controlPattern, in: text) >= 3
    }

    private nonisolated func matches(of pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, range: range)
    }

    /// Post-processes PDF conversion output. Garbled or empty extractions are
    /// retried via on-device Vision OCR (PDFKit rendering + VNRecognizeTextRequest).
    /// Returns the original output when OCR is unavailable or still fails.
    private nonisolated func postProcessPDFResult(_ text: String, filePath: String) throws -> String {
        guard isGarbledPDFText(text) else { return text }
        do {
            let ocrText = try ocrPDFWithVision(filePath: filePath)
            guard !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return text
            }
            return ocrText
        } catch {
            return text
        }
    }

    /// Renders each PDF page with PDFKit and runs Vision text recognition.
    private nonisolated func ocrPDFWithVision(filePath: String) throws -> String {
        guard let document = PDFDocument(url: URL(fileURLWithPath: filePath)) else {
            throw MarkItDownError.conversionFailed(
                "文件: \(filePath)\n无法打开 PDF 进行 OCR"
            )
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true

        var pageTexts: [String] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let targetSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let pageImage = page.thumbnail(of: targetSize, for: .mediaBox)
            guard let cgImage = pageImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                continue
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            guard let observations = request.results else { continue }
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            if !lines.isEmpty {
                pageTexts.append(lines.joined(separator: "\n"))
            }
        }

        if pageTexts.isEmpty {
            throw MarkItDownError.conversionFailed(
                "文件: \(filePath)\nOCR 未识别到文本"
            )
        }
        return pageTexts.joined(separator: "\n\n---\n\n")
    }

    /// Unified conversion for formats that need a custom registered converter
    /// (.ppt → PptConverter) with advanced options.
    private nonisolated func _runConvertWithConverter(
        filePath: String,
        converterModule: String,
        converterSourcePath: String?,
        envKey: String,
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
        guard let converterSourcePath else {
            throw MarkItDownError.conversionFailed(
                "文件: \(filePath)\n未找到 \(converterModule).py，无法转换该文件"
            )
        }

        let escapedPath = filePath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

        var parts = [String]()
        parts.append("import sys, tempfile, os")
        parts.append("sys.path.insert(0, \"\(sitePackagesPath)\")")
        parts.append("from markitdown import MarkItDown")

        parts.append("")
        parts.append("_converter_src = open(os.environ['\(envKey)']).read()")
        parts.append("_converter_path = os.path.join(tempfile.gettempdir(), '\(converterModule).py')")
        parts.append("with open(_converter_path, 'w') as f:")
        parts.append("    f.write(_converter_src)")
        parts.append("sys.path.insert(0, tempfile.gettempdir())")
        parts.append("from \(converterModule) import \(converterModule)")
        parts.append("")
        parts.append("class _RegMarkItDown(MarkItDown):")
        parts.append("    def register_converter(self, converter, *, priority=0.0):")
        parts.append("        from markitdown._markitdown import ConverterRegistration")
        parts.append("        self._converters.insert(0, ConverterRegistration(converter=converter, priority=priority))")

        var kwargs = [String]()

        if enableLLM, let apiKey = llmApiKey, !apiKey.isEmpty {
            let escapedKey = apiKey.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let escapedModel = llmModel.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            kwargs.append("llm_client=__llm_client")
            kwargs.append("llm_model=\"\(escapedModel)\"")
            parts.append("from openai import OpenAI")
            parts.append("__llm_client = OpenAI(api_key=\"\(escapedKey)\")")
        }

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

        if enableOCR {
            kwargs.append("enable_plugins=True")
        }

        if kwargs.isEmpty {
            parts.append("md = _RegMarkItDown(enable_plugins=False)")
        } else {
            let kwargStr = kwargs.joined(separator: ", ")
            parts.append("md = _RegMarkItDown(\(kwargStr))")
        }
        parts.append("md.register_converter(\(converterModule)())")

        if enableLLM && !customPrompt.isEmpty {
            let escapedPrompt = customPrompt.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            parts.append("")
            parts.append("__custom_prompt = \"\(escapedPrompt)\"")
            parts.append("_result = md.convert(\"\(escapedPath)\", keep_data_uris=True)")
            parts.append("_text = _result.text_content")
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
        return try _runPython(
            script: script,
            filePath: filePath,
            pythonURL: pythonURL,
            environment: [envKey: converterSourcePath]
        )
    }

    private nonisolated func _runPython(
        script: String,
        filePath: String,
        pythonURL: URL,
        environment: [String: String] = [:]
    ) throws -> String {
        let process = Process()
        process.executableURL = pythonURL
        process.arguments = ["-c", script]
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

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
