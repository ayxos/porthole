import Foundation

/// Asks GitHub whether a newer release exists. One unauthenticated request to
/// the public releases API; nothing is downloaded or installed.
enum UpdateChecker {
    struct Release: Equatable {
        let version: String
        let url: URL
    }

    static let latestReleaseURL = URL(string: "https://api.github.com/repos/ayxos/porthole/releases/latest")!

    static func latestRelease() async -> Release? {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parseRelease(data)
    }

    static func parseRelease(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, url: page)
    }

    /// Numeric comparison of dotted versions: "1.10.0" is newer than "1.9.2", "1.0" equals "1.0.0".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
