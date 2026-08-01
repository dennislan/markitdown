import Foundation
import Security

/// Centralized configuration for advanced settings (LLM, OCR, Azure).
///
/// Sensitive values (API keys) are stored in the macOS Keychain.
/// Non-sensitive values are stored in UserDefaults under the app's suite.
///
/// Keychain item details:
/// - service: `com.dennis.markitdown.advanced`
/// - accounts: individual keys per setting (e.g. `llm_api_key`, `azure_endpoint`)
struct AdvancedSettingsConfig {

    // MARK: - Keychain constants

    private static let keychainService = "com.dennis.markitdown.advanced"

    // MARK: - UserDefaults keys

    private enum UDKey: String {
        case enableLLMDescription
        case llmModel
        case enableOCR
        case enableAzure
        case azureEndpoint
        case customLLMPrompt
    }

    // MARK: - LLM Image Description

    /// Whether LLM-based image description is enabled.
    var enableLLMDescription: Bool {
        get { UserDefaults.standard.bool(forKey: UDKey.enableLLMDescription.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: UDKey.enableLLMDescription.rawValue) }
    }

    /// Selected LLM model identifier (e.g. "gpt-4o", "gpt-4o-mini").
    var llmModel: String {
        get { UserDefaults.standard.string(forKey: UDKey.llmModel.rawValue) ?? "gpt-4o" }
        set { UserDefaults.standard.set(newValue, forKey: UDKey.llmModel.rawValue) }
    }

    /// OpenAI-compatible API Key, persisted in the macOS Keychain.
    var llmApiKey: String? {
        get { KeychainHelper.loadString(key: keychainKey(for: "llm_api_key")) }
        set {
            if let value = newValue {
                _saveToKeychain(value, key: "llm_api_key")
            } else {
                _deleteFromKeychain(key: "llm_api_key")
            }
        }
    }

    // MARK: - OCR Plugin

    /// Whether the OCR plugin is enabled.
    var enableOCR: Bool {
        get { UserDefaults.standard.bool(forKey: UDKey.enableOCR.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: UDKey.enableOCR.rawValue) }
    }

    /// Checks whether the markitdown-ocr Python package is available in the current environment.
    var ocrPackageInstalled: Bool {
        _checkPackageInstalled("markitdown_ocr")
    }

    // MARK: - Azure Document Intelligence

    /// Whether Azure Document Intelligence is enabled.
    var enableAzure: Bool {
        get { UserDefaults.standard.bool(forKey: UDKey.enableAzure.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: UDKey.enableAzure.rawValue) }
    }

    /// Azure Document Intelligence endpoint URL (e.g. "https://<resource>.cognitiveservices.azure.com/documentintelligence").
    var azureEndpoint: String {
        get { UserDefaults.standard.string(forKey: UDKey.azureEndpoint.rawValue) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: UDKey.azureEndpoint.rawValue) }
    }

    /// Azure API Key, persisted in the macOS Keychain.
    var azureApiKey: String? {
        get { KeychainHelper.loadString(key: keychainKey(for: "azure_api_key")) }
        set {
            if let value = newValue {
                _saveToKeychain(value, key: "azure_api_key")
            } else {
                _deleteFromKeychain(key: "azure_api_key")
            }
        }
    }

    // MARK: - Custom LLM Prompt

    /// Custom prompt text for LLM image description. Empty string means default prompt.
    var customLLMPrompt: String {
        get { UserDefaults.standard.string(forKey: UDKey.customLLMPrompt.rawValue) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: UDKey.customLLMPrompt.rawValue) }
    }

    // MARK: - Keychain helpers

    /// Returns the API Key for Azure Document Intelligence if Azure is enabled and a key exists.
    var azureKeyProvided: Bool {
        return azureApiKey != nil && !azureApiKey!.isEmpty
    }

    /// Returns whether the LLM API key is configured.
    var llmKeyProvided: Bool {
        return llmApiKey != nil && !llmApiKey!.isEmpty
    }

    // MARK: - Private

    private func keychainKey(for account: String) -> String {
        return "\(AdvancedSettingsConfig.keychainService).\(account)"
    }

    private func _saveToKeychain(_ value: String, key: String) {
        let fullKey = keychainKey(for: key)
        _ = KeychainHelper.saveString(key: fullKey, value: value)
    }

    private func _deleteFromKeychain(key: String) {
        let fullKey = keychainKey(for: key)
        _ = KeychainHelper.delete(key: fullKey)
    }

    private func _checkPackageInstalled(_ packageName: String) -> Bool {
        // Attempt a quick Python check to see if the package can be imported
        guard let pythonURL = MarkItDownProxy.pythonBinaryURL() else { return false }
        do {
            let script = "import importlib; print(importlib.util.find_spec(\"\(packageName)\") is not None)"
            let output = try MarkItDownProxy.runSilentPython(pythonURL: pythonURL, script: script)
            return output.trimmingCharacters(in: .whitespacesAndNewlines) == "True"
        } catch {
            return false
        }
    }
}
