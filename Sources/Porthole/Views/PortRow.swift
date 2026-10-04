import AppKit
import SwiftUI

struct PortRow: View {
    @EnvironmentObject private var store: PortStore
    let entry: ListeningPort

    @State private var hovering = false
    @State private var confirmingKill = false
    @State private var confirmToken = UUID()
    @State private var copied = false

    private var isExpanded: Bool { store.isExpanded(entry) }
    private var showActions: Bool { hovering || confirmingKill || isExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                ProcessIconView(entry: entry)
                VStack(alignment: .leading, spacing: 2) {
                    titleLine
                    detailLine
                    noticeLine
                }
                Spacer(minLength: 8)
                ZStack(alignment: .trailing) {
                    resourceLabel.opacity(showActions ? 0 : 1)
                    actions.opacity(showActions ? 1 : 0)
                }
                .animation(.easeOut(duration: 0.12), value: showActions)
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleDetails() }
            if isExpanded {
                ProcessDetailView(entry: entry)
                    .padding(.leading, 40)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(hovering || isExpanded ? Color.primary.opacity(isExpanded ? 0.035 : 0.05) : Color.clear)
        .onHover { inside in
            hovering = inside
            if !inside { confirmingKill = false }
        }
        .contextMenu { contextMenu }
        .help(entry.commandLine ?? entry.executablePath ?? entry.processName)
    }

    private func toggleDetails() {
        withAnimation(.easeOut(duration: 0.15)) {
            store.toggleDetails(entry)
        }
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            Text(verbatim: ":\(entry.port)")
                .font(.system(.body, design: .monospaced).weight(.semibold))
            Text(entry.processName)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)
            if entry.proto == .udp {
                Text("UDP")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.1)))
                    .foregroundStyle(.secondary)
            }
            let restarts = store.restartCount(for: entry)
            if restarts > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(verbatim: "\(restarts)")
                }
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.orange.opacity(0.18)))
                .foregroundStyle(.orange)
                .help("Restarted \(restarts) \(restarts == 1 ? "time" : "times") in the last hour")
            }
        }
    }

    /// CPU% and memory, shown where the action buttons appear on hover.
    @ViewBuilder private var resourceLabel: some View {
        let cpu = store.cpuPercent[entry.pid]
        if cpu != nil || entry.memory != nil {
            HStack(spacing: 4) {
                if let cpu {
                    Text(Format.cpuPercent(cpu))
                        .foregroundStyle(cpu >= 80 ? Color.orange : Color.secondary)
                }
                if cpu != nil && entry.memory != nil {
                    Text("·")
                }
                if let memory = entry.memory {
                    Text(Format.memory(memory))
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help("CPU \(cpu.map(Format.cpuPercent) ?? "measuring…") · memory \(entry.memory.map(Format.memory) ?? "unknown")")
        }
    }

    private var detailLine: some View {
        HStack(spacing: 4) {
            Text(verbatim: "PID \(entry.pid)")
            if !entry.user.isEmpty && entry.user != store.currentUser {
                Text("·")
                Text(entry.user)
            }
            Text("·")
            HStack(spacing: 3) {
                Image(systemName: entry.isLoopbackOnly ? "lock" : "globe")
                    .font(.system(size: 9))
                Text(entry.bindDescription)
            }
            if let hint = entry.serviceHint {
                Text("·")
                Text(hint)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    @ViewBuilder private var noticeLine: some View {
        if let notice = store.notices[entry.id] {
            HStack(spacing: 6) {
                Text(notice.text)
                if case .needsAdmin(let force) = notice.kind {
                    Button("Kill as admin…") { store.killAsAdmin(entry, force: force) }
                        .buttonStyle(.link)
                }
            }
            .font(.caption)
            .foregroundStyle(notice.kind == .info ? Color.secondary : Color.orange)
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            ActionButton(symbol: isExpanded ? "info.circle.fill" : "info.circle",
                         help: "What is \(entry.processName)?",
                         tint: isExpanded ? .accentColor : .secondary) {
                toggleDetails()
            }
            ActionButton(symbol: "safari", help: "Open \(entry.url.absoluteString)") {
                store.open(entry)
            }
            ActionButton(symbol: copied ? "checkmark" : "doc.on.doc", help: "Copy \(entry.url.absoluteString)") {
                store.copy(entry.url.absoluteString)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    copied = false
                }
            }
            killControl
        }
    }

    @ViewBuilder private var killControl: some View {
        if confirmingKill {
            Button {
                store.kill(entry, force: NSEvent.modifierFlags.contains(.option))
                confirmingKill = false
            } label: {
                Text("Kill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.red))
            }
            .buttonStyle(.plain)
            .help("Click again to send SIGTERM. Hold ⌥ while clicking to send SIGKILL.")
        } else {
            ActionButton(symbol: "xmark.circle", help: "Kill \(entry.processName) (PID \(entry.pid))", tint: .red) {
                confirmingKill = true
                let token = UUID()
                confirmToken = token
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    if confirmToken == token { confirmingKill = false }
                }
            }
        }
    }

    @ViewBuilder private var contextMenu: some View {
        Button(isExpanded ? "Hide Details" : "What Is This Process?") { toggleDetails() }
        Button("Open \(entry.url.absoluteString)") { store.open(entry) }
        Menu("Copy") {
            Button("URL") { store.copy(entry.url.absoluteString) }
            Button("Port") { store.copy(String(entry.port)) }
            Button("PID") { store.copy(String(entry.pid)) }
            if let commandLine = entry.commandLine {
                Button("Command Line") { store.copy(commandLine) }
            }
        }
        if entry.executablePath != nil {
            Button("Show Executable in Finder") { store.revealExecutable(entry) }
        }
        Divider()
        Button("Kill (SIGTERM)") { store.kill(entry) }
        Button("Force Kill (SIGKILL)") { store.kill(entry, force: true) }
        Button("Kill as Admin…") { store.killAsAdmin(entry, force: false) }
    }
}

struct ActionButton: View {
    let symbol: String
    let help: String
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 22)
        }
        .buttonStyle(IconButtonStyle(tint: tint))
        .help(help)
    }
}

struct ProcessIconView: View {
    let entry: ListeningPort

    var body: some View {
        Group {
            if let image = ProcessIconCache.icon(for: entry) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                    Image(systemName: entry.proto == .udp ? "antenna.radiowaves.left.and.right" : "terminal")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 30, height: 30)
    }
}

/// Resolves and caches an icon for a process: its running app icon, or the
/// icon of the .app bundle the executable lives in. CLI tools get nil.
@MainActor
enum ProcessIconCache {
    private static var cache: [String: NSImage] = [:]
    private static var misses: Set<String> = []

    static func icon(for entry: ListeningPort) -> NSImage? {
        let key = entry.appBundlePath ?? "pid:\(entry.pid)"
        if let cached = cache[key] { return cached }
        if misses.contains(key) { return nil }

        var image: NSImage?
        if let app = NSRunningApplication(processIdentifier: entry.pid), let appIcon = app.icon {
            image = appIcon
        } else if let bundle = entry.appBundlePath, FileManager.default.fileExists(atPath: bundle) {
            image = NSWorkspace.shared.icon(forFile: bundle)
        }
        if let image {
            cache[key] = image
        } else {
            misses.insert(key)
        }
        return image
    }
}
