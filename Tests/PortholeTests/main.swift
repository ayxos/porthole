import Foundation

// A dependency-free test runner: scripts/test.sh compiles this file together with
// the app's non-UI sources, so it works with the Command Line Tools alone (no XCTest).

var failures = 0
var checks = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    checks += 1
    if !condition() {
        failures += 1
        print("✗ \(file):\(line): \(message)")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    expect(actual == expected, "expected \(expected), got \(actual)", file: file, line: line)
}

func port(_ number: Int, _ name: String, addresses: [String] = ["*"], commandLine: String? = nil,
          path: String? = nil) -> ListeningPort {
    ListeningPort(proto: .tcp, port: number, pid: 4242, addresses: addresses, processName: name,
                  executablePath: path, commandLine: commandLine, user: "me")
}

// MARK: netstat parsing

let modernTCP = """
Active Internet connections (including servers)
Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)          rxbytes      txbytes  rhiwat  shiwat          process:pid    state  options           gencnt    flags   flags1 usecnt rtncnt fltrs
tcp4       0      0  192.168.0.105.59739    108.177.127.109.993    ESTABLISHED        19042         2908  131072  131600             Mail:935    00102 00020000 000000000005b500 00180081 04084900      2      0 000000
tcp4       0      0  *.7000                 *.*                    LISTEN                 0            0  131072  131072    ControlCenter:629    00100 00000006 0000000000000a1c 00000000 00000900      1      0 000000
tcp6       0      0  *.7000                 *.*                    LISTEN                 0            0  131072  131072    ControlCenter:629    00100 00000006 0000000000000a1b 00000000 00000900      1      0 000000
tcp4       0      0  127.0.0.1.5037         *.*                    LISTEN                 0            0  131072  131072              adb:21865  00100 00000006 000000000005b822 00000000 00000900      1      0 000000
tcp4       0      0  *.8080                 *.*                    LISTEN                 0            0  131072  131072 Brave Browser He:855    00100 00000006 000000000005b822 00000000 00000900      1      0 000000
"""

let tcp = PortScanner.parseNetstat(modernTCP, proto: .tcp)
expectEqual(tcp.map(\.port), [7000, 5037, 8080])
expectEqual(tcp.map(\.pid), [629, 21865, 855])
expectEqual(tcp.first?.addresses ?? [], ["*"])  // IPv4 and IPv6 rows merge into one entry
expectEqual(tcp[1].addresses, ["127.0.0.1"])
expect(tcp[1].isLoopbackOnly, "127.0.0.1 is loopback only")

let modernUDP = """
Active Internet connections (including servers)
Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)          rxbytes      txbytes  rhiwat  shiwat          process:pid    state  options           gencnt    flags   flags1 usecnt rtncnt fltrs
udp4       0      0  *.5353                 *.*                                         258           99  786896    9216              adb:21865  00100 00000204 000000000005b823 00000001 04000800      1      0 000002
udp4       0      0  192.168.0.105.64161    108.177.119.95.443                        13398         5574 1048576   29040 Brave Browser He:855    00102 00000000 000000000005b699 00000000 04200900      1      0 000002
"""

let udp = PortScanner.parseNetstat(modernUDP, proto: .udp)
expectEqual(udp.map(\.port), [5353])  // connected UDP sockets are not listeners
expectEqual(udp.first?.pid, 21865)

let legacyTCP = """
Active Internet connections (including servers)
Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)     rhiwat shiwat    pid   epid  state    options
tcp4       0      0  *.3000                 *.*                    LISTEN      131072 131072  12345      0 0x0100 0x00000006
"""

let legacy = PortScanner.parseNetstat(legacyTCP, proto: .tcp)
expectEqual(legacy.map(\.port), [3000])
expectEqual(legacy.first?.pid, 12345)

let legacyUDP = """
Active Internet connections (including servers)
Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)     rhiwat shiwat    pid   epid  state    options
udp4       0      0  *.5353                 *.*                                196724   9216    321      0 0x0100 0x00000000
"""

expectEqual(PortScanner.parseNetstat(legacyUDP, proto: .udp).first?.pid, 321)  // UDP rows have no state token
expectEqual(PortScanner.parseNetstat("garbage", proto: .tcp).count, 0)

// MARK: host / port splitting

expect(PortScanner.splitHostPort("*.7000").map { $0 == ("*", 7000) } ?? false, "*.7000")
expect(PortScanner.splitHostPort("127.0.0.1.19847").map { $0 == ("127.0.0.1", 19847) } ?? false, "IPv4 host")
expect(PortScanner.splitHostPort("fe80::1%lo0.3000").map { $0 == ("fe80::1", 3000) } ?? false, "IPv6 scope stripped")
expect(PortScanner.splitHostPort("*.*") == nil, "*.* has no port")

// MARK: ListeningPort

