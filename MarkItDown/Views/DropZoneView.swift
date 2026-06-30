import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @ObservedObject var viewModel: ConversionViewModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 32))
                .foregroundColor(isTargeted ? .accentColor : .secondary)
                .scaleEffect(isTargeted ? 1.1 : 1.0)

            Text(isTargeted ? "松开以添加文件" : "将文件拖放到此处")
                .font(.subheadline)
                .foregroundColor(isTargeted ? .accentColor : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [8, 4]))
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.spring(response: 0.3), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
            return true
        }
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
