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

    func convertFile(_ filePath: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self._runConvert(filePath: filePath)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func convertFileWithLLM(_ filePath: String, apiKey: String, model: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self._runConvertWithLLM(filePath: filePath, apiKey: apiKey, model: model)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func _runConvert(filePath: String) throws -> String {
        let escapedPath = filePath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        import sys
        sys.path.insert(0, "\(sitePackagesPath)")
        from markitdown import MarkItDown
        md = MarkItDown(enable_plugins=False)
        result = md.convert("\(escapedPath)", keep_data_uris=True)
        sys.stdout.write(result.text_content)
        """

        return try _runPython(script: script, filePath: filePath)
    }

    private func _runConvertWithLLM(filePath: String, apiKey: String, model: String) throws -> String {
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

        return try _runPython(script: script, filePath: filePath)
    }

    private func _runPython(script: String, filePath: String) throws -> String {
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
                "文件: \(filePath)\n" +
                "无法解码 Python 输出 (stdout size: \(outputData.count) bytes)"
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
