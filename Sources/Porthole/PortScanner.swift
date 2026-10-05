import Darwin
import Foundation

/// Builds the list of listening ports.
///
/// 1. libproc enumerates sockets of every process we may inspect (own user, or
///    everything when running as root). This is the dependable source.
/// 2. `netstat -anv` is consulted as a supplement: when macOS lets it see the
///    kernel socket table it also reports other users' daemons. On recent
///    macOS versions it only does so for processes with the right privilege
///    attribution, so an empty result is expected and simply ignored.
/// 3. Process metadata comes from libproc/sysctl, with `ps` as a fallback for
///    PIDs we cannot inspect directly.
enum PortScanner {
    private static var netstatCooldown = 0

    static func scan(includeUDP: Bool) -> [ListeningPort] {
        var merged: [String: ListeningPort] = [:]
        var order: [String] = []

        func add(proto: SocketProtocol, port: Int, pid: pid_t, host: String) {
            let key = "\(proto.rawValue)/\(port)/\(pid)"
            if var existing = merged[key] {
                if !existing.addresses.contains(host) { existing.addresses.append(host) }
                merged[key] = existing
            } else {
                merged[key] = ListeningPort(proto: proto, port: port, pid: pid, addresses: [host],
                                            processName: "pid \(pid)", executablePath: nil,
                                            commandLine: nil, user: "")
                order.append(key)
            }
        }

        for socket in NativeSocketScanner.listeningSockets(includeUDP: includeUDP) {
            add(proto: socket.proto, port: socket.port, pid: socket.pid, host: socket.host)
        }

        if netstatCooldown > 0 {
            netstatCooldown -= 1
        } else {
            var found = 0
            let protocols: [SocketProtocol] = includeUDP ? [.tcp, .udp] : [.tcp]
            for proto in protocols {
                for entry in netstatListeners(proto: proto) {
                    found += 1
                    for host in entry.addresses {
                        add(proto: proto, port: entry.port, pid: entry.pid, host: host)
                    }
                }
            }
            // netstat adds nothing in this context: stop paying for it on every refresh.
            if found == 0 { netstatCooldown = 20 }
        }

        var entries = order.compactMap { merged[$0] }
        enrich(&entries)
        return entries.sorted { a, b in
            if a.port != b.port { return a.port < b.port }
            if a.proto != b.proto { return a.proto == .tcp }
            return a.pid < b.pid
        }
    }

    // MARK: netstat

    private static func netstatListeners(proto: SocketProtocol) -> [ListeningPort] {
        guard let output = try? Shell.run("/usr/sbin/netstat", ["-anv", "-p", proto == .tcp ? "tcp" : "udp"]),
              output.status == 0 else { return [] }
        return parseNetstat(output.stdout, proto: proto)
    }

