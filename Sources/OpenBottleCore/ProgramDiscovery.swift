import Foundation

/// A Windows executable discovered in a bottle; paths are relative to that bottle's prefix.
public struct ProgramCandidate: Identifiable, Hashable, Sendable {
    public var id: String { relativeExecutablePath }
    public let title: String
    public let relativeExecutablePath: String
    public let folder: String

    public init(title: String, relativeExecutablePath: String, folder: String) {
        self.title = title
        self.relativeExecutablePath = relativeExecutablePath
        self.folder = folder
    }
}

/// Looks only in common user-application folders, deliberately skipping Windows system files.
public enum ProgramDiscovery {
    public static func find(in prefix: URL,
                            excluding registeredPaths: Set<String> = [],
                            maxResults: Int = 250) -> [ProgramCandidate] {
        guard maxResults > 0 else { return [] }
        let fm = FileManager.default
        let base = prefix.resolvingSymlinksInPath().standardizedFileURL
        let driveC = base.appendingPathComponent("drive_c", isDirectory: true)
        let roots = ["Program Files", "Program Files (x86)", "Games", "GOG Games", "SteamLibrary"]
            .map { driveC.appendingPathComponent($0, isDirectory: true) }
        var scanRoots = roots
        let users = driveC.appendingPathComponent("users", isDirectory: true)
        if let homeDirs = try? fm.contentsOfDirectory(at: users, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for home in homeDirs {
                let localPrograms = home.appendingPathComponent("AppData/Local/Programs", isDirectory: true)
                scanRoots.append(localPrograms)
            }
        }

        var found: [ProgramCandidate] = []
        var seen = Set<String>()
        var examined = 0
        let maxVisited = 30_000
        let registered = Set(registeredPaths.map { $0.lowercased() })
        for root in scanRoots {
            guard fm.fileExists(atPath: root.path) else { continue }
            guard let enumerator = fm.enumerator(at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            while let url = enumerator.nextObject() as? URL {
                examined += 1
                if examined > maxVisited || found.count >= maxResults { break }
                let props = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
                if props?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if props?.isDirectory == true { continue }
                guard props?.isRegularFile == true,
                      url.pathExtension.lowercased() == "exe",
                      !excludedExecutable(url.lastPathComponent) else { continue }

                let resolved = url.resolvingSymlinksInPath().standardizedFileURL
                guard resolved.path.hasPrefix(base.path + "/") else { continue }
                let relativePath = String(resolved.path.dropFirst(base.path.count + 1))
                let key = relativePath.lowercased()
                guard !registered.contains(key), seen.insert(key).inserted else { continue }
                let name = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                found.append(ProgramCandidate(title: name,
                    relativeExecutablePath: relativePath,
                    folder: url.deletingLastPathComponent().lastPathComponent))
            }
            if examined > maxVisited || found.count >= maxResults { break }
        }
        return found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static func excludedExecutable(_ filename: String) -> Bool {
        let n = filename.lowercased()
        let base = String(n.dropLast(4))
        let exact: Set<String> = ["uninstall", "uninstaller", "setup", "installer", "update", "updater", "repair", "crashreporter", "crashhandler", "dxsetup", "vcredist_x64", "vcredist_x86", "vc_redist.x64", "vc_redist.x86", "eula", "unins000", "unins001"]
        return exact.contains(base) || base.hasPrefix("unins") || base.hasPrefix("uninstall") || base.hasPrefix("crashpad_handler")
    }
}
