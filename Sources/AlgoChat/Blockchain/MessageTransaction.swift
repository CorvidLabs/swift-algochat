import Algorand
import AlgoKit
import Foundation

/// Builds and sends message transactions
public enum MessageTransaction {
    /// Minimum payment amount for a message (0.001 ALGO)
    public static let minimumPayment = MicroAlgos(1000)

    /// Creates a payment transaction carrying an encrypted message
    ///
    /// - Parameters:
    ///   - sender: The sending chat account
    ///   - recipient: The recipient's Algorand address
    ///   - envelope: The encrypted message envelope
    ///   - params: Transaction parameters from the network
    ///   - amount: Optional payment amount (default: minimum)
    /// - Returns: Unsigned PaymentTransaction
    public static func create(
        from sender: ChatAccount,
        to recipient: Address,
        envelope: ChatEnvelope,
        params: TransactionParams,
        amount: MicroAlgos = minimumPayment
    ) throws -> PaymentTransaction {
        let noteData = envelope.encode()

        guard noteData.count <= 1024 else {
            throw ChatError.messageTooLarge(maxSize: 1024)
        }

        return try PaymentTransactionBuilder()
            .sender(sender.address)
            .receiver(recipient)
            .amount(amount)
            .note(noteData)
            .params(params)
            .build()
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
}
