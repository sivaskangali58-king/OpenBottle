import XCTest
@testable import OpenBottleCore

final class SteamRepairStatusTests: XCTestCase {
    func testReadyWithCompiler() {
        let state = SteamRepairCheck.parse("state=ready\ncompiler=ready\nsteam=installed\n")
        XCTAssertEqual(state.phase, .ready)
        XCTAssertTrue(state.hasCompiler)
        XCTAssertTrue(state.canApply)
        XCTAssertFalse(state.canRestore)
    }
    func testActiveCanRestore() {
        let state = SteamRepairCheck.parse("state=active\ncompiler=missing\nsteam=installed")
        XCTAssertEqual(state.phase, .active)
        XCTAssertTrue(state.canRestore)
        XCTAssertTrue(state.canApply)
    }
    func testSteamUpdatedNeedsRepair() {
        let state = SteamRepairCheck.parse("state=changed\ncompiler=ready\nsteam=installed")
        XCTAssertEqual(state.phase, .changed)
        XCTAssertTrue(state.canApply)
    }
    func testMissingSteamCannotFix() {
        let state = SteamRepairCheck.parse("state=unavailable\ncompiler=ready\nsteam=missing")
        XCTAssertFalse(state.canApply)
    }
    func testDamagedCannotPatchBlindly() {
        let state = SteamRepairCheck.parse("state=damaged\ncompiler=ready\nsteam=installed")
        XCTAssertFalse(state.canApply)
        XCTAssertFalse(state.canRestore)
    }
    func testMalformedProbeIsConservative() {
        let state = SteamRepairCheck.parse("garbled output\n")
        XCTAssertEqual(state.phase, .unknown)
        XCTAssertFalse(state.canApply)
    }
    func testConflictDisablesFix() {
        let state = SteamRepairCheck.parse("state=conflict\ncompiler=ready\nsteam=installed")
        XCTAssertFalse(state.canApply)
    }
}
