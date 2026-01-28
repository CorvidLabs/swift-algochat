import Foundation

/// Ratchet counter state for PSK messaging with a specific contact
public struct PSKState: Sendable, Codable {
    // MARK: - Constants

    /// Number of positions per session
    public static let sessionSize: UInt32 = 100

    /// Window of counter values to accept around peerLastCounter
    public static let counterWindow: UInt32 = 200

    // MARK: - Properties

    /// The next counter value to use when sending
    public var sendCounter: UInt32

    /// The highest counter value received from the peer
    public var peerLastCounter: UInt32

    /// Set of counter values we have seen (for replay detection)
    public var seenCounters: Set<UInt32>

    // MARK: - Initialization

    /// Creates a new PSK state with default values
    public init() {
        self.sendCounter = 0
        self.peerLastCounter = 0
        self.seenCounters = []
    }

    /// Creates a PSK state with specific values
    public init(sendCounter: UInt32, peerLastCounter: UInt32, seenCounters: Set<UInt32>) {
        self.sendCounter = sendCounter
        self.peerLastCounter = peerLastCounter
        self.seenCounters = seenCounters
    }

    // MARK: - Counter Operations

    /**
     Validates a received counter value without recording it

     Call this before attempting decryption. If decryption succeeds,
     call `recordReceive(_:)` to commit the counter.

     - Parameter counter: The received ratchet counter
     - Throws: `ChatError.pskCounterReplay` if the counter was already seen
     - Throws: `ChatError.pskCounterOutOfRange` if the counter is outside the acceptance window
     */
    public func validateCounter(_ counter: UInt32) throws {
        // Check for replay
        if seenCounters.contains(counter) {
            throw ChatError.pskCounterReplay
        }

        // Check counter window: accept if counter is within window of peerLastCounter
        // For the first message (peerLastCounter == 0), accept any counter within the window
        let lowerBound: UInt32
        if peerLastCounter > Self.counterWindow {
            lowerBound = peerLastCounter - Self.counterWindow
        } else {
            lowerBound = 0
        }
        let upperBound = peerLastCounter + Self.counterWindow

        guard counter >= lowerBound && counter <= upperBound else {
            throw ChatError.pskCounterOutOfRange
        }
    }

    /**
     Records a successfully decrypted counter value

     Call this only after decryption succeeds to avoid burning
     counters on failed decryptions.

     - Parameter counter: The counter value to record
     */
    public mutating func recordReceive(_ counter: UInt32) {
        seenCounters.insert(counter)
        if counter > peerLastCounter {
            peerLastCounter = counter
        }
        pruneSeenCounters()
    }

    /**
     Validates and records a received counter value

     Convenience that combines `validateCounter` and `recordReceive`.
     Use the two-phase API when decryption may fail between validation and recording.

     - Parameter counter: The received ratchet counter
     - Throws: `ChatError.pskCounterReplay` if the counter was already seen
     - Throws: `ChatError.pskCounterOutOfRange` if the counter is outside the acceptance window
     */
    public mutating func validateAndRecordReceive(_ counter: UInt32) throws {
        try validateCounter(counter)
        recordReceive(counter)
    }

    /**
     Advances the send counter and returns the current value

     - Returns: The counter value to use for the next send
     */
    public mutating func advanceSendCounter() -> UInt32 {
        let current = sendCounter
        sendCounter &+= 1
        return current
    }

    // MARK: - Private

    /// Removes seen counters that are below the acceptance window
    private mutating func pruneSeenCounters() {
        guard peerLastCounter > Self.counterWindow else { return }
        let cutoff = peerLastCounter - Self.counterWindow
        seenCounters = seenCounters.filter { $0 >= cutoff }
    }
}
