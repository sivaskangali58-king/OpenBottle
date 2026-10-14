import Foundation
import XCTest
@testable import OpenBottleCore

final class SteamLaunchGateTests: XCTestCase {
    func testDoubleLaunchOfSameSteamBottleBlocked() {
        var gate = SteamLaunchGate()
        let id = UUID()
        XCTAssertTrue(gate.beginUserLaunch(for: id))
        XCTAssertFalse(gate.beginUserLaunch(for: id))
        XCTAssertTrue(gate.isActive(id))
        gate.finish(for: id)
        XCTAssertFalse(gate.isActive(id))
    }
    func testLaunchGateIsPerBottle() {
        var gate = SteamLaunchGate()
        XCTAssertTrue(gate.beginUserLaunch(for: UUID()))
        XCTAssertTrue(gate.beginUserLaunch(for: UUID()))
    }
    func testExitDoesNotTriggerAutoRestart() {
        XCTAssertFalse(SteamLaunchGate.shouldRelaunchAfterExit(exitCode: 0))
        XCTAssertFalse(SteamLaunchGate.shouldRelaunchAfterExit(exitCode: 1))
        XCTAssertFalse(SteamLaunchGate.shouldRelaunchAfterExit(exitCode: -9))
    }
}
