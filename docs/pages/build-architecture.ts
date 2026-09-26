// Renders docs/HLD.md into docs/pages/architecture.html for the GitHub Pages site.
// Mermaid fences become <pre class="mermaid"> blocks that the page draws in the browser,
// and repository-relative links point at the files on GitHub.
//
// Usage: bun docs/pages/build-architecture.ts <output.html>

const repositoryBlob = "https://github.com/CorvidLabs/swift-algochat/blob/main/";
const placeholder = "<!-- HLD -->";

const output = Bun.argv[2];
if (!output) {
    console.error("usage: bun docs/pages/build-architecture.ts <output.html>");
    process.exit(2);
}

const source = await Bun.file(new URL("../HLD.md", import.meta.url)).text();
const template = await Bun.file(new URL("architecture.html", import.meta.url)).text();
if (!template.includes(placeholder)) {
    throw new Error(`architecture.html is missing the ${placeholder} placeholder`);
}

const body = Bun.markdown
    .html(source, { headings: { ids: true } })
    .replace(/<pre><code class="language-mermaid">([\s\S]*?)<\/code><\/pre>/g, '<pre class="mermaid" tabindex="0">$1</pre>')
    .replaceAll('href="../', `href="${repositoryBlob}`)
    .replaceAll("<table>", '<div class="table-scroll" tabindex="0"><table>')
    .replaceAll("</table>", "</table></div>");

const diagrams = body.match(/<pre class="mermaid"/g)?.length ?? 0;
if (diagrams === 0) {
    throw new Error("no Mermaid diagrams found in docs/HLD.md");
}

await Bun.write(output, template.replace(placeholder, () => body));
console.log(`wrote ${output} with ${diagrams} Mermaid diagrams`);
