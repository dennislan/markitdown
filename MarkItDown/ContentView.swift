import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: ConversionViewModel
    @State private var previewText: String?
    @State private var previewFileName: String?
    @State private var previewDragOver = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if viewModel.files.isEmpty {
                emptyState
                    .onDrop(of: [.fileURL], isTargeted: $previewDragOver) { providers in
                        handleDrop(providers)
                        return true
                    }
            } else {
                FileListView(viewModel: viewModel, onPreview: showPreview)
                    .onDrop(of: [.fileURL], isTargeted: $previewDragOver) { providers in
                        handleDrop(providers)
                        return true
                    }
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

            Button {
                viewModel.selectFiles()
            } label: {
                Label("选择文件", systemImage: "square.and.arrow.down")
            }

            Button {
                viewModel.selectFolder()
            } label: {
                Label("选择文件夹", systemImage: "folder.badge.plus")
            }

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
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 48))
                .foregroundColor(previewDragOver ? .accentColor : .secondary)
                .scaleEffect(previewDragOver ? 1.1 : 1.0)

            Text("暂无文件")
                .font(.title3)
                .foregroundColor(previewDragOver ? .accentColor : .secondary)
            Text(previewDragOver ? "松开以添加文件" : "拖放文件或点击顶部“选择文件”按钮添加")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
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

    private func handleDrop(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                defer { group.leave() }
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                urls.append(url)
            }
        }

        group.notify(queue: .main) {
            viewModel.addFilesFromURLs(urls)
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
