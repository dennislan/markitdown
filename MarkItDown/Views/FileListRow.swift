import SwiftUI

struct FileListRow: View {
    let file: FileItem
    @ObservedObject var viewModel: ConversionViewModel
    var onPreview: ((FileItem) -> Void)?
    @State private var isHovered = false
    @State private var showErrorDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: formatIcon)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.fileName)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Text(file.formattedSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: file.status.icon)
                        .foregroundColor(file.status.color)
                        .font(.system(size: 12))

                    if file.status == .converting {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(file.status.label)
                        .font(.caption)
                        .foregroundColor(file.status.color)
                }

                if isHovered {
                    HStack(spacing: 4) {
                        if file.status == .completed, let outputURL = file.outputURL {
                            Button {
                                onPreview?(file)
                            } label: {
                                Image(systemName: "eye")
                            }
                            .buttonStyle(.borderless)
                            .help("预览")

                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                            .help("在 Finder 中显示")
                        }

                        if file.status == .failed {
                            Button {
                                showErrorDetail.toggle()
                            } label: {
                                Image(systemName: "info.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("查看错误详情")

                            Button {
                                viewModel.retryFile(file)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("重试")
                        }

                        Button {
                            viewModel.removeFile(file)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .help("移除")
                    }
                    .transition(.opacity)
                }
            }
            .padding(.vertical, 4)
            .onHover { hovering in
                isHovered = hovering
            }

            if file.status == .failed, showErrorDetail {
                errorDetailPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showErrorDetail)
    }

    private var errorDetailPanel: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text("转换失败原因")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                ScrollView {
                    Text(file.errorMessage ?? "未知错误")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.red.opacity(0.9))
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 120)
            }

            Spacer()

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(file.errorMessage ?? "", forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("复制错误信息")
        }
        .padding(10)
        .background(Color.red.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.leading, 36)
        .padding(.trailing, 8)
        .padding(.bottom, 4)
    }

    private var formatIcon: String {
        switch file.fileExtension {
        case "pdf": return "doc.richtext"
        case "docx", "doc": return "doc.text"
        case "pptx", "ppt": return "doc.text.image"
        case "xlsx", "xls": return "tablecells"
        case "csv": return "tablecells"
        case "json": return "curlybraces"
        case "xml": return "chevron.left.forwardslash.chevron.right"
        case "html", "htm": return "globe"
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff": return "photo"
        case "wav", "mp3": return "waveform"
        case "epub": return "book"
        case "zip": return "doc.zipper"
        case "msg", "eml": return "envelope"
        default: return "doc"
        }
    }
}
