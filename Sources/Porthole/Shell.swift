import Foundation

enum Shell {
    struct Output {
        let status: Int32
        let stdout: String
    }

    /// Runs an executable to completion and captures stdout. stderr is discarded.
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Output(status: process.terminationStatus, stdout: String(decoding: data, as: UTF8.self))
    }
}
