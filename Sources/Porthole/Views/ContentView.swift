import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PortStore
    @FocusState private var searchFocused: Bool
    @State private var listHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    private let maxListHeight: CGFloat = 560

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            Divider()
            list
            Divider()
            FooterView()
        }
        .frame(width: 400)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            contentHeight = height
        }
        .background(WindowBridge(contentHeight: contentHeight) { visible in store.isWindowVisible = visible })
        .onAppear {
            store.isWindowVisible = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { searchFocused = true }
        }
        .onDisappear { store.isWindowVisible = false }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: MenuBarIcon.image)
                .renderingMode(.template)
            Text("Porthole")
                .font(.headline)
            let count = store.uniquePortCount
            Text(verbatim: "\(count) \(count == 1 ? "port" : "ports")")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            Spacer()
            Button { store.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(IconButtonStyle())
            .help("Refresh now")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter by port, process, PID…", text: $store.filter)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !store.filter.isEmpty {
                Button { store.filter = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder private var list: some View {
        let rows = store.filtered
        if rows.isEmpty {
            EmptyStateView(hasFilter: !store.filter.isEmpty, error: store.lastError)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { entry in
                        PortRow(entry: entry)
                        if entry.id != rows.last?.id {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
                .animation(.easeOut(duration: 0.15), value: store.expandedIDs)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    listHeight = height
                }
            }
            // Start from an estimate: a scroll view that begins at ~0pt never lays out
            // its content, so the measured height would never arrive.
            .frame(height: min(listHeight > 0 ? listHeight : CGFloat(rows.count) * 46, maxListHeight))
        }
    }
}

struct EmptyStateView: View {
    let hasFilter: Bool
    let error: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: hasFilter ? "magnifyingglass" : "moon.zzz")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(hasFilter ? "No ports match your filter" : "Nothing is listening")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// Borderless icon button with a subtle hover highlight.
struct IconButtonStyle: ButtonStyle {
    var tint: Color = .secondary
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hovering ? Color.primary : tint)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.1 : 0))
            )
            .opacity(configuration.isPressed ? 0.55 : 1)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
