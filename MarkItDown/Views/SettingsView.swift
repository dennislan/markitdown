import SwiftUI

struct SettingsView: View {
    @AppStorage("concurrency") private var concurrency: Double = 4
    @AppStorage("outputStrategy") private var outputStrategy: OutputStrategy = .sameDirectory
    @AppStorage("autoOpenOutput") private var autoOpenOutput: Bool = false
    @AppStorage("sendNotification") private var sendNotification: Bool = true

    @State private var config = AdvancedSettingsConfig()

    // Track whether OCR package was detected on last check
    @State private var ocrDetected: Bool = false
    @State private var checkingOCR: Bool = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }

            advancedTab
                .tabItem { Label("高级", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 450, height: 380)
        .onAppear {
            // Re-check OCR on settings open since packages may have changed
            checkOCRPackage()
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Picker("输出策略", selection: $outputStrategy) {
                ForEach(OutputStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.displayName).tag(strategy)
                }
            }

            Slider(value: $concurrency, in: 1...8, step: 1) {
                Text("并发数 (\(Int(concurrency)))")
            } minimumValueLabel: {
                Text("1")
            } maximumValueLabel: {
                Text("8")
            }

            Toggle("转换完成后自动打开输出目录", isOn: $autoOpenOutput)
            Toggle("转换完成后发送系统通知", isOn: $sendNotification)
        }
        .padding(20)
    }

    // MARK: - Advanced Tab

    private var advancedTab: some View {
        Form {
            // LLM Image Description
            Section("LLM 图像描述") {
                Toggle("启用", isOn: $config.enableLLMDescription)

                if config.enableLLMDescription {
                    SecureField("OpenAI 兼容 API Key", text: _llmApiKeyBinding)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .help("API Key 安全存储于 macOS Keychain，不会写入明文配置文件")

                    Picker("模型", selection: $config.llmModel) {
                        Text("GPT-4o").tag("gpt-4o")
                        Text("GPT-4o Mini").tag("gpt-4o-mini")
                        Text("GPT-4 Turbo").tag("gpt-4-turbo")
                        Text("GPT-4").tag("gpt-4")
                        Text("GPT-3.5 Turbo").tag("gpt-3.5-turbo")
                    }
                    .pickerStyle(.menu)

                    Text("自定义 Prompt（留空使用默认）")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: $config.customLLMPrompt)
                        .frame(height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .help("此 Prompt 仅在 LLM 图像描述启用时生效，用于指导模型如何描述图片内容。")
                    }

                if config.enableLLMDescription && !config.llmKeyProvided {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("未填写 API Key，LLM 描述将无法使用")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 4)
                }
            }

            // OCR Plugin
            Section("OCR 插件") {
                Toggle("启用", isOn: $config.enableOCR)
                    .disabled(!ocrDetected)

                if checkingOCR {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("正在检测 markitdown-ocr 包...")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                } else if !ocrDetected {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.gray)
                        Text("markitdown-ocr 包未检测到。安装后重启设置生效。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("markitdown-ocr 包已安装并可用")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            }

            // Azure Document Intelligence
            Section("Azure Document Intelligence") {
                Toggle("启用", isOn: $config.enableAzure)

                if config.enableAzure {
                    TextField("端点 URL", text: _azureEndpointBinding)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .help("例如: https://<your-resource>.cognitiveservices.azure.com")

                    SecureField("Azure API Key", text: _azureApiKeyBinding)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .help("API Key 安全存储于 macOS Keychain")

                    if !config.azureKeyProvided {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("未填写 API Key，Azure 转换将无法使用")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
        }
        .padding(20)
        .onChange(of: config.enableOCR) { _ in
            checkOCRPackage()
        }
    }

    // MARK: - OCR Detection

    private func checkOCRPackage() {
        checkingOCR = true
        DispatchQueue.global(qos: .userInitiated).async {
            let detected = config.ocrPackageInstalled
            DispatchQueue.main.async {
                ocrDetected = detected
                checkingOCR = false
            }
        }
    }

    // MARK: - Keychain-backed bindings

    /// Two-way binding for the LLM API Key SecureField.
    private var _llmApiKeyBinding: Binding<String> {
        Binding<String>(
            get: { config.llmApiKey ?? "" },
            set: {
                config.llmApiKey = $0.isEmpty ? nil : $0
            }
        )
    }

    /// Two-way binding for the Azure endpoint TextField.
    private var _azureEndpointBinding: Binding<String> {
        Binding<String>(
            get: { config.azureEndpoint },
            set: { config.azureEndpoint = $0 }
        )
    }

    /// Two-way binding for the Azure API Key SecureField.
    private var _azureApiKeyBinding: Binding<String> {
        Binding<String>(
            get: { config.azureApiKey ?? "" },
            set: {
                config.azureApiKey = $0.isEmpty ? nil : $0
            }
        )
    }
}
