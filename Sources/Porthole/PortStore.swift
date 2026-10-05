import AppKit
import Combine
import OSLog
import ServiceManagement

@MainActor
final class PortStore: ObservableObject {
    struct Notice: Equatable {
        enum Kind: Equatable {
            case info
            case warning
            case needsAdmin(force: Bool)
        }
        let text: String
        let kind: Kind
    }

    @Published private(set) var ports: [ListeningPort] = []
    @Published var filter = ""
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var notices: [String: Notice] = [:]
    @Published private(set) var launchAtLogin = false
    @Published private(set) var expandedIDs: Set<String> = []
    @Published private(set) var details: [pid_t: ProcessDetails] = [:]
    /// CPU usage per process between the last two scans, in percent of one core.
    @Published private(set) var cpuPercent: [pid_t: Double] = [:]
    /// What Porthole has observed about each port since it started.
    @Published private(set) var history: [String: PortHistory] = [:]

    struct PortHistory: Equatable {
        var firstSeen: Date
        var lastSeen: Date
        var lastPID: pid_t
        var processName: String
        var restarts: [Date]
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case port, name, memory, cpu
        var id: String { rawValue }
        var label: String {
            switch self {
            case .port: return "Port"
            case .name: return "Process name"
            case .memory: return "Memory"
            case .cpu: return "CPU"
            }
        }
    }

    /// Row shown in its hover state without a mouse, used by `--preview --demo` to record the README GIF.
    @Published var demoHoverKey: String?

    @Published var sortOrder: SortOrder {
        didSet { defaults.set(sortOrder.rawValue, forKey: Keys.sortOrder) }
    }

    @Published var includeUDP: Bool {
        didSet { defaults.set(includeUDP, forKey: Keys.includeUDP); refresh() }
    }
    @Published var showCountInMenuBar: Bool {
        didSet { defaults.set(showCountInMenuBar, forKey: Keys.showCount); rescheduleTimer() }
    }
    @Published var refreshInterval: Double {
        didSet { defaults.set(refreshInterval, forKey: Keys.interval); rescheduleTimer() }
    }
    @Published var checkForUpdates: Bool {
        didSet {
            defaults.set(checkForUpdates, forKey: Keys.checkForUpdates)
            if checkForUpdates { checkForUpdate() } else { availableUpdate = nil }
        }
    }
    /// A newer release on GitHub, when `checkForUpdates` is on and one exists.
    @Published private(set) var availableUpdate: UpdateChecker.Release?

    /// Set by the content view. Drives the refresh cadence.
    var isWindowVisible = false {
        didSet {
            guard oldValue != isWindowVisible else { return }
            debugLog("window visible: \(isWindowVisible)")
            rescheduleTimer()
            if isWindowVisible { refresh() }
        }
    }

    /// `PORTHOLE_DEBUG=1 Porthole` prints scan and visibility events to stderr.
    private static let debugEnabled = ProcessInfo.processInfo.environment["PORTHOLE_DEBUG"] != nil
    private func debugLog(_ message: @autoclosure () -> String) {
        guard Self.debugEnabled else { return }
        fputs("[porthole \(Date().formatted(date: .omitted, time: .standard))] \(message())\n", stderr)
    }

    let currentUser = NSUserName()
    private static let log = Logger(subsystem: "com.ayxos.porthole", category: "scan")

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var scanning = false
    private var refreshQueued = false
    private var cpuSamples: [pid_t: (cpuTime: TimeInterval, at: Date)] = [:]
    private var updateTimer: Timer?

    private enum Keys {
        static let includeUDP = "includeUDP"
        static let showCount = "showCountInMenuBar"
        static let interval = "refreshInterval"
        static let sortOrder = "sortOrder"
        static let checkForUpdates = "checkForUpdates"
    }

    init() {
        includeUDP = defaults.bool(forKey: Keys.includeUDP)
        showCountInMenuBar = defaults.object(forKey: Keys.showCount) as? Bool ?? true
        let saved = defaults.double(forKey: Keys.interval)
        refreshInterval = saved > 0 ? saved : 3
        sortOrder = SortOrder(rawValue: defaults.string(forKey: Keys.sortOrder) ?? "") ?? .port
        checkForUpdates = defaults.object(forKey: Keys.checkForUpdates) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        refresh()
        rescheduleTimer()
        scheduleUpdateChecks()
    }

    // MARK: Derived

    var uniquePortCount: Int { Set(ports.map(\.port)).count }

