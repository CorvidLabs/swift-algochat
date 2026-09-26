---
change: render-the-high-level-design-with-mermaid-on-the-github-pages-site
artifact: context
---

# Context

PR #32 adds `docs/HLD.md`, a high-level design with Mermaid diagrams. GitHub renders those diagrams in the repository view, but the GitHub Pages site is a DocC archive built by `.github/workflows/docs.yml`, and DocC does not render Mermaid. This change publishes the HLD on the Pages site as a sibling page at `/architecture/`, next to the unchanged DocC archive.

Constraints and choices:

- Least invasive option from the CorvidLabs docs kit: no DocC catalog is added under `Sources/`, so the library target, its symbols and the spec contract are untouched.
- The DocC output moves from `./docs` to `./_site`, because `./docs` now holds documentation sources and a local run of the old command would write the DocC archive over them. `_site/` is ignored.
- `docs/pages/build-architecture.ts` converts the Markdown with Bun's built-in `Bun.markdown` (Bun 1.4.0, no packages installed), gives headings GitHub-style ids so the in-page links work, turns Mermaid fences into `<pre class="mermaid">`, and points repository-relative links at the files on GitHub. `docs/pages/architecture.html` is the page shell; it loads Mermaid 11 from jsDelivr and draws the diagrams in the browser.
- The workflow now also runs when `docs/**` changes, so HLD edits redeploy the page.
- Merge after PR #32: the render step reads `docs/HLD.md`, which lands there.
