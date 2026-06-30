import SwiftUI
import UniformTypeIdentifiers

struct FileListView: View {
    @ObservedObject var viewModel: ConversionViewModel
    var onPreview: ((FileItem) -> Void)?
    @State private var isDragOver = false

    var body: some View {
        List {
            ForEach(viewModel.files) { file in
                FileListRow(file: file, viewModel: viewModel, onPreview: onPreview)
            }
        }
        .listStyle(.inset)
        .overlay {
            if isDragOver {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.08))
                    .overlay(
                        Rectangle()
                            .stroke(Color.accentColor, lineWidth: 2)
                    )
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
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
