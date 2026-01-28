import Foundation
import Testing
@testable import AlgoChat

@Suite("PSK State Tests")
struct PSKStateTests {

    // MARK: - Counter Window Validation (Protocol Test Case 4.4)

    @Test("Counter 51 passes when peerLastCounter=50")
    func testCounterAhead() throws {
        var state = PSKState(sendCounter: 0, peerLastCounter: 50, seenCounters: [50])
        try state.validateAndRecordReceive(51)
        #expect(state.peerLastCounter == 51)
        #expect(state.seenCounters.contains(51))
    }

    @Test("Counter 0 passes when peerLastCounter=50 (within window)")
    func testCounterBehindInWindow() throws {
        var state = PSKState(sendCounter: 0, peerLastCounter: 50, seenCounters: [50])
        try state.validateAndRecordReceive(0)
        #expect(state.peerLastCounter == 50) // Not advanced
        #expect(state.seenCounters.contains(0))
    }

    @Test("Counter 249 passes when peerLastCounter=50 (within window)")
    func testCounterFarAheadInWindow() throws {
        var state = PSKState(sendCounter: 0, peerLastCounter: 50, seenCounters: [50])
        try state.validateAndRecordReceive(249)
        #expect(state.peerLastCounter == 249) // Advanced
    }

    @Test("Counter 251 fails when peerLastCounter=50 (outside window)")
    func testCounterOutOfRange() throws {
        var state = PSKState(sendCounter: 0, peerLastCounter: 50, seenCounters: [50])
        #expect(throws: ChatError.self) {
            try state.validateAndRecordReceive(251)
        }
    }

    // MARK: - Replay Detection

    @Test("Duplicate counter is rejected")
    func testReplayDetection() throws {
        var state = PSKState(sendCounter: 0, peerLastCounter: 50, seenCounters: [50])
        #expect(throws: ChatError.self) {
            try state.validateAndRecordReceive(50)
        }
    }

    @Test("Counter is recorded after successful receive")
    func testCounterRecorded() throws {
        var state = PSKState(sendCounter: 0, peerLastCounter: 0, seenCounters: [])
        try state.validateAndRecordReceive(5)
        #expect(state.seenCounters.contains(5))

        // Second time should fail (replay)
        #expect(throws: ChatError.self) {
            try state.validateAndRecordReceive(5)
        }
    }

    // MARK: - Send Counter

    @Test("advanceSendCounter increments correctly")
    func testAdvanceSendCounter() {
        var state = PSKState()
        #expect(state.advanceSendCounter() == 0)
        #expect(state.advanceSendCounter() == 1)
        #expect(state.advanceSendCounter() == 2)
        #expect(state.sendCounter == 3)
    }

    @Test("Initial send counter is 0")
    func testInitialSendCounter() {
        let state = PSKState()
        #expect(state.sendCounter == 0)
    }

    // MARK: - Pruning

    @Test("seenCounters are pruned below window")
    func testSeenCountersPruning() throws {
        var state = PSKState(sendCounter: 0, peerLastCounter: 0, seenCounters: [])

        // Record a bunch of early counters
        for i: UInt32 in 0..<10 {
            try state.validateAndRecordReceive(i)
        }
        #expect(state.seenCounters.count == 10)

        // Incrementally advance peerLastCounter to reach 300
        // Can't jump directly from 9 to 300 (exceeds window of 200)
        try state.validateAndRecordReceive(150)
        try state.validateAndRecordReceive(300)
        #expect(state.peerLastCounter == 300)

        // Old counters below (300 - 200 = 100) should be pruned
        for i: UInt32 in 0..<10 {
            #expect(!state.seenCounters.contains(i), "Counter \(i) should have been pruned")
        }
        #expect(state.seenCounters.contains(300))
    }

    // MARK: - Edge Cases

    @Test("First message with counter 0 is accepted")
    func testFirstMessage() throws {
        var state = PSKState()
        try state.validateAndRecordReceive(0)
        #expect(state.peerLastCounter == 0)
        #expect(state.seenCounters.contains(0))
    }

    @Test("Out-of-order within window is accepted")
    func testOutOfOrder() throws {
        var state = PSKState()
        try state.validateAndRecordReceive(5)
        try state.validateAndRecordReceive(3)
        try state.validateAndRecordReceive(7)
        try state.validateAndRecordReceive(1)

        #expect(state.peerLastCounter == 7)
        #expect(state.seenCounters.count == 4)
    }

    // MARK: - Constants

    @Test("Session size is 100")
    func testSessionSize() {
        #expect(PSKState.sessionSize == 100)
    }

    @Test("Counter window is 200")
    func testCounterWindow() {
        #expect(PSKState.counterWindow == 200)
    }
}
