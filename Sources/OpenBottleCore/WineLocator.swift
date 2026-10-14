import Foundation

public enum WineLocator {
    /// Finder-launched apps often have a limited PATH; search known Wine app bundles too.
    public static func candidates(custom: String? = nil, environmentPath: String? = ProcessInfo.processInfo.environment["PATH"],
                                  applications: String = "/Applications") -> [String] {
        var locations: [String] = []
        if let custom, !custom.isEmpty { locations.append(custom) }
        if let environmentPath {
            for dir in environmentPath.split(separator: ":") {
                locations.append(String(dir) + "/wine")
                locations.append(String(dir) + "/wine64")
            }
        }
        locations += ["/opt/homebrew/bin/wine", "/opt/homebrew/bin/wine64", "/usr/local/bin/wine", "/usr/local/bin/wine64"]
        for name in ["Wine Staging", "Wine Stable", "Wine Devel", "Wine"] {
            let app = "\(applications)/\(name).app/Contents"
            locations.append(app + "/Resources/wine/bin/wine")
            locations.append(app + "/MacOS/wine")
        }
        return locations
    }

    public static func isValidExecutable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    public static func find(custom: String? = nil) -> URL? {
        for path in candidates(custom: custom) where isValidExecutable(path) {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return nil
    }
}