    var filtered: [ListeningPort] {
        var query = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.hasPrefix(":") { query.removeFirst() }
        let matching = query.isEmpty ? ports : ports.filter { entry in
            String(entry.port).contains(query)
                || String(entry.pid) == query
                || entry.processName.lowercased().contains(query)
                || entry.user.lowercased().contains(query)
                || (entry.serviceHint?.lowercased().contains(query) ?? false)
                || (entry.commandLine?.lowercased().contains(query) ?? false)
                || entry.addresses.contains { $0.contains(query) }
        }
        switch sortOrder {
        case .port:
            return matching
        case .name:
            return matching.sorted { ($0.processName.lowercased(), $0.port) < ($1.processName.lowercased(), $1.port) }
        case .memory:
            return matching.sorted { ($0.memory ?? 0, $1.port) > ($1.memory ?? 0, $0.port) }
        case .cpu:
            return matching.sorted {
                (cpuPercent[$0.pid] ?? -1, $0.memory ?? 0, $1.port) > (cpuPercent[$1.pid] ?? -1, $1.memory ?? 0, $0.port)
            }
        }
    }

    func portHistory(for entry: ListeningPort) -> PortHistory? {
        history["\(entry.proto.rawValue)/\(entry.port)"]
    }

    func restartCount(for entry: ListeningPort) -> Int {
        portHistory(for: entry)?.restarts.count ?? 0
    }

    // MARK: Scanning

    func refresh() {
        if scanning { refreshQueued = true; return }
        scanning = true
        isRefreshing = true
        let udp = includeUDP
        Task { [weak self] in
            let list = await Task.detached(priority: .userInitiated) {
                PortScanner.scan(includeUDP: udp)
            }.value
            guard let self else { return }
            self.scanning = false
            self.isRefreshing = false
            let now = Date()
            self.recordCPUSamples(list, at: now)
            self.recordHistory(list, at: now)
            self.ports = list
            self.lastUpdated = now
            self.pruneTransientState()
            for entry in list where self.expandedIDs.contains(entry.portKey) {
                self.loadDetails(for: entry)  // keeps memory / CPU figures current
            }
            Self.log.debug("scan finished: \(list.count) listeners")
            self.debugLog("scan: \(list.count) listeners, visible=\(self.isWindowVisible), interval=\(self.timer?.timeInterval ?? 0)s")
            if self.refreshQueued {
                self.refreshQueued = false
                self.refresh()
            }
        }
    }

    /// CPU% = CPU time consumed since the previous scan / wall time elapsed, like Activity Monitor.
    private func recordCPUSamples(_ list: [ListeningPort], at now: Date) {
        var percent: [pid_t: Double] = [:]
        var samples: [pid_t: (cpuTime: TimeInterval, at: Date)] = [:]
        for entry in list {
            guard let cpuTime = entry.cpuTime else { continue }
            samples[entry.pid] = (cpuTime, now)
            if let previous = cpuSamples[entry.pid] {
                let elapsed = now.timeIntervalSince(previous.at)
                if elapsed > 0.2 {
                    percent[entry.pid] = max(0, (cpuTime - previous.cpuTime) / elapsed * 100)
                } else if let old = cpuPercent[entry.pid] {
                    percent[entry.pid] = old
                }
            }
        }
        cpuSamples = samples
        cpuPercent = percent
    }

    /// Tracks when a port changes hands between PIDs of the same program: a dev server
    /// that keeps crashing and restarting shows up here.
    private func recordHistory(_ list: [ListeningPort], at now: Date) {
        var updated = history
        for entry in list {
            let key = "\(entry.proto.rawValue)/\(entry.port)"
            if var item = updated[key] {
                if item.lastPID != entry.pid {
                    if item.processName == entry.processName {
                        item.restarts.append(now)
                    } else {
                        item = PortHistory(firstSeen: now, lastSeen: now, lastPID: entry.pid,
                                           processName: entry.processName, restarts: [])
                    }
                    item.lastPID = entry.pid
                }
                item.lastSeen = now
                item.restarts.removeAll { now.timeIntervalSince($0) > 3600 }
                updated[key] = item
            } else {
                updated[key] = PortHistory(firstSeen: now, lastSeen: now, lastPID: entry.pid,
                                           processName: entry.processName, restarts: [])
            }
        }
        // A port that has been gone for an hour is forgotten; shorter gaps are
        // kept so a restart that falls between two scans is still counted.
        updated = updated.filter { now.timeIntervalSince($0.value.lastSeen) < 3600 }
        if updated != history { history = updated }
    }

