# Security

## Cryptographic Guarantees

AlgoChat provides the following security properties:

### Confidentiality
- Messages encrypted with **ChaCha20-Poly1305** authenticated encryption
- Key agreement via **X25519** elliptic curve Diffie-Hellman
- Only the sender and intended recipient can decrypt messages

### Forward Secrecy
- **Per-message ephemeral keys** ensure that compromising a long-term key does not reveal past messages
- Each message uses a fresh X25519 keypair for key agreement
- Ephemeral private keys are discarded immediately after encryption

### Integrity
- **Poly1305 MAC** authenticates all ciphertext
- Tampered messages fail decryption with authentication error
- Blockchain immutability prevents post-delivery modification

### Authenticity
- Sender identity verified via Algorand transaction signature
- Sender's static public key included in envelope for key discovery
- Transaction ID provides non-repudiable proof of message origin

## Threat Model

### What AlgoChat Protects Against

| Threat | Protection |
|--------|------------|
| Eavesdropping | End-to-end encryption; only endpoints can decrypt |
| Message tampering | Authenticated encryption fails on modification |
| Replay attacks | Unique nonce per message; blockchain prevents duplicates |
| Key compromise (past messages) | Forward secrecy via ephemeral keys |
| Man-in-the-middle | Key discovery from blockchain transaction history |

### What AlgoChat Does NOT Protect Against

| Threat | Limitation |
|--------|------------|
| Endpoint compromise | If device is compromised, keys may be extracted |
| Traffic analysis | Message timing and size visible on blockchain |
| Recipient key compromise | Compromised recipient key reveals all messages TO that recipient |
| Message deletion | Blockchain messages are permanent and immutable |
| Metadata privacy | Sender/recipient addresses visible on-chain |

## Key Management

### Key Derivation
- Encryption keys derived from Algorand account via **HKDF-SHA256**
- Domain separation: `"AlgoChatV4"` prevents cross-protocol attacks
- Salt derived from account address for deterministic key generation

### Key Storage

**Apple Platforms (macOS, iOS, visionOS):**
- Keys stored in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Biometric protection via `SecAccessControlCreateFlags.userPresence`
- Keys never leave the Secure Enclave on supported devices

**Linux/Other Platforms:**
- Keys encrypted with **AES-256-GCM**
- Password-based key derivation via **PBKDF2** (100,000 iterations)
- Storage file permissions set to `0600` (owner read/write only)

## Implementation Details

### Cryptographic Primitives
| Primitive | Algorithm | Library |
|-----------|-----------|---------|
| Key Agreement | X25519 | swift-crypto |
| Symmetric Encryption | ChaCha20-Poly1305 | swift-crypto |
| Key Derivation | HKDF-SHA256 | swift-crypto |
| Password KDF | PBKDF2-SHA256 | swift-crypto |
| Random Generation | SecRandomCopyBytes / /dev/urandom | Platform |

### Envelope Format (v4)
```
[version: 1][protocol: 1][sender_pubkey: 32][ephemeral_pubkey: 32][nonce: 12][encrypted_sender_key: 48][ciphertext: variable]
```

- **Total overhead:** 142 bytes (126-byte header + 16-byte auth tag)
- **Maximum plaintext:** 882 bytes per message

## Security Assumptions

1. **Algorand blockchain is available and honest** - Messages rely on blockchain for delivery and ordering
2. **swift-crypto is correctly implemented** - We use Apple's audited cryptographic library
3. **Platform random number generator is secure** - SecRandomCopyBytes on Apple, /dev/urandom on Linux
4. **User protects their device** - Endpoint security is user's responsibility

## Reporting Vulnerabilities

If you discover a security vulnerability, please report it privately:

1. **Do not** open a public GitHub issue
2. Email security concerns to the repository maintainers
3. Include steps to reproduce and potential impact
4. Allow reasonable time for a fix before public disclosure

## Audit Status

This library has not undergone a formal security audit. While the cryptographic implementation follows best practices and uses well-audited primitives from swift-crypto, users requiring high-assurance security should commission an independent audit.
