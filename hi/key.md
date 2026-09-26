---
hi: 1
families: [KEY]
owner: leif
---

# Keys and identity

## Intent

My Algorand account should be my whole identity. I should not have to create, back up or hand out a second key to be reachable: the encryption key comes from the account, the same way on every device and in every implementation, and other people can find it on the chain. Finding a key on a public chain invites someone to slip in their own, so I want to know when a key has been proven to belong to an address and when it has only been seen, and I want the private key on my device kept as safe as the platform allows.

## Criteria

- **KEY-1**  My encryption key comes from my Algorand account, so the account is the only thing I have to back up.
  - **KEY-1.a**  The same account gives the same encryption key on every device and in every AlgoChat implementation.
- **KEY-2**  I can make myself reachable before anyone has messaged me by publishing my key once.
- **KEY-3**  Someone can find my key on the chain without having to ask me for it.
  - **KEY-3.a**  A key I published myself is shown as proven to belong to my address.
  - **KEY-3.b**  A key that was only seen in passing is shown as unverified, never as trusted.
  - **KEY-3.c**  I can limit how much history is searched when looking for a key.
- **KEY-4**  I can compare a short fingerprint of a key with someone out of band.
- **KEY-5**  On Apple devices my stored encryption key can sit behind Face ID, Touch ID or Optic ID.
- **KEY-6**  Everywhere else my stored encryption key is protected by a password I choose.
- **KEY-7**  A wrong password or a damaged key file fails with an error and never hands back a wrong key.
