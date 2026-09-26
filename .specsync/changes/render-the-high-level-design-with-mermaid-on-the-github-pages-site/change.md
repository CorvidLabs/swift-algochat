---
id: render-the-high-level-design-with-mermaid-on-the-github-pages-site
state: draft
type: documentation
base_commit: fba536f1b0ed4f240f14547262be1548b32650c9
---

# Render the high-level design with Mermaid on the GitHub Pages site

## Intent

Render the high-level design with Mermaid on the GitHub Pages site

## Affected Canonical Specs

- None

## Acceptance Criteria

- The docs workflow publishes docs/HLD.md at /architecture/ on the GitHub Pages site with every Mermaid diagram rendered, keeps the DocC API reference at /documentation/algochat/, and changes nothing under Sources/, Tests/ or Package.swift

## No-spec Rationale

Documentation publishing only; the AlgoChat library, CLI and canonical contract are unchanged
