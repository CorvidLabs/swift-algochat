import Algorand
import AlgoKit
import Foundation

/// Builds and sends message transactions
public enum MessageTransaction {
    /// Minimum payment amount for a message (0.001 ALGO)
    public static let minimumPayment = MicroAlgos(1000)

    /// Note bytes covered by one minimum fee.
    /// Each byte past this adds one ten-thousandth of the minimum fee, rounded up once.
    private static let noteFeeIncludedBytes = 1_024

    /**
     Fee in microAlgos for a note of `noteBytes` at the network minimum fee.

     The first 1,024 bytes cost one minimum fee. Each later byte adds one
     ten-thousandth of that minimum fee, rounded up once. This package signs
     with Ed25519, so the scheme component is one minimum fee. Falcon-1024
     authorization is not implemented; it would add two further minimum fees.
     */
    public static func fee(noteBytes: Int, minFee: UInt64) -> UInt64 {
        let over = noteBytes > noteFeeIncludedBytes ? noteBytes - noteFeeIncludedBytes : 0
        let surcharge = (UInt64(over) * minFee + 9_999) / 10_000
        return minFee + surcharge
    }

    /**
     Creates a payment transaction carrying an encrypted message

     - Parameters:
       - sender: The sending chat account
       - recipient: The recipient's Algorand address
       - envelope: The encrypted message envelope
       - params: Transaction parameters from the network
       - amount: Optional payment amount (default: minimum)
     - Returns: Unsigned PaymentTransaction
     */
    public static func create(
        from sender: ChatAccount,
        to recipient: Address,
        envelope: ChatEnvelope,
        params: TransactionParams,
        amount: MicroAlgos = minimumPayment
    ) throws -> PaymentTransaction {
        try makePayment(
            sender: sender.address,
            receiver: recipient,
            amount: amount,
            note: envelope.encode(),
            params: params
        )
    }

    /// Creates and signs a message transaction
    public static func createSigned(
        from sender: ChatAccount,
        to recipient: Address,
        envelope: ChatEnvelope,
        params: TransactionParams,
        amount: MicroAlgos = minimumPayment
    ) throws -> SignedTransaction {
        let tx = try create(
            from: sender,
            to: recipient,
            envelope: envelope,
            params: params,
            amount: amount
        )
        return try SignedTransaction.sign(tx, with: sender.account)
    }

    /**
     Creates a signed key-publish transaction with an Ed25519 signature

     The note contains the envelope followed by a 64-byte Ed25519 signature
     over the sender's X25519 encryption key. This proves the encryption key
     was published by the holder of the Algorand account.

     - Parameters:
       - sender: The sending chat account
       - envelope: The encrypted key-publish envelope
       - keySignature: Ed25519 signature over the sender's encryption public key (64 bytes)
       - params: Transaction parameters from the network
     - Returns: Signed transaction
     */
    public static func createSignedKeyPublish(
        from sender: ChatAccount,
        envelope: ChatEnvelope,
        keySignature: Data,
        params: TransactionParams
    ) throws -> SignedTransaction {
        var noteData = envelope.encode()
        noteData.append(keySignature)

        let tx = try makePayment(
            sender: sender.address,
            receiver: sender.address,
            amount: MicroAlgos(0),
            note: noteData,
            params: params
        )

        return try SignedTransaction.sign(tx, with: sender.account)
    }

    // MARK: - PSK Envelope Overloads

    /**
     Creates a payment transaction carrying a PSK-encrypted message

     - Parameters:
       - sender: The sending chat account
       - recipient: The recipient's Algorand address
       - envelope: The PSK encrypted message envelope
       - params: Transaction parameters from the network
       - amount: Optional payment amount (default: minimum)
     - Returns: Unsigned PaymentTransaction
     */
    public static func create(
        from sender: ChatAccount,
        to recipient: Address,
        envelope: PSKEnvelope,
        params: TransactionParams,
        amount: MicroAlgos = minimumPayment
    ) throws -> PaymentTransaction {
        try makePayment(
            sender: sender.address,
            receiver: recipient,
            amount: amount,
            note: envelope.encode(),
            params: params
        )
    }

    // MARK: - Private Methods

    /// Builds a payment whose fee is the consensus note fee for `note`.
    private static func makePayment(
        sender: Address,
        receiver: Address,
        amount: MicroAlgos,
        note: Data,
        params: TransactionParams
    ) throws -> PaymentTransaction {
        guard note.count <= ChatEnvelope.maxNoteSize else {
            throw ChatError.messageTooLarge(maxSize: ChatEnvelope.maxNoteSize)
        }

        let noteFee = MicroAlgos(fee(noteBytes: note.count, minFee: params.minFee))
        return try PaymentTransactionBuilder()
            .sender(sender)
            .receiver(receiver)
            .amount(amount)
            .fee(noteFee)
            .note(note)
            .params(params)
            .build()
    }

    /// Creates and signs a PSK message transaction
    public static func createSigned(
        from sender: ChatAccount,
        to recipient: Address,
        envelope: PSKEnvelope,
        params: TransactionParams,
        amount: MicroAlgos = minimumPayment
    ) throws -> SignedTransaction {
        let tx = try create(
            from: sender,
            to: recipient,
            envelope: envelope,
            params: params,
            amount: amount
        )
        return try SignedTransaction.sign(tx, with: sender.account)
    }
}
