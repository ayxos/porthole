import AppKit
import SwiftUI

/// Expanded "what is this process?" section shown under a port row.
struct ProcessDetailView: View {
    @EnvironmentObject private var store: PortStore
    let entry: ListeningPort

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let details = store.details[entry.pid] {
                Text(details.summary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let advice = details.advice {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "lightbulb")
                            .font(.caption)
                        Text(advice)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                chips(details)
                facts(details)
                actions(details)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking up \(entry.processName)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.045)))
    }

    @ViewBuilder private func chips(_ details: ProcessDetails) -> some View {
        let items: [(String, String)] = [
            details.category.map { ("tag", $0) },
            details.signature.map { ($0.hasPrefix("Signed by Apple") || $0.hasPrefix("Developer ID") ? "checkmark.seal" : "questionmark.diamond", $0) },
        ].compactMap { $0 }
        if !items.isEmpty {
            HStack(spacing: 6) {
                ForEach(items, id: \.1) { symbol, text in
                    HStack(spacing: 3) {
                        Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                        Text(text).lineLimit(1).truncationMode(.middle)
                    }
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func facts(_ details: ProcessDetails) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 3) {
            if let path = entry.executablePath {
                fact("Executable", path, help: path)
            }
            if let commandLine = entry.commandLine, commandLine != entry.executablePath {
                fact("Command", commandLine, help: commandLine)
            }
            if let folder = details.workingDirectory, folder != "/" {
                fact("Folder", abbreviate(folder), help: folder)
            }
            if let project = details.project {
                fact("Project", project)
            }
            if let bundleID = details.bundleID {
                fact("Bundle ID", bundleID)
            }
            if let parent = details.parent {
                fact("Parent", parent)
            }
            if let started = details.started {
                fact("Started", relative(started))
            }
            let resourceText = resources(details)
            if !resourceText.isEmpty {
                fact("Resources", resourceText)
            }
            if let item = store.portHistory(for: entry) {
                fact("History", historyText(item))
            }
            let siblings = store.ports.filter { $0.pid == entry.pid && $0.id != entry.id }
            if !siblings.isEmpty {
                fact("Also on", siblings.map { ":\($0.port)" }.joined(separator: "  "))
            }
            if !entry.user.isEmpty {
                fact("User", entry.user)
            }
        }
    }

    private func fact(_ label: String, _ value: String, help: String? = nil) -> some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(help ?? value)
        }
    }

    private func actions(_ details: ProcessDetails) -> some View {
        HStack(spacing: 8) {
            Button {
                NSWorkspace.shared.open(searchURL)
            } label: {
                Label("Search the web", systemImage: "magnifyingglass")
            }
            if entry.executablePath != nil {
                Button {
                    store.revealExecutable(entry)
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
            }
            Button {
                store.copy(report(details))
            } label: {
                Label("Copy details", systemImage: "doc.on.clipboard")
            }
            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.top, 2)
    }

    // MARK: Helpers

    private var searchURL: URL {
        let query = "\(entry.processName) process macOS"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? entry.processName
        return URL(string: "https://www.google.com/search?q=\(query)")!
    }

    private func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 5 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func resources(_ details: ProcessDetails) -> String {
        var parts: [String] = []
        if let cpu = store.cpuPercent[entry.pid] {
            parts.append("\(Format.cpuPercent(cpu)) CPU")
        }
        if let memory = details.memory ?? entry.memory {
            parts.append(Format.memory(memory))
        }
        if let cpuTime = details.cpuTime ?? entry.cpuTime {
            parts.append("\(Format.duration(cpuTime)) CPU time")
        }
        return parts.joined(separator: " · ")
    }

    private func historyText(_ item: PortStore.PortHistory) -> String {
        let since = item.firstSeen.formatted(date: .omitted, time: .shortened)
        guard let last = item.restarts.last else {
            return "No restarts since first seen at \(since)"
        }
        let count = item.restarts.count
        return "\(count) \(count == 1 ? "restart" : "restarts") in the last hour, last \(relative(last))"
    }

    private func report(_ details: ProcessDetails) -> String {
        var lines = [":\(entry.port) \(entry.processName) (PID \(entry.pid))", details.summary]
        if let advice = details.advice { lines.append("Tip: \(advice)") }
        if let path = entry.executablePath { lines.append("Executable: \(path)") }
        if let commandLine = entry.commandLine { lines.append("Command: \(commandLine)") }
        if let folder = details.workingDirectory { lines.append("Folder: \(folder)") }
        if let project = details.project { lines.append("Project: \(project)") }
        if let bundleID = details.bundleID { lines.append("Bundle ID: \(bundleID)") }
        if let parent = details.parent { lines.append("Parent: \(parent)") }
        if let signature = details.signature { lines.append("Signature: \(signature)") }
        if let started = details.started { lines.append("Started: \(started.formatted())") }
        let resourceText = resources(details)
        if !resourceText.isEmpty { lines.append("Resources: \(resourceText)") }
        if let item = store.portHistory(for: entry) { lines.append("History: \(historyText(item))") }
        lines.append("Bind: \(entry.bindDescription) (\(entry.addresses.joined(separator: ", ")))")
        if !entry.user.isEmpty { lines.append("User: \(entry.user)") }
        return lines.joined(separator: "\n")
    }
}
