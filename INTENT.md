# swift-algochat

swift-algochat lets a Swift app, or a person at a terminal, send private messages to anyone with an Algorand address, with the chain as the only thing in the middle. It exists because chat usually means trusting whoever runs the servers with your identity, your contacts and the delivery of every word, while a public ledger can carry an encrypted message just as well without anyone owning the pipe. The account a person already has should be their whole identity, the cryptography should be the well-reviewed kind rather than something invented here, and a message should read the same whether it was written in Swift, TypeScript, Rust, Python or Kotlin.

To a developer it should feel like an ordinary async Swift client, and to the person using an app built on it, like sending a text. It should also be plain about what a public chain always reveals, who talked to whom, when, and at what cost, and about what it cannot promise, so nobody mistakes it for more protection than it gives.

## Features

<!-- hi:index -->
- [key](hi/key.md): KEY (11 criteria)
- [message](hi/message.md): MESSAGE (15 criteria)
- [psk](hi/psk.md): PSK (10 criteria)
<!-- /hi:index -->
