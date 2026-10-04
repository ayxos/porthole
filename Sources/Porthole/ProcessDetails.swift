import Darwin
import Foundation
import Security

/// Everything the info panel shows for a process: a plain-language explanation
/// plus live facts gathered through libproc and the Security framework.
struct ProcessDetails: Equatable {
    var summary = ""
    var category: String?
    var advice: String?
    var signature: String?
    var bundleID: String?
    var workingDirectory: String?
    var project: String?
    var parent: String?
    var started: Date?
    var memory: UInt64?
    var cpuTime: TimeInterval?

    static func gather(for entry: ListeningPort) -> ProcessDetails {
        var details = ProcessDetails()
        let pid = entry.pid

        var bsdInfo = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdSize) == bsdSize {
            if bsdInfo.pbi_start_tvsec > 0 {
                details.started = Date(timeIntervalSince1970: TimeInterval(bsdInfo.pbi_start_tvsec))
            }
            let parentPID = pid_t(bsdInfo.pbi_ppid)
            if parentPID > 0 {
                let parentName = parentPID == 1
                    ? "launchd"
                    : ProcessInspector.details(for: parentPID).name ?? ProcessInspector.nameViaPS(parentPID) ?? "pid \(parentPID)"
                details.parent = "\(parentName) (\(parentPID))"
            }
        }
        details.workingDirectory = ProcessInspector.workingDirectory(of: pid)
        if let usage = ProcessInspector.resourceUsage(of: pid) {
            details.memory = usage.memory
            details.cpuTime = usage.cpuTime
        }
        if let path = entry.executablePath {
            details.signature = CodeSignature.describe(path: path)
        }

        let bundle = entry.appBundlePath.flatMap { BundleInfo(path: $0) }
        details.bundleID = bundle?.identifier
        details.project = detectProject(entry, workingDirectory: details.workingDirectory)

