// TDD for the GitHub-faithful body renderer. Runs on every nix build (the
// package's check phase), so a rendering regression fails the build. Each case
// encodes a behavior GitHub actually has; the reference for the autolink rules
// is remark-github.
import { test } from "node:test";
import assert from "node:assert/strict";
import { renderBody } from "./render-body.mjs";

const REPO = "cjlarose/nix-configurations";
const r = (md) => renderBody(md, REPO);

test("issue/PR #N autolinks to this repo", async () => {
  const h = await r("Closes #42.");
  assert.match(h, /<a href="https:\/\/github\.com\/cjlarose\/nix-configurations\/issues\/42">#42<\/a>/);
});

test("GH-N autolinks", async () => {
  assert.match(await r("See GH-7."), /\/issues\/7">GH-7<\/a>/);
});

test("cross-repo owner/repo#N autolinks to that repo", async () => {
  assert.match(await r("See octocat/hello-world#7."), /https:\/\/github\.com\/octocat\/hello-world\/issues\/7/);
});

test("@mention is linked and bolded", async () => {
  assert.match(await r("Thanks @octocat."), /<a href="https:\/\/github\.com\/octocat"><strong>@octocat<\/strong><\/a>/);
});

test("@org/team mention is linked", async () => {
  const h = await r("cc @cjlarose/reviewers");
  assert.match(h, /<a href="https:\/\/github\.com\/[^"]*cjlarose[^"]*reviewers"><strong>@cjlarose\/reviewers<\/strong><\/a>/);
});

test("bare 40-char SHA links to the commit and is shortened to 7", async () => {
  const sha = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef";
  const h = await r(`Fixed in ${sha}.`);
  assert.match(h, new RegExp(`href="https://github.com/cjlarose/nix-configurations/commit/${sha}"><code>deadbee</code></a>`));
});

test("cross-repo owner/repo@sha links to that repo's commit", async () => {
  const sha = "0123456789abcdef0123456789abcdef01234567";
  assert.match(await r(`octocat/hello-world@${sha}`), /github\.com\/octocat\/hello-world\/commit\//);
});

test("commit range sha1...sha2 is one compare link, both shortened to 7", async () => {
  const h = await r("Range abcdef1234...9876543abc shipped.");
  assert.match(h, /\/compare\/abcdef1234\.\.\.9876543abc"><code>abcdef1\.\.\.9876543<\/code><\/a>/);
});

test("autolinking is skipped inside code spans", async () => {
  const h = await r("Literal `#42` and `deadbeefdeadbeefdeadbeefdeadbeefdeadbeef` stay.");
  assert.match(h, /<code>#42<\/code>/);
  assert.doesNotMatch(h, /<code>\s*<a /);
});

test("autolinking is skipped inside fenced code blocks", async () => {
  const h = await r("```\n#42 deadbeefdeadbeefdeadbeefdeadbeefdeadbeef @octocat\n```");
  assert.doesNotMatch(h, /<pre>[\s\S]*<a /);
});

test("GFM table renders", async () => {
  const h = await r("| a | b |\n|---|---|\n| 1 | 2 |");
  assert.match(h, /<table>/);
  assert.match(h, /<th>a<\/th>/);
  assert.match(h, /<td>1<\/td>/);
});

test("GFM strikethrough", async () => {
  assert.match(await r("~~gone~~"), /<del>gone<\/del>/);
});

test("GFM task list checkboxes", async () => {
  const h = await r("- [x] done\n- [ ] todo");
  assert.ok(h.includes('class="task-list-item"'));
  assert.ok(h.includes('type="checkbox" checked'), "checked box present");
  assert.ok(h.includes('type="checkbox" disabled>'), "unchecked box present");
});

test("bare URL is linkified", async () => {
  assert.match(await r("Visit https://example.com now."), /<a href="https:\/\/example\.com">https:\/\/example\.com<\/a>/);
});

test("footnote renders a footnotes section", async () => {
  const h = await r("Text.[^1]\n\n[^1]: the note");
  assert.match(h, /class="[^"]*footnotes/);
});

test("alert block > [!WARNING] becomes a titled callout", async () => {
  const h = await r("> [!WARNING]\n> be careful");
  assert.match(h, /<div class="markdown-alert markdown-alert-warning">/);
  assert.match(h, /<p class="markdown-alert-title">Warning<\/p>/);
  assert.match(h, /be careful/);
});

test("all five alert kinds map to their classes", async () => {
  for (const [k, cls] of [["NOTE", "note"], ["TIP", "tip"], ["IMPORTANT", "important"], ["WARNING", "warning"], ["CAUTION", "caution"]]) {
    assert.match(await r(`> [!${k}]\n> x`), new RegExp(`markdown-alert-${cls}`));
  }
});

test("non-alert blockquote is untouched", async () => {
  const h = await r("> just a quote");
  assert.match(h, /<blockquote>/);
  assert.doesNotMatch(h, /markdown-alert/);
});
