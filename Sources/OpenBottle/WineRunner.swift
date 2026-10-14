#if os(macOS)
import Foundation
import OpenBottleCore

/// Runs Wine without a shell; paths and arguments are passed directly to Process.
@MainActor
final class WineRunner {
    private var process: Process?

    var isRunning: Bool { process?.isRunning == true }

    func run(wine: URL, prefix: URL, arguments: [String],
             workingDirectory: URL? = nil, extraEnvironment: [String: String] = [:],
             output: @escaping @MainActor (String) -> Void,
             completion: @escaping @MainActor (Int32) -> Void) throws {
        guard process == nil else { throw BottleError.operationInProgress }
        let task = Process()
        task.executableURL = wine
        task.arguments = arguments
        task.currentDirectoryURL = workingDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["WINEPREFIX"] = prefix.path
        environment["WINEDEBUG"] = "-all"
        for (key, value) in extraEnvironment { environment[key] = value }
        // Wine may launch helper binaries from its own directory.
        let helperPath = wine.deletingLastPathComponent().path
        environment["PATH"] = "\(helperPath):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        task.environment = environment
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        process = task

        // Read continuously on a background queue to avoid blocking the SwiftUI thread.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let handle = pipe.fileHandleForReading
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    Task { @MainActor in output(text) }
                }
            }
            task.waitUntilExit()
            let exitCode = task.terminationStatus
            Task { @MainActor in
                self?.process = nil
                completion(exitCode)
            }
        }
    }
}
#endif