        if let known = ProcessKnowledgeBase.lookup(entry) {
            details.summary = known.summary
            details.category = known.category
            details.advice = known.advice
        } else if let bundle {
            var text = bundle.displayName
            if let version = bundle.version { text += " \(version)" }
            if bundle.executableName != entry.processName {
                text = "Helper process of \(text)"
            }
            text += "."
            if let copyright = bundle.copyright { text += " \(copyright)" }
            details.summary = text
            details.category = "App"
        } else if let brew = homebrewFormula(entry.executablePath) {
            details.summary = "Installed with Homebrew: formula \(brew.formula) \(brew.version). The command line below shows how it was started."
            details.category = "Homebrew"
            details.advice = "If it runs as a service, `brew services stop \(brew.formula)` stops it cleanly."
        } else if isSystemPath(entry.executablePath) {
            details.summary = "Part of macOS (\((entry.executablePath! as NSString).deletingLastPathComponent)). System daemons are managed by launchd, which usually relaunches them when killed."
            details.category = "macOS"
        } else {
            details.summary = "No description for \(entry.processName) yet. The command line, folder and signature below usually tell the story, or search the web for it."
        }
        return details
    }

    // MARK: Heuristics

    private static func isSystemPath(_ path: String?) -> Bool {
        guard let path else { return false }
        return ["/System/", "/usr/libexec/", "/usr/sbin/", "/usr/bin/", "/sbin/", "/Library/Apple/"]
            .contains { path.hasPrefix($0) }
    }

    private static let cellarRegex = try! NSRegularExpression(pattern: #"/(?:opt/homebrew|usr/local)/Cellar/([^/]+)/([^/]+)/"#)

    static func homebrewFormula(_ path: String?) -> (formula: String, version: String)? {
        guard let path else { return nil }
        let ns = path as NSString
        guard let match = cellarRegex.firstMatch(in: path, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (ns.substring(with: match.range(at: 1)), ns.substring(with: match.range(at: 2)))
    }

    /// "next · Node project (my-app)" style description of what the process is working on.
    static func detectProject(_ entry: ListeningPort, workingDirectory: String?) -> String? {
        var folder: String?
        var tool: String?
        if let commandLine = entry.commandLine, let range = commandLine.range(of: "/node_modules/") {
            let before = commandLine[..<range.lowerBound]
            folder = String(before[(before.lastIndex(of: " ").map { before.index(after: $0) } ?? before.startIndex)...])
            let after = commandLine[range.upperBound...]
            let segment = after.split(separator: " ").first.map(String.init) ?? ""
            let parts = segment.split(separator: "/").map(String.init)
            if parts.first == ".bin", parts.count > 1 { tool = parts[1] }
            else if parts.first?.hasPrefix("@") == true, parts.count > 1 { tool = parts[0] + "/" + parts[1] }
            else { tool = parts.first }
        }
        let home = NSHomeDirectory()
        if folder == nil, let cwd = workingDirectory, cwd != "/", cwd != home {
            folder = cwd
        }
        guard let folder else { return nil }

        let manifests: [(file: String, kind: String)] = [
            ("package.json", "Node project"), ("pyproject.toml", "Python project"), ("requirements.txt", "Python project"),
            ("Cargo.toml", "Rust project"), ("go.mod", "Go project"), ("Gemfile", "Ruby project"),
            ("Package.swift", "Swift package"), ("composer.json", "PHP project"), ("mix.exs", "Elixir project"),
            ("pom.xml", "Maven project"), ("build.gradle", "Gradle project"), ("build.gradle.kts", "Gradle project"),
            ("docker-compose.yml", "Docker Compose project"), ("compose.yaml", "Docker Compose project"),
        ]
        var kind: String?
        var name = (folder as NSString).lastPathComponent
        for manifest in manifests where FileManager.default.fileExists(atPath: folder + "/" + manifest.file) {
            kind = manifest.kind
            if manifest.file == "package.json",
               let data = FileManager.default.contents(atPath: folder + "/package.json"),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let packageName = json["name"] as? String, !packageName.isEmpty {
                name = packageName
            }
            break
        }
        guard kind != nil || tool != nil else { return nil }
        var pieces: [String] = []
        if let tool { pieces.append(tool) }
        if let kind { pieces.append("\(kind) \(name)") } else { pieces.append(name) }
        return pieces.joined(separator: " · ")
    }
}

struct BundleInfo {
    let displayName: String
    let version: String?
    let copyright: String?
    let identifier: String?
    let executableName: String?

    init?(path: String) {
        guard let bundle = Bundle(path: path), let info = bundle.infoDictionary else { return nil }
        let fallback = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        displayName = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? fallback
        version = info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String
        copyright = (info["NSHumanReadableCopyright"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        identifier = info["CFBundleIdentifier"] as? String
        executableName = info["CFBundleExecutable"] as? String
    }
}

/// Who signed an executable: Apple, the Mac App Store, a Developer ID, or nobody.
enum CodeSignature {
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    static func describe(path: String) -> String? {
        lock.lock()
        if let cached = cache[path] { lock.unlock(); return cached }
        lock.unlock()
        let result = compute(path: path)
        if let result {
            lock.lock(); cache[path] = result; lock.unlock()
        }
        return result
    }

    private static func compute(path: String) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return nil }
        var infoRef: CFDictionary?
        let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
        guard SecCodeCopySigningInformation(code, flags, &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any] else { return nil }
        let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        guard let leaf = certificates.first else {
            return info[kSecCodeInfoIdentifier as String] == nil ? "Unsigned" : "Ad hoc signature"
        }
        let subject = (SecCertificateCopySubjectSummary(leaf) as String?) ?? ""
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        if subject.hasSuffix("Software Signing") { return "Signed by Apple (macOS)" }
        if subject == "Apple Mac OS Application Signing" { return "Signed by Apple (Mac App Store)" }
        if let range = subject.range(of: "Developer ID Application: ") {
            return "Developer ID: \(subject[range.upperBound...])"
        }
        if let range = subject.range(of: "Apple Development: ") {
            return "Development build: \(subject[range.upperBound...])"
        }
        if let team { return "\(subject) (\(team))" }
        return subject.isEmpty ? nil : subject
    }
}
