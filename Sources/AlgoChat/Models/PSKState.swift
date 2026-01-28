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

    /// Validates and records a received counter value
    ///
    /// - Parameter counter: The received ratchet counter
    /// - Throws: `ChatError.pskCounterReplay` if the counter was already seen
    /// - Throws: `ChatError.pskCounterOutOfRange` if the counter is outside the acceptance window
    public mutating func validateAndRecordReceive(_ counter: UInt32) throws {
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

        // Record and update
        seenCounters.insert(counter)
        if counter > peerLastCounter {
            peerLastCounter = counter
        }

        // Prune old seen counters outside the window
        pruneSeenCounters()
    }

    /// Advances the send counter and returns the current value
    ///
    /// - Returns: The counter value to use for the next send
    public mutating func advanceSendCounter() -> UInt32 {
        let current = sendCounter
        sendCounter += 1
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
