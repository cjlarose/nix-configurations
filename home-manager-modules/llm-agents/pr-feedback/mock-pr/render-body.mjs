// Render a PR body (GitHub-flavored markdown) to HTML the way GitHub does:
// GFM (tables, task lists, strikethrough, linkified URLs, footnotes) via
// remark-gfm, GitHub's app-level autolinking (#123, owner/repo#123, @user,
// @org/team, bare and cross-repo commit SHAs shortened to 7 chars, ranges) via
// remark-github (the reference implementation), and GitHub-style alert blocks
// (> [!NOTE] etc.) via the small plugin below. `repository` ("owner/repo") is
// how remark-github resolves bare #123 / SHA references.
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import remarkGithub from "remark-github";
import remarkRehype from "remark-rehype";
import rehypeRaw from "rehype-raw";
import rehypeStringify from "rehype-stringify";
import { visit } from "unist-util-visit";

// GitHub alerts: a blockquote whose first line is [!NOTE|TIP|IMPORTANT|WARNING|
// CAUTION] becomes a titled callout div. Runs BEFORE remark-github so the marker
// text is gone before autolinking sees it.
const ALERT = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*\n?/;
function remarkAlerts() {
  return (tree) => {
    visit(tree, "blockquote", (node) => {
      const para = node.children[0];
      if (!para || para.type !== "paragraph") return;
      const lead = para.children[0];
      if (!lead || lead.type !== "text") return;
      const m = lead.value.match(ALERT);
      if (!m) return;
      const kind = m[1].toLowerCase();
      const title = m[1][0] + m[1].slice(1).toLowerCase();
      lead.value = lead.value.replace(ALERT, "");
      node.data = {
        hName: "div",
        hProperties: { className: ["markdown-alert", `markdown-alert-${kind}`] },
      };
      node.children.unshift({
        type: "html",
        value: `<p class="markdown-alert-title">${title}</p>`,
      });
    });
  };
}

const processor = (repository) =>
  unified()
    .use(remarkParse)
    .use(remarkGfm)
    .use(remarkAlerts)
    .use(remarkGithub, { repository, mentionStrong: true })
    .use(remarkRehype, { allowDangerousHtml: true })
    .use(rehypeRaw)
    .use(rehypeStringify);

export async function renderBody(markdown, repository = "owner/repo") {
  const file = await processor(repository).process(markdown);
  return String(file);
}
