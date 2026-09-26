---
change: render-the-high-level-design-with-mermaid-on-the-github-pages-site
artifact: docs
---

# Docs

After this change the Pages site serves two things:

- `https://corvidlabs.github.io/swift-algochat/documentation/algochat/`: the DocC API reference, unchanged.
- `https://corvidlabs.github.io/swift-algochat/architecture/`: `docs/HLD.md` rendered as HTML with all Mermaid diagrams drawn, linking back to the API reference, the Markdown source and the protocol specification.

Verification done before the PR: a local DocC build into `./_site` followed by the render step produced both, and a headless Chrome check drew 12 of 12 diagrams with no Mermaid errors and no axe WCAG 2.1 AA violations in light or dark mode, with no horizontal scroll at phone width.

Public API, CLI behavior and the canonical `algochat` spec are unaffected.
