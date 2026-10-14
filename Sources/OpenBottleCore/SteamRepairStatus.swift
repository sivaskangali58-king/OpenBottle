import Foundation

/// A read-only interpretation of the bundled steam-ui-fix.sh probe output.
/// The probe never patches the Steam installation.
public enum SteamRepairPhase: String, Equatable {
    case unavailable, waiting, ready, active, changed, conflict, damaged, unknown
}

public struct SteamRepairCheck: Equatable {
    public let phase: SteamRepairPhase
    public let hasCompiler: Bool
    public let hasSteam: Bool

    public init(phase: SteamRepairPhase, hasCompiler: Bool, hasSteam: Bool) {
        self.phase = phase
        self.hasCompiler = hasCompiler
        self.hasSteam = hasSteam
    }

    public static func parse(_ output: String) -> SteamRepairCheck {
        var fields: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let halves = line.split(separator: "=", maxSplits: 1).map(String.init)
            if halves.count == 2 { fields[halves[0]] = halves[1] }
        }
        return SteamRepairCheck(
            phase: SteamRepairPhase(rawValue: fields["state"] ?? "") ?? .unknown,
            hasCompiler: fields["compiler"] == "ready",
            hasSteam: fields["steam"] == "installed"
        )
    }

    public var canApply: Bool {
        hasSteam && (phase == .ready || phase == .changed || phase == .active)
    }
    public var canRestore: Bool {
        phase == .active || phase == .changed
    }
}
