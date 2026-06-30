import SwiftUI

struct MarkItDownCommands: Commands {
    @ObservedObject var viewModel: ConversionViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("打开文件...") {
                viewModel.selectFiles()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("打开文件夹...") {
                viewModel.selectFolder()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandMenu("转换") {
            Button("开始转换") {
                viewModel.startConversion()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.files.isEmpty || viewModel.isConverting)

            Button("清空列表") {
                viewModel.clearFiles()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.files.isEmpty)
        }
    }
}
