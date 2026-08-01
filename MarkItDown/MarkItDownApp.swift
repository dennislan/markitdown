import SwiftUI

@main
struct MarkItDownApp: App {
    @StateObject private var viewModel = ConversionViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 720, minHeight: 480)
        }
        .commands {
            MarkItDownCommands(viewModel: viewModel)
        }

        Settings {
            SettingsView()
        }
    }
}
