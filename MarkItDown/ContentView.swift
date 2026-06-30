import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: ConversionViewModel
    @State private var previewText: String?
    @State private var previewFileName: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            DropZoneView(viewModel: viewModel)
                .frame(minHeight: 180, idealHeight: 220)

            Divider()

            if viewModel.files.isEmpty {
                emptyState
            } else {
                FileListView(viewModel: viewModel, onPreview: showPreview)
            }

            Divider()

            bottomBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            NotificationService.requestPermission()
        }
        .sheet(item: $previewText) { text in
            VStack(spacing: 0) {
                HStack {
                    Text(previewFileName ?? "Markdown 预览")
                        .font(.headline)
                    Spacer()
                    Button("关闭") {
                        previewText = nil
                        previewFileName = nil
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding(12)
                .background(.regularMaterial)

                Divider()

                PreviewSheet(markdownText: text)
            }
            .frame(minWidth: 600, minHeight: 400)
        }
        .overlay(alignment: .bottom) {
            if let toast = viewModel.toastMessage {
                Text(toast)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(radius: 2)
                    .padding(.bottom, 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.toastMessage)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("MarkItDown")
                .font(.headline)

            Spacer()

            Picker("输出策略", selection: $viewModel.outputStrategy) {
                Text("原目录输出").tag(OutputStrategy.sameDirectory)
                Text("自定义目录").tag(OutputStrategy.customDirectory)
                Text("自定义+保留结构").tag(OutputStrategy.customDirectoryPreserveStructure)
            }
            .frame(width: 200)

            if viewModel.outputStrategy != .sameDirectory {
                Button {
                    viewModel.selectOutputDirectory()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }

            if let dir = viewModel.customOutputDirectory {
                Text(dir.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("暂无文件")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("拖放文件到上方区域，或点击选择按钮添加")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if viewModel.isConverting {
                ProgressView(value: viewModel.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
            }

            Text(viewModel.progressText)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if viewModel.isConverting {
                Text("用时: \(viewModel.elapsedTimeString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button("清空列表") {
                viewModel.clearFiles()
            }
            .disabled(viewModel.files.isEmpty)

            Button(viewModel.isConverting ? "转换中..." : "全部转换") {
                viewModel.startConversion()
            }
            .disabled(viewModel.files.isEmpty || viewModel.isConverting)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    func showPreview(for file: FileItem) {
        guard let outputURL = file.outputURL,
              let content = try? String(contentsOf: outputURL, encoding: .utf8) else { return }
        previewFileName = file.outputFileName
        previewText = content
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
