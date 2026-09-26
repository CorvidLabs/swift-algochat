---
hi: 1
families: [MESSAGE]
owner: leif
---

# Talking over the chain

## Intent

I want to message anyone who has an Algorand address, privately, with nothing between us but the chain: no server that can read my messages, lose them or decide not to deliver them, and nothing to sign up for beyond the account I already have. To a Swift developer it should feel like an ordinary async chat client, with conversations, send and refresh, and no blockchain plumbing to learn first. Because every message is permanent and its outline is public, it should be honest about what the chain gives away, and it should never tell me a message went out when it did not.

## Criteria

- **MESSAGE-1**  I can send a text message to any Algorand address, and only that person and I can read it.
  - **MESSAGE-1.a**  Anyone watching the chain can see that we talked, when, and roughly how much, but never what was said.
  - **MESSAGE-1.b**  I can read my own sent messages again from the chain, on any device that holds my account.
- **MESSAGE-2**  A message too big for one transaction is refused before anything is paid for.
- **MESSAGE-3**  I choose whether sending returns as soon as the message is submitted, once it is confirmed, or once it can be read back.
  - **MESSAGE-3.a**  Even when I do not wait, I get the message back straight away to show in my own view.
- **MESSAGE-4**  I can open a conversation with someone and refresh it without downloading everything again.
  - **MESSAGE-4.a**  I can page back through older history when I want it.
  - **MESSAGE-4.b**  Messages I have already cached are still there when I am offline.
- **MESSAGE-5**  I can reply to a specific message, and the other side sees what I was replying to.
- **MESSAGE-6**  A message written by any AlgoChat implementation can be read by this one, and the other way round.
- **MESSAGE-7**  When I am offline, a message I write waits in a queue and goes out later.
  - **MESSAGE-7.a**  A queued message is never reported as sent when it was not.
- **MESSAGE-8**  Something on the chain that is not a message for me never breaks my conversation list.
- **MESSAGE-9**  A message costs me the network minimum and nothing more unless I choose to send more.
