import AppKit
import SwiftUI

/// Connects the SwiftUI content to the NSWindow hosting it, normally the
/// MenuBarExtra panel. It reports whether the window is actually on screen
/// (onAppear/onDisappear are unreliable for panels, which are ordered in and
/// out rather than recreated) and keeps the window's height in step with the
/// content. Panels are not reliably resized when the content changes while
/// they are hidden, which otherwise shows up as empty space above the header
/// the next time they open.
struct WindowBridge: NSViewRepresentable {
    let contentHeight: CGFloat
    let onVisibilityChange: (Bool) -> Void

    func makeNSView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.onVisibilityChange = onVisibilityChange
        view.contentHeight = contentHeight
        return view
    }

    func updateNSView(_ view: BridgeView, context: Context) {
        view.onVisibilityChange = onVisibilityChange
        view.contentHeight = contentHeight
        view.scheduleSync()
    }

    final class BridgeView: NSView {
        var onVisibilityChange: ((Bool) -> Void)?
        var contentHeight: CGFloat = 0

        private var tokens: [NSObjectProtocol] = []
        private var syncScheduled = false
        private var recentAdjustments: [Date] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            guard let window else {
                report(false)
                return
            }
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.willCloseNotification,
            ]
            for name in names {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.reportCurrentState()
                })
            }
            reportCurrentState()
        }

        private func reportCurrentState() {
            guard let window else {
                report(false)
                return
            }
            report(window.isVisible && window.occlusionState.contains(.visible))
            scheduleSync()
        }

        private func report(_ visible: Bool) {
            // Deferred so state is never published in the middle of a layout pass.
            DispatchQueue.main.async { [weak self] in self?.onVisibilityChange?(visible) }
        }

        func scheduleSync() {
            guard !syncScheduled else { return }
            syncScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.syncScheduled = false
                self?.syncWindowHeight()
            }
        }

        /// The view SwiftUI uses to size the window; its height is what should match the content.
        private var hostingView: NSView? {
            var view: NSView? = superview
            while let candidate = view {
                if String(describing: type(of: candidate)).contains("HostingView") { return candidate }
                view = candidate.superview
            }
            return nil
        }

        private func syncWindowHeight() {
            guard let window, window.isVisible, contentHeight > 0, let hostingView else { return }
            let delta = contentHeight - hostingView.frame.height
            guard abs(delta) > 1 else { return }

            // Never fight SwiftUI: at most a few corrections per second.
            let now = Date()
            recentAdjustments.removeAll { now.timeIntervalSince($0) > 1 }
            guard recentAdjustments.count < 3 else { return }
            recentAdjustments.append(now)

            var frame = window.frame
            frame.size.height += delta
            frame.origin.y -= delta  // keep the top edge where it is, attached to the menu bar
            window.setFrame(frame, display: true)
        }

        private func removeObservers() {
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens.removeAll()
        }

        deinit {
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}
