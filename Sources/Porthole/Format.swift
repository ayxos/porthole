import Foundation

/// Compact, locale-independent number formatting for the dense row layout.
enum Format {
    static func memory(_ bytes: UInt64) -> String {
        let megabytes = Double(bytes) / 1_048_576
        if megabytes < 1 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        if megabytes < 10 { return String(format: "%.1f MB", megabytes) }
        if megabytes < 1024 { return String(format: "%.0f MB", megabytes) }
        return String(format: "%.1f GB", megabytes / 1024)
    }

    static func cpuPercent(_ percent: Double) -> String {
        percent >= 10 ? String(format: "%.0f%%", percent) : String(format: "%.1f%%", percent)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return String(format: "%.1f s", seconds) }
        if seconds < 3600 { return String(format: "%.0f min", seconds / 60) }
        return String(format: "%.1f h", seconds / 3600)
    }
}
