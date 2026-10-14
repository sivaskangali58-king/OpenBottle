import Foundation

/// OpenBottle never retries Steam automatically. Only a fresh user action may
/// start a client, and duplicate clicks cannot start a second process.
public struct SteamLaunchGate {
    private var activeBottles: Set<UUID> = []
    public init() {}
    @discardableResult
    public mutating func beginUserLaunch(for bottleID: UUID) -> Bool {
        activeBottles.insert(bottleID).inserted
    }
    public mutating func finish(for bottleID: UUID) {
        activeBottles.remove(bottleID)
    }
    public func isActive(_ bottleID: UUID) -> Bool { activeBottles.contains(bottleID) }
    /// A crash or normal termination is never a reason for automatic relaunch.
    public static func shouldRelaunchAfterExit(exitCode: Int32) -> Bool { false }
}
