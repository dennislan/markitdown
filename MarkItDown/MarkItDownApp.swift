import SwiftUI
import os

@main
struct MarkItDownApp: App {
    @StateObject private var viewModel = ConversionViewModel()

    init() {
        // Auto-embed Python environment if not already embedded
        let resourcesURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/python/markitdown-env/bin/python3")
        if !FileManager.default.fileExists(atPath: resourcesURL.path) {
            // Try to find the embed script: in app bundle Resources (after install)
            // or next to the app executable (during development)
            let bundlePath = Bundle.main.bundlePath
            let scriptCandidates = [
                // From app bundle Resources (after Xcode build)
                "\(bundlePath)/Contents/Resources/embed-python.sh",
                // From project Scripts/ directory (during development)
                "\(bundlePath)/../../../../Scripts/embed-python.sh",
                // From project root (if app is in build/Debug/)
                "\(bundlePath)/../../../../../../Scripts/embed-python.sh",
            ]

            for scriptPath in scriptCandidates {
                if FileManager.default.fileExists(atPath: scriptPath) {
                    let logger = Logger(subsystem: "com.dennis.markitdown", category: "startup")
                    logger.info("Auto-embedding Python from: \(scriptPath)")

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/bash")
                    process.arguments = [scriptPath]

                    var env = ProcessInfo.processInfo.environment
                    // Pass Xcode-like variables so the script works
                    if let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
                        env["SRCROOT"] = srcRoot
                    }
                    process.environment = env

                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe

                    do {
                        try process.run()
                        process.waitUntilExit()
                        if process.terminationStatus == 0 {
                            logger.info("Python environment embedded successfully")
                        } else {
                            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                            logger.error("Embed failed (exit \(process.terminationStatus)): \(output.prefix(200))")
                        }
                    } catch {
                        logger.error("Failed to run embed script: \(error)")
                    }
                    break
                }
            }
        }
    }

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