    // Matches the "process:pid" column on recent macOS, e.g. "ControlCenter:629    00100 00000006".
    // Process names may contain spaces, so columns cannot simply be split on whitespace.
    private static let pidRegex = try! NSRegularExpression(pattern: #":(\d+)\s+[0-9A-Fa-f]{4,}\s"#)

    static func parseNetstat(_ output: String, proto: SocketProtocol) -> [ListeningPort] {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard let headerIndex = lines.firstIndex(where: { $0.hasPrefix("Proto") }) else { return [] }
        let header = lines[headerIndex].split(separator: " ").map(String.init)
        let hasProcessColumn = header.contains("process:pid")
        // "Local Address" and "Foreign Address" are one column each in the rows
        // but two words in the header.
        let legacyPidColumn = header.firstIndex(of: "pid").map { pid in
            pid - header[..<pid].filter { $0 == "Address" }.count
        }
        let hasStateColumn = header.contains("(state)")
        let prefix = proto == .tcp ? "tcp" : "udp"

        var merged: [String: ListeningPort] = [:]
        var order: [String] = []

        for line in lines[(headerIndex + 1)...] {
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 5, tokens[0].hasPrefix(prefix) else { continue }
            let local = tokens[3]
            let foreign = tokens[4]
            if proto == .tcp {
                guard tokens.count > 5, tokens[5] == "LISTEN" else { continue }
            } else {
                guard foreign == "*.*" else { continue }  // unconnected UDP socket = "listening"
            }
            guard let (host, port) = splitHostPort(local) else { continue }

            var pid: Int32?
            if hasProcessColumn {
                pid = modernPID(in: line)
            } else if let column = legacyPidColumn {
                // UDP rows have no state token even though the header has one.
                let index = (proto == .udp && hasStateColumn) ? column - 1 : column
                pid = index < tokens.count ? Int32(tokens[index]) : nil
            }
            guard let pid else { continue }

            let key = "\(proto.rawValue)/\(port)/\(pid)"
            if var existing = merged[key] {
                if !existing.addresses.contains(host) { existing.addresses.append(host) }
                merged[key] = existing
            } else {
                merged[key] = ListeningPort(proto: proto, port: port, pid: pid, addresses: [host],
                                            processName: "pid \(pid)", executablePath: nil,
                                            commandLine: nil, user: "")
                order.append(key)
            }
        }
        return order.compactMap { merged[$0] }
    }

    private static func modernPID(in line: String) -> Int32? {
        let ns = line as NSString
        let matches = pidRegex.matches(in: line, range: NSRange(location: 0, length: ns.length))
        guard let last = matches.last else { return nil }
        return Int32(ns.substring(with: last.range(at: 1)))
    }

    /// "*.7000" -> ("*", 7000), "127.0.0.1.19847" -> ("127.0.0.1", 19847),
    /// "fe80::1%lo0.3000" -> ("fe80::1", 3000), "*.*" -> nil
    static func splitHostPort(_ address: String) -> (String, Int)? {
        guard let dot = address.lastIndex(of: "."),
              let port = Int(address[address.index(after: dot)...]) else { return nil }
        var host = String(address[..<dot])
        if let percent = host.firstIndex(of: "%") { host = String(host[..<percent]) }
        return (host, port)
    }

    // MARK: Process metadata

    private static func enrich(_ entries: inout [ListeningPort]) {
        let pids = Set(entries.map(\.pid))
        guard !pids.isEmpty else { return }

        var details: [pid_t: ProcessInspector.Details] = [:]
        var unresolved: [pid_t] = []
        for pid in pids {
            let info = ProcessInspector.details(for: pid)
            details[pid] = info
            if info.path == nil { unresolved.append(pid) }
        }
        if !unresolved.isEmpty {
            fillFromPS(pids: unresolved, into: &details)
        }

        var usage: [pid_t: (memory: UInt64, cpuTime: TimeInterval)] = [:]
        for pid in pids {
            if let sample = ProcessInspector.resourceUsage(of: pid) { usage[pid] = sample }
        }

        for index in entries.indices {
            if let sample = usage[entries[index].pid] {
                entries[index].memory = sample.memory
                entries[index].cpuTime = sample.cpuTime
            }
            guard let info = details[entries[index].pid] else { continue }
            entries[index].executablePath = info.path
            entries[index].commandLine = info.commandLine
            if let path = info.path {
                entries[index].processName = (path as NSString).lastPathComponent
            } else if let name = info.name {
                entries[index].processName = name
            }
            if let uid = info.uid {
                entries[index].user = ProcessInspector.userName(uid: uid)
            }
        }
    }

    /// `ps` can report path, owner and arguments for processes libproc will not let us open.
    private static func fillFromPS(pids: [pid_t], into details: inout [pid_t: ProcessInspector.Details]) {
        let list = pids.map(String.init).joined(separator: ",")
        if let output = try? Shell.run("/bin/ps", ["-ww", "-o", "pid=,uid=,comm=", "-p", list]) {
            for line in output.stdout.split(whereSeparator: \.isNewline) {
                let parts = line.trimmingCharacters(in: .whitespaces)
                    .split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard parts.count == 3, let pid = Int32(parts[0]) else { continue }
                details[pid, default: .init()].path = String(parts[2])
                if let uid = uid_t(parts[1]) { details[pid, default: .init()].uid = uid }
            }
        }
        if let output = try? Shell.run("/bin/ps", ["-ww", "-o", "pid=,args=", "-p", list]) {
            for line in output.stdout.split(whereSeparator: \.isNewline) {
                let parts = line.trimmingCharacters(in: .whitespaces)
                    .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count == 2, let pid = Int32(parts[0]) else { continue }
                details[pid, default: .init()].commandLine = String(parts[1])
            }
        }
    }
}
