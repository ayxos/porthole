import Foundation

enum SocketProtocol: String, Codable, Hashable {
    case tcp = "TCP"
    case udp = "UDP"
}

/// One listening socket. A server bound to the same port on IPv4 and IPv6
/// is merged into a single entry with several addresses.
struct ListeningPort: Identifiable, Hashable, Codable {
    let proto: SocketProtocol
    let port: Int
    let pid: Int32
    var addresses: [String]
    var processName: String
    var executablePath: String?
    var commandLine: String?
    var user: String
    /// Physical memory footprint in bytes, as Activity Monitor reports it.
    var memory: UInt64?
    /// Total CPU time consumed so far, in seconds.
    var cpuTime: TimeInterval?

    var id: String { "\(proto.rawValue)/\(port)/\(pid)" }
    /// Identity that survives a restart of the same server on the same port.
    var portKey: String { "\(proto.rawValue)/\(port)" }

    static let wildcardHosts: Set<String> = ["*", "0.0.0.0", "::"]
    static let loopbackHosts: Set<String> = ["127.0.0.1", "::1", "localhost"]

    var isLoopbackOnly: Bool {
        !addresses.isEmpty && addresses.allSatisfy { Self.loopbackHosts.contains($0) }
    }

    var isWildcard: Bool {
        addresses.contains { Self.wildcardHosts.contains($0) }
    }

    var bindDescription: String {
        if isLoopbackOnly { return "localhost only" }
        if isWildcard { return "all interfaces" }
        return addresses.joined(separator: ", ")
    }

    /// Host to use when opening the port in a browser.
    var urlHost: String {
        if let specific = addresses.first(where: {
            !Self.wildcardHosts.contains($0) && !Self.loopbackHosts.contains($0)
        }) {
            return specific.contains(":") ? "[\(specific)]" : specific
        }
        return "localhost"
    }

    var url: URL {
        URL(string: "http://\(urlHost):\(port)") ?? URL(string: "http://localhost:\(port)")!
    }

    /// Path of the enclosing .app bundle, if the executable lives inside one.
    var appBundlePath: String? {
        guard let path = executablePath, let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    var serviceHint: String? { KnownServices.hint(for: self) }
}
