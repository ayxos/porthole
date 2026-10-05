import AppKit
import SwiftUI

struct FooterView: View {
    @EnvironmentObject private var store: PortStore

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let updated = store.lastUpdated {
                    Text("Updated ") + Text(updated, style: .relative) + Text(" ago")
                } else {
                    Text("Scanning…")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            if let error = store.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(error)
            }
            Spacer()
            if let update = store.availableUpdate {
                Button("Update: \(update.version)") { NSWorkspace.shared.open(update.url) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .help("Porthole \(update.version) is available. Opens the release page.")
            }
            Menu {
                settingsMenu
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 26, height: 22)
            }
            .menuStyle(.button)
            .buttonStyle(IconButtonStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Settings")
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 26, height: 22)
            }
            .buttonStyle(IconButtonStyle())
            .keyboardShortcut("q", modifiers: .command)
            .help("Quit Porthole (⌘Q)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder private var settingsMenu: some View {
        Toggle("Include UDP sockets", isOn: $store.includeUDP)
        Toggle("Show port count in menu bar", isOn: $store.showCountInMenuBar)
        Picker("Refresh every", selection: $store.refreshInterval) {
            Text("1 second").tag(1.0)
            Text("2 seconds").tag(2.0)
            Text("3 seconds").tag(3.0)
            Text("5 seconds").tag(5.0)
            Text("10 seconds").tag(10.0)
        }
        Picker("Sort by", selection: $store.sortOrder) {
            ForEach(PortStore.SortOrder.allCases) { order in
                Text(order.label).tag(order)
            }
        }
        Toggle("Launch at login", isOn: Binding(
            get: { store.launchAtLogin },
            set: { store.setLaunchAtLogin($0) }
        ))
        Toggle("Check for updates daily", isOn: $store.checkForUpdates)
        Divider()
        Text("Porthole \(AppInfo.version) · ayxosLabs")
        Button("Quit Porthole") { NSApp.terminate(nil) }
    }
}
