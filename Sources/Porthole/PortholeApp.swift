import AppKit
import SwiftUI

@main
struct PortholeApp: App {
    @StateObject private var store = PortStore()

    init() {
        PortholeCLI.runIfRequested()  // exits when invoked with --list / --json
        NSApplication.shared.setActivationPolicy(.accessory)  // no Dock icon, even when run outside a bundle
        if CommandLine.arguments.contains("--preview") {
            PreviewWindow.show(expandFirst: CommandLine.arguments.contains("--expand-first"),
                               thenCollapse: CommandLine.arguments.contains("--then-collapse"),
                               demo: CommandLine.arguments.contains("--demo"))
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
        } label: {
            MenuBarLabel(count: store.showCountInMenuBar ? store.uniquePortCount : 0)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let count: Int

    var body: some View {
        if count > 0 {
            HStack(spacing: 3) {
                Image(nsImage: MenuBarIcon.image)
                Text(verbatim: "\(count)")
            }
        } else {
            Image(nsImage: MenuBarIcon.image)
        }
    }
}

enum AppInfo {
    static let version: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
}

/// `Porthole --preview [--expand-first]` shows the menu bar content in a plain
/// borderless window sized to its content. MenuBarExtra panels cannot be opened
/// programmatically, so this is how screenshots and layout checks are done.
@MainActor
enum PreviewWindow {
    private static var window: NSWindow?
    private static var controller: NSHostingController<AnyView>?

    static func show(expandFirst: Bool, thenCollapse: Bool = false, demo: Bool = false) {
        DispatchQueue.main.async {
            let store = PortStore()
            let controller = NSHostingController(rootView: AnyView(ContentView().environmentObject(store)))
            controller.sizingOptions = []
            controller.view.wantsLayer = true
            controller.view.layer?.cornerRadius = 12
            controller.view.layer?.masksToBounds = true
            controller.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.borderless]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = true
            window.level = .floating  // stay unoccluded, like the real panel, so the fast refresh cadence applies
            window.title = "Porthole preview"
            self.window = window
            self.controller = controller

            fit()
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            print("preview window id: \(window.windowNumber)")
            fflush(stdout)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if expandFirst, let first = store.ports.first { store.toggleDetails(first) }
                fit()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { fit() }
                if demo {
                    // Scripted sequence for the README GIF: hover, open the info panel, close it.
                    let queue = DispatchQueue.main
                    queue.asyncAfter(deadline: .now() + 0.8) { store.demoHoverKey = store.ports.first?.portKey }
                    queue.asyncAfter(deadline: .now() + 2.2) {
                        if let first = store.ports.first { store.toggleDetails(first) }
                        queue.asyncAfter(deadline: .now() + 0.6) { fit() }
                    }
                    queue.asyncAfter(deadline: .now() + 6.8) {
                        if let first = store.ports.first { store.toggleDetails(first) }
                        store.demoHoverKey = nil
                        queue.asyncAfter(deadline: .now() + 0.4) { fit() }
                    }
                }
                if thenCollapse {
                    // Collapse without calling fit(): the window keeps its tall frame, exactly
                    // what happens to the menu bar panel. WindowBridge is expected to fix it.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        if let first = store.ports.first { store.toggleDetails(first) }
                    }
                }
            }
        }
    }

    private static func fit() {
        guard let window, let controller else { return }
        let size = controller.sizeThatFits(in: NSSize(width: 400, height: 2000))
        let origin = window.frame.origin
        window.setContentSize(size)
        window.setFrameOrigin(origin)
    }
}
