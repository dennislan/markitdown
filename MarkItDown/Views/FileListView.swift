import SwiftUI

struct FileListView: View {
    @ObservedObject var viewModel: ConversionViewModel
    var onPreview: ((FileItem) -> Void)?

    var body: some View {
        List {
            ForEach(viewModel.files) { file in
                FileListRow(file: file, viewModel: viewModel, onPreview: onPreview)
            }
        }
        .listStyle(.inset)
    }
}
