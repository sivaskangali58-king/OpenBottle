import Foundation

public enum EngineLocator {
    public static let bundledGPTK = "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64"
    public static func executable(for engine: WineEngine, customWine: String? = nil) -> URL? {
        switch engine {
        case .wineStaging: return WineLocator.find(custom: customWine)
        case .gptk:
            guard WineLocator.isValidExecutable(bundledGPTK) else { return nil }
            return URL(fileURLWithPath: bundledGPTK)
        }
    }
}
