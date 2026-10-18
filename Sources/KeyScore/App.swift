import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIcon.image(size: 512)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct KeyScoreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--export-iconset"), i + 1 < args.count {
            do { try AppIcon.exportIconset(to: args[i + 1]) } catch {
                FileHandle.standardError.write(Data("icon export failed: \(error)\n".utf8))
                exit(1)
            }
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("KeyScore") {
            ContentView()
        }
    }
}
