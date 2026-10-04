import Foundation

/// `Porthole --list [--udp]` / `Porthole --json [--udp]` print the port table and exit,
/// so the same binary doubles as a terminal tool.
enum PortholeCLI {
    private static let usage = """
    Porthole — listening ports in your menu bar

      Porthole                 launch the menu bar app
      Porthole --list [--udp]  print listening ports as a table
      Porthole --json [--udp]  print listening ports as JSON
      Porthole --help          this text
    """

    static func runIfRequested() {
        let args = Set(CommandLine.arguments.dropFirst())
        if args.contains("--help") || args.contains("-h") {
            print(usage)
            exit(0)
        }
        let wantsList = args.contains("--list") || args.contains("-l")
        let wantsJSON = args.contains("--json")
        guard wantsList || wantsJSON else { return }

        let ports = PortScanner.scan(includeUDP: args.contains("--udp"))
        if wantsJSON {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = (try? encoder.encode(ports)) ?? Data("[]".utf8)
            print(String(decoding: data, as: UTF8.self))
        } else {
            printTable(ports)
        }
        exit(0)
    }

    private static func printTable(_ ports: [ListeningPort]) {
        guard !ports.isEmpty else {
            print("Nothing is listening.")
            return
        }
        let rows: [[String]] = ports.map { p in
            [String(p.port), p.proto.rawValue, String(p.pid), p.user, p.processName,
             p.memory.map(Format.memory) ?? "", p.bindDescription, p.serviceHint ?? ""]
        }
        let header = ["PORT", "PROTO", "PID", "USER", "PROCESS", "MEM", "BIND", "HINT"]
        var widths = header.map(\.count)
        for row in rows {
            for (i, cell) in row.enumerated() { widths[i] = max(widths[i], cell.count) }
        }
        func line(_ cells: [String]) -> String {
            cells.enumerated()
                .map { $0.offset == cells.count - 1 ? $0.element : $0.element.padding(toLength: widths[$0.offset], withPad: " ", startingAt: 0) }
                .joined(separator: "  ")
                .trimmingCharacters(in: .whitespaces)
        }
        print(line(header))
        for row in rows { print(line(row)) }
    }
}
