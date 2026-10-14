import Foundation

public struct InstalledProgram: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    /// Relative to the bottle prefix. Never a free-form absolute path.
    public var relativeExecutablePath: String
    public init(id: UUID = UUID(), title: String, relativeExecutablePath: String) {
        self.id = id; self.title = title; self.relativeExecutablePath = relativeExecutablePath
    }
}

public enum WineEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case wineStaging = "wineStaging"
    case gptk = "gptk"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .wineStaging: return "Wine Staging"
        case .gptk: return "Game Porting Toolkit (GPTK)"
        }
    }
}

public struct GameShortcut: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var relativeExecutablePath: String
    public var showMetalHUD: Bool
    /// Steam app id when known. Used for artwork resolution and future integrations.
    public var steamAppID: Int?
    /// Relative path inside the bottle prefix to a locally cached Steam artwork image.
    public var artworkRelativePath: String?
    public init(id: UUID = UUID(), title: String, relativeExecutablePath: String,
                showMetalHUD: Bool = false, steamAppID: Int? = nil, artworkRelativePath: String? = nil) {
        self.id = id; self.title = title; self.relativeExecutablePath = relativeExecutablePath
        self.showMetalHUD = showMetalHUD
        self.steamAppID = steamAppID
        self.artworkRelativePath = artworkRelativePath
    }
}

public enum BottleProfile: String, Codable, CaseIterable, Sendable {
    case standard, steam
}

public struct Bottle: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let createdAt: Date
    public var programs: [InstalledProgram]
    public var engine: WineEngine
    /// A Steam bottle always uses Wine Staging for Steam, and GPTK for game processes.
    public var profile: BottleProfile
    public var gameEngine: WineEngine?
    public var effectiveGameEngine: WineEngine { gameEngine ?? engine }
    public var games: [GameShortcut]
    /// Linked GPTK test prefix, held directly under OpenBottle support root. Never delete its contents.
    public var linkedPrefixName: String?
    public var isLinked: Bool { linkedPrefixName != nil }

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(),
                programs: [InstalledProgram] = [], engine: WineEngine = .wineStaging,
                games: [GameShortcut] = [], linkedPrefixName: String? = nil,
                profile: BottleProfile = .standard, gameEngine: WineEngine? = nil) {
        self.id = id; self.name = name; self.createdAt = createdAt; self.programs = programs
        self.engine = engine; self.games = games; self.linkedPrefixName = linkedPrefixName
        self.profile = profile; self.gameEngine = gameEngine
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, programs, engine, games, linkedPrefixName, profile, gameEngine
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        programs = try c.decodeIfPresent([InstalledProgram].self, forKey: .programs) ?? []
        engine = try c.decodeIfPresent(WineEngine.self, forKey: .engine) ?? .wineStaging
        profile = try c.decodeIfPresent(BottleProfile.self, forKey: .profile) ?? .standard
        gameEngine = try c.decodeIfPresent(WineEngine.self, forKey: .gameEngine)
        games = try c.decodeIfPresent([GameShortcut].self, forKey: .games) ?? []
        linkedPrefixName = try c.decodeIfPresent(String.self, forKey: .linkedPrefixName)
    }
}

public enum BottleError: LocalizedError {
    case emptyName, invalidProgramPath, missingExecutable, missingWine, operationInProgress
    case missingLinkedPrefix, invalidLinkedPrefix
    public var errorDescription: String? {
        switch self {
        case .emptyName: return "Şişe adı boş olamaz."
        case .invalidProgramPath: return "EXE dosyası bu şişenin klasöründe olmalıdır."
        case .missingExecutable: return "Çalıştırılacak dosya bulunamadı."
        case .missingWine: return "Seçili Wine/GPTK motoru bulunamadı. Ayarları kontrol et."
        case .operationInProgress: return "Önce mevcut işlemin bitmesini bekle."
        case .missingLinkedPrefix: return "Bağlı GPTK test ortamı artık bulunamıyor."
        case .invalidLinkedPrefix: return "Bağlanacak ortam OpenBottle klasöründe geçerli bir Wine prefix olmalı."
        }
    }
}
