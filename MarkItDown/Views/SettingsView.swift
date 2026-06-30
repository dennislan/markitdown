import SwiftUI

struct SettingsView: View {
    @AppStorage("concurrency") private var concurrency: Double = 4
    @AppStorage("outputStrategy") private var outputStrategy: OutputStrategy = .sameDirectory
    @AppStorage("autoOpenOutput") private var autoOpenOutput: Bool = false
    @AppStorage("sendNotification") private var sendNotification: Bool = true
    @AppStorage("enableLLMDescription") private var enableLLMDescription: Bool = false
    @AppStorage("llmModel") private var llmModel: String = "gpt-4o"

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }

            advancedTab
                .tabItem { Label("高级", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 450, height: 320)
    }

    private var generalTab: some View {
        Form {
            Picker("输出策略", selection: $outputStrategy) {
                ForEach(OutputStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.displayName).tag(strategy)
                }
            }

            Slider(value: $concurrency, in: 1...8, step: 1) {
                Text("并发数")
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

    private var advancedTab: some View {
        Form {
            Toggle("启用 LLM 图像描述", isOn: $enableLLMDescription)

            if enableLLMDescription {
                SecureField("OpenAI API Key", text: .constant(""))
                    .help("API Key 存储于系统 Keychain 中")
                Picker("模型", selection: $llmModel) {
                    Text("GPT-4o").tag("gpt-4o")
                    Text("GPT-4o Mini").tag("gpt-4o-mini")
                    Text("GPT-4 Turbo").tag("gpt-4-turbo")
                }
            }

            Divider()

            Toggle("OCR 插件", isOn: .constant(false))
                .disabled(true)
                .help("V1.0 暂不支持，设置预留入口")

            Toggle("Azure Document Intelligence", isOn: .constant(false))
                .disabled(true)
                .help("V1.0 暂不支持，设置预留入口")
        }
        .padding(20)
    }
}