expectEqual(port(80, "x", addresses: ["127.0.0.1", "::1"]).bindDescription, "localhost only")
expectEqual(port(80, "x", addresses: ["127.0.0.1", "*"]).bindDescription, "all interfaces")
expectEqual(port(80, "x", addresses: ["192.168.1.2"]).bindDescription, "192.168.1.2")
expectEqual(port(3000, "x").url.absoluteString, "http://localhost:3000")
expectEqual(port(3000, "x", addresses: ["fe80::1"]).url.absoluteString, "http://[fe80::1]:3000")
expectEqual(port(80, "x", path: "/Applications/Foo.app/Contents/MacOS/Foo").appBundlePath, "/Applications/Foo.app")
expectEqual(port(80, "x", path: "/usr/sbin/httpd").appBundlePath, nil)

// MARK: Known services

expectEqual(port(5000, "ControlCenter").serviceHint, "AirPlay Receiver")      // process beats port
expectEqual(port(5173, "node").serviceHint, "Vite")                           // node without a command line
expectEqual(port(8000, "Python", commandLine: "/usr/bin/python3 -m http.server").serviceHint, "http.server")
expectEqual(port(3000, "node", commandLine: "node /p/node_modules/.bin/next dev").serviceHint, "next")
expectEqual(port(49152, "ollama").serviceHint, "Ollama")
expectEqual(port(49152, "unknown").serviceHint, nil)

// MARK: Process knowledge

expect(ProcessKnowledgeBase.lookup(port(5000, "ControlCenter"))?.category == "macOS", "ControlCenter is described")
expectEqual(ProcessKnowledgeBase.helperAppName("Notion Helper (Renderer)"), "Notion")
expectEqual(ProcessKnowledgeBase.helperAppName("Helper"), nil)
expect(ProcessKnowledgeBase.lookup(port(1, "Notion Helper (Renderer)"))?.summary.hasPrefix("Helper process of Notion") ?? false,
       "unknown helpers get a generic explanation")

// MARK: Process details

let formula = ProcessDetails.homebrewFormula("/opt/homebrew/Cellar/postgresql@16/16.4/bin/postgres")
expectEqual(formula?.formula, "postgresql@16")
expectEqual(formula?.version, "16.4")
expect(ProcessDetails.homebrewFormula("/usr/bin/true") == nil, "no formula outside the Cellar")

let project = FileManager.default.temporaryDirectory.appendingPathComponent("porthole-test-\(getpid())")
try? FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
try? Data(#"{"name": "my-app"}"#.utf8).write(to: project.appendingPathComponent("package.json"))
expectEqual(ProcessDetails.detectProject(port(3000, "node", commandLine: "node \(project.path)/node_modules/.bin/vite"),
                                         workingDirectory: nil),
            "vite · Node project my-app")
expectEqual(ProcessDetails.detectProject(port(3000, "node"), workingDirectory: project.path), "Node project my-app")
expectEqual(ProcessDetails.detectProject(port(3000, "node"), workingDirectory: "/"), nil)
try? FileManager.default.removeItem(at: project)

// MARK: Formatting

expectEqual(Format.memory(512 * 1024), "512 KB")
expectEqual(Format.memory(4 * 1_048_576), "4.0 MB")
expectEqual(Format.memory(459 * 1_048_576), "459 MB")
expectEqual(Format.memory(3 * 1_073_741_824), "3.0 GB")
expectEqual(Format.cpuPercent(2.345), "2.3%")
expectEqual(Format.cpuPercent(42.6), "43%")
expectEqual(Format.duration(5), "5.0 s")
expectEqual(Format.duration(600), "10 min")
expectEqual(Format.duration(5400), "1.5 h")

// MARK: Update checks

expect(UpdateChecker.isNewer("1.0.1", than: "1.0.0"), "patch bump")
expect(UpdateChecker.isNewer("1.10.0", than: "1.9.2"), "numeric, not lexical")
expect(!UpdateChecker.isNewer("1.0", than: "1.0.0"), "missing components count as zero")
expect(!UpdateChecker.isNewer("0.9.9", than: "1.0.0"), "older")
expect(UpdateChecker.isNewer("2.0.0-beta", than: "1.9"), "suffixes are ignored")

let release = UpdateChecker.parseRelease(Data("""
{"tag_name": "v1.2.3", "html_url": "https://github.com/ayxos/porthole/releases/tag/v1.2.3", "draft": false, "prerelease": false}
""".utf8))
expectEqual(release?.version, "1.2.3")
expectEqual(release?.url.absoluteString, "https://github.com/ayxos/porthole/releases/tag/v1.2.3")
expect(UpdateChecker.parseRelease(Data(#"{"tag_name": "v9", "html_url": "https://x", "prerelease": true}"#.utf8)) == nil,
       "prereleases are skipped")
expect(UpdateChecker.parseRelease(Data("not json".utf8)) == nil, "bad JSON")

// MARK: Live scan smoke test

let live = PortScanner.scan(includeUDP: true)
expect(live.allSatisfy { $0.port > 0 && $0.port < 65536 }, "scanned ports are in range")
expectEqual(live.map(\.port), live.map(\.port).sorted())

print(failures == 0 ? "✓ \(checks) checks passed" : "✗ \(failures) of \(checks) checks failed")
exit(failures == 0 ? 0 : 1)