    private func rescheduleTimer() {
        timer?.invalidate()
        timer = nil
        let interval: TimeInterval
        if isWindowVisible {
            interval = refreshInterval
        } else if showCountInMenuBar {
            interval = max(refreshInterval * 5, 20)  // keep the badge roughly current
        } else {
            return
        }
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        newTimer.tolerance = interval * 0.25
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func scheduleRefresh(after seconds: Double) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.refresh()
        }
    }

    // MARK: Updates

    private func scheduleUpdateChecks() {
        // Development builds report "dev" and have nothing to compare against.
        guard AppInfo.version != "dev", !CommandLine.arguments.contains("--preview") else { return }
        checkForUpdate()
        let timer = Timer(timeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForUpdate() }
        }
        timer.tolerance = 3600
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
    }

    func checkForUpdate() {
        guard checkForUpdates, AppInfo.version != "dev" else { return }
        Task { [weak self] in
            guard let release = await UpdateChecker.latestRelease(), let self, self.checkForUpdates else { return }
            let newer = UpdateChecker.isNewer(release.version, than: AppInfo.version)
            self.debugLog("update check: latest \(release.version), running \(AppInfo.version)")
            self.availableUpdate = newer ? release : nil
        }
    }

    // MARK: Process details

    /// Expansion is keyed by port, so the panel stays open when the server behind it restarts.
    func isExpanded(_ entry: ListeningPort) -> Bool { expandedIDs.contains(entry.portKey) }

    func toggleDetails(_ entry: ListeningPort) {
        if expandedIDs.contains(entry.portKey) {
            expandedIDs.remove(entry.portKey)
        } else {
            expandedIDs.insert(entry.portKey)
            loadDetails(for: entry)
        }
    }

    private func loadDetails(for entry: ListeningPort) {
        Task { [weak self] in
            let gathered = await Task.detached(priority: .userInitiated) {
                ProcessDetails.gather(for: entry)
            }.value
            guard let self, self.expandedIDs.contains(entry.portKey) else { return }
            if self.details[entry.pid] != gathered {
                self.details[entry.pid] = gathered
            }
        }
    }

    // MARK: Actions

    func open(_ entry: ListeningPort) {
        NSWorkspace.shared.open(entry.url)
    }

    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func revealExecutable(_ entry: ListeningPort) {
        guard let path = entry.executablePath else { return }
        let target = entry.appBundlePath ?? path
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: target)])
    }

    func kill(_ entry: ListeningPort, force: Bool = false) {
        let signal = force ? SIGKILL : SIGTERM
        if Darwin.kill(entry.pid, signal) == 0 {
            setNotice(entry.id, Notice(text: force ? "SIGKILL sent" : "SIGTERM sent, waiting for exit…", kind: .info))
            scheduleRefresh(after: 0.6)
            scheduleRefresh(after: 2.0)
            return
        }
        switch errno {
        case EPERM:
            let owner = entry.user.isEmpty ? "another user" : entry.user
            setNotice(entry.id, Notice(text: "Owned by \(owner), needs admin rights.",
                                       kind: .needsAdmin(force: force)), autoClear: nil)
        case ESRCH:
            setNotice(entry.id, Notice(text: "Process already exited", kind: .info))
            refresh()
        default:
            setNotice(entry.id, Notice(text: String(cString: strerror(errno)), kind: .warning))
        }
    }

    func killAsAdmin(_ entry: ListeningPort, force: Bool) {
        let id = entry.id
        let script = "do shell script \"/bin/kill -\(force ? "KILL" : "TERM") \(entry.pid)\" with administrator privileges"
        setNotice(id, Notice(text: "Waiting for admin authorization…", kind: .info), autoClear: nil)
        Task { [weak self] in
            let ok = await Task.detached(priority: .userInitiated) {
                (try? Shell.run("/usr/bin/osascript", ["-e", script]))?.status == 0
            }.value
            guard let self else { return }
            if ok {
                self.setNotice(id, Notice(text: "Killed with admin privileges", kind: .info))
                self.scheduleRefresh(after: 0.6)
            } else {
                self.setNotice(id, Notice(text: "Admin kill cancelled or failed", kind: .warning))
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = "Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Notices

    private func setNotice(_ id: String, _ notice: Notice, autoClear: TimeInterval? = 4) {
        notices[id] = notice
        guard let autoClear else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(autoClear))
            guard let self, self.notices[id] == notice else { return }
            self.notices[id] = nil
        }
    }

    private func pruneTransientState() {
        let ids = Set(ports.map(\.id))
        let pids = Set(ports.map(\.pid))
        let keys = Set(ports.map(\.portKey))
        notices = notices.filter { ids.contains($0.key) }
        expandedIDs = expandedIDs.filter { keys.contains($0) }
        details = details.filter { pids.contains($0.key) }
    }
}
