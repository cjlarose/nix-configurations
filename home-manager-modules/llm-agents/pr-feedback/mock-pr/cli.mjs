#!/usr/bin/env node
// Deterministically render a GitHub-styled mock pull-request page for review.
//
// Given a git commit range plus a PR title and body, emits a self-contained
// HTML file: the title, the body (rendered the way GitHub renders it -- see
// render-body.mjs), the commit list with full messages, and a per-file diff of
// the range (rendered client-side by @pierre/diffs). The diff data is INLINED
// as JSON so the page needs no sibling fetch -- lavish serves it at
// /session/<id>, where a relative fetch would resolve to the wrong path.
//
// Output is a function of (git content, args) only: no timestamps, no random
// ids, stable file ordering. Same inputs -> byte-identical output.
import { execFileSync } from "node:child_process";
import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { renderBody } from "./render-body.mjs";

const CSS = readFileSync(new URL("./styles.css", import.meta.url), "utf8");
const CLIENT = readFileSync(new URL("./client.js", import.meta.url), "utf8");

// --- git helpers -----------------------------------------------------------

function git(repo, ...args) {
  return execFileSync("git", ["-C", repo, ...args], { encoding: "utf8", maxBuffer: 1 << 28 });
}
function gitMaybe(repo, ...args) {
  try {
    return execFileSync("git", ["-C", repo, ...args], { encoding: "utf8", maxBuffer: 1 << 28 });
  } catch {
    return "";
  }
}

function resolveRepoSlug(repo, explicit) {
  if (explicit) return explicit;
  const url = gitMaybe(repo, "remote", "get-url", "origin").trim();
  for (const sep of ["github.com:", "github.com/"]) {
    if (url.includes(sep)) {
      const slug = url.split(sep)[1];
      return slug.endsWith(".git") ? slug.slice(0, -4) : slug;
    }
  }
  return "owner/repo";
}

function commits(repo, base, head) {
  const fmt = "%H%x00%h%x00%an%x00%s%x00%B%x1e";
  const raw = git(repo, "log", "--reverse", `--pretty=format:${fmt}`, `${base}..${head}`);
  const out = [];
  for (let rec of raw.split("\x1e")) {
    rec = rec.replace(/^\n+|\n+$/g, "");
    if (!rec) continue;
    const [sha, short, author, subject, body] = rec.split("\x00");
    out.push({ sha, short, author, subject, message: body.replace(/^\n+|\n+$/g, "") });
  }
  return out;
}

export function changedFiles(repo, base, head) {
  const range = `${base}..${head}`;

  // -z output: NUL-separated records, paths emitted raw (no core.quotePath
  // escaping). numstat: a normal file is one "add\tdel\tpath" record; a rename
  // is "add\tdel\t" followed by two more records (old path, then new path).
  // Binary files report "-\t-" for add/del.
  const numstat = {};
  const ntoks = git(repo, "diff", "--numstat", "-z", range).split("\0");
  for (let i = 0; i < ntoks.length; ) {
    const rec = ntoks[i];
    if (!rec) { i++; continue; }
    const [add, del, p] = rec.split("\t");
    const counts = [/^\d+$/.test(add) ? +add : 0, /^\d+$/.test(del) ? +del : 0];
    if (p === "" || p === undefined) {
      // rename/copy: old, new follow as separate records; key by the new path.
      const newPath = ntoks[i + 2];
      if (newPath != null) numstat[newPath] = counts;
      i += 3;
    } else {
      numstat[p] = counts;
      i += 1;
    }
  }

  // name-status: a status record, then its path -- two paths (old, then new)
  // for renames (R) and copies (C).
  const files = [];
  const stoks = git(repo, "diff", "--name-status", "-z", range).split("\0");
  for (let i = 0; i < stoks.length; ) {
    const code = stoks[i];
    if (!code) { i++; continue; }
    const status = code[0]; // M, A, D, R, C, T (Rxxx -> R)
    let oldRef, path;
    if (status === "R" || status === "C") {
      oldRef = stoks[i + 1];
      path = stoks[i + 2];
      i += 3;
    } else {
      path = stoks[i + 1];
      oldRef = path;
      i += 2;
    }
    if (path == null) break;
    const [additions, deletions] = numstat[path] || [0, 0];
    files.push({
      path,
      status,
      additions,
      deletions,
      old: status === "A" ? "" : gitMaybe(repo, "show", `${base}:${oldRef}`),
      new: status === "D" ? "" : gitMaybe(repo, "show", `${head}:${path}`),
    });
  }
  files.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
  return files;
}

// git's empty tree: diffing against it makes a root commit's every file an "add".
const EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904";

// The diff a single commit introduced: parent..commit, reusing changedFiles so
// per-commit and range diffs share one extraction path. A root commit (no
// parent) is diffed against the empty tree.
export function commitFiles(repo, sha) {
  const parent =
    gitMaybe(repo, "rev-parse", "--verify", "--quiet", `${sha}^`).trim() || EMPTY_TREE;
  return changedFiles(repo, parent, sha);
}

// --- HTML rendering --------------------------------------------------------

export function esc(s) {
  return String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#x27;");
}
function inlineJson(data) {
  // </ -> <\/ so no </script> can terminate the block early; \/ is valid JSON.
  return JSON.stringify(data).replaceAll("</", "<\\/");
}

const MERGE_ICON =
  '<svg width="14" height="14" viewBox="0 0 16 16" aria-hidden="true"><path d="M1.5 3.25a2.25 2.25 0 1 1 3 2.122v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.25 2.25 0 0 1 1.5 3.25Zm5.677-.177L9.573.677A.25.25 0 0 1 10 .854V2.5h1A2.5 2.5 0 0 1 13.5 5v5.628a2.251 2.251 0 1 1-1.5 0V5a1 1 0 0 0-1-1h-1v1.646a.25.25 0 0 1-.427.177L7.177 3.427a.25.25 0 0 1 0-.354ZM3.75 2.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm0 9.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm8.25.75a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0Z"></path></svg>';

function buildHtml({ slug, title, bodyHtml, bodyMd, branch, baseLabel, prNumber, cmts, files }) {
  const totalAdd = files.reduce((a, f) => a + f.additions, 0);
  const totalDel = files.reduce((a, f) => a + f.deletions, 0);
  const nFiles = files.length;
  const s = (n) => (n === 1 ? "" : "s");

  let numHtml, bannerAction, subAction;
  if (prNumber != null) {
    numHtml = `<span class="num">#${esc(prNumber)}</span>`;
    bannerAction = `these commits would be pushed to the already-open <strong>PR #${esc(prNumber)}</strong>`;
    subAction = `add <strong style="color:var(--fg)">${cmts.length} commit${s(cmts.length)}</strong> to <code class="k">${esc(branch)}</code> (open PR #${esc(prNumber)})`;
  } else {
    numHtml = '<span class="num">#draft</span>';
    bannerAction = "no PR exists yet";
    subAction = `merge <strong style="color:var(--fg)">${cmts.length} commit${s(cmts.length)}</strong> into <code class="k">${esc(baseLabel)}</code> from <code class="k">${esc(branch)}</code>`;
  }

  const commitsHtml =
    cmts
      .map((c, i) => {
        const cf = c.files || [];
        const cAdd = cf.reduce((a, f) => a + f.additions, 0);
        const cDel = cf.reduce((a, f) => a + f.deletions, 0);
        const cn = cf.length;
        return (
          `<div class="commit-block">` +
          `<div class="commit-row"><div class="avatar" style="width:32px;height:32px;font-size:13px;background:linear-gradient(135deg,#6e7681,#30363d);">✲</div><div class="commit-main"><div class="commit-subject">${esc(c.subject)}</div><div class="commit-meta"><strong>${esc(c.author)}</strong> committed · ${esc(c.short)}</div></div><span class="sha">${esc(c.short)}</span></div>` +
          `<div class="commit-msg"><pre>${esc(c.message)}</pre></div>` +
          `<div class="commit-diff"><div class="cdiff-head"><span class="chev">▾</span><span class="cdiff-stat"><strong style="color:var(--fg)">${cn}</strong> file${s(cn)} changed</span><span class="add">+${cAdd}</span><span class="del">−${cDel}</span></div><div class="cdiff-body"><div class="commit-files" data-commit="${i}"></div></div></div>` +
          `</div>`
        );
      })
      .join("\n") || '<div class="empty">No commits in this range.</div>';

  const [owner, ...rest] = slug.split("/");
  const repoName = rest.length ? rest.join("/") : slug;

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)} · Pull Request</title>
<style>${CSS}</style>
</head>
<body>
<div class="mockbar"><div class="inner">
  <span>🔍 <strong>Mock preview</strong> — styled after the GitHub pull-request page</span>
  <span class="dot"></span>
  <span>local branch <code class="k">${esc(branch)}</code>, committed but <strong>not pushed</strong>. ${bannerAction}.</span>
</div></div>
<div class="wrap">
  <div class="pr-head">
    <div class="repo-crumb"><a href="#">${esc(owner)}</a> / <a href="#">${esc(repoName)}</a></div>
    <h1 class="pr-title">${esc(title)} ${numHtml}</h1>
    <div class="pr-sub">
      <span class="state">${MERGE_ICON} Open</span>
      <span>${subAction}</span>
    </div>
    <div class="tabs">
      <button class="tab active" data-target="#conversation">💬 Conversation <span class="count">0</span></button>
      <button class="tab" data-target="#commits">🧾 Commits <span class="count">${cmts.length}</span></button>
      <button class="tab" data-target="#files">📄 Files changed <span class="count">${nFiles}</span></button>
    </div>
  </div>
  <section id="conversation" class="tab-panel active">
    <div class="comment">
      <div class="avatar">✲</div>
      <div class="bubble">
        <div class="bubble-head"><span><strong>Proposed change</strong> — for your review before it goes out</span><span class="toggle body-toggle"><button data-view="rendered" class="active">Rendered</button><button data-view="raw">Raw</button></span></div>
        <div class="bubble-body">
          <div class="body-view" data-view="rendered">${bodyHtml}</div>
          <div class="body-view hidden" data-view="raw"><pre class="raw-md">${esc(bodyMd)}</pre></div>
        </div>
      </div>
    </div>
  </section>
  <section id="commits" class="tab-panel">
    <div class="sec-h">Commits</div>
    ${commitsHtml}
  </section>
  <section id="files" class="tab-panel">
    <div class="sec-h">Files changed</div>
    <div class="files-toolbar">
      <div class="diffstat"><span><strong style="color:var(--fg)">${nFiles}</strong> file(s) changed</span><span class="add">+${totalAdd}</span><span class="del">−${totalDel}</span></div>
      <div class="toggle" id="styleToggle"><button data-style="unified" class="active">Unified</button><button data-style="split">Split</button></div>
    </div>
    <div id="files-mount"></div>
  </section>
  <footer>Mock pull-request preview generated locally for review · rendered with @pierre/diffs · GitHub visual style</footer>
</div>
<script id="diffdata" type="application/json">${inlineJson(files)}</script>
${cmts
  .map((c, i) => `<script id="commitdiff-${i}" type="application/json">${inlineJson(c.files || [])}</script>`)
  .join("\n")}
<script type="module">${CLIENT}</script>
</body>
</html>
`;
}

// --- main ------------------------------------------------------------------

async function main() {
  const { values } = parseArgs({
    options: {
      title: { type: "string" },
      "body-file": { type: "string" },
      body: { type: "string" },
      base: { type: "string" },
      head: { type: "string", default: "HEAD" },
      branch: { type: "string" },
      repo: { type: "string" },
      "repo-path": { type: "string", default: "." },
      "pr-number": { type: "string" },
      out: { type: "string", default: ".lavish/mock-pr.html" },
    },
  });

  const die = (msg) => {
    process.stderr.write(`mock-pr-html: ${msg}\n`);
    process.exit(2);
  };
  if (!values.title) die("--title is required");
  if (!values.base) die("--base is required");
  if (!values["body-file"] && values.body == null) die("one of --body-file or --body is required");
  if (values["body-file"] && values.body != null) die("--body-file and --body are mutually exclusive");

  const repo = values["repo-path"];
  const bodyMd = values["body-file"] ? readFileSync(values["body-file"], "utf8") : values.body;
  const branch = values.branch || git(repo, "rev-parse", "--abbrev-ref", "HEAD").trim();
  const slug = resolveRepoSlug(repo, values.repo);
  const baseLabel = values.base.split("/").at(-1); // origin/main -> main
  const prNumber = values["pr-number"] != null ? Number.parseInt(values["pr-number"], 10) : null;

  const bodyHtml = await renderBody(bodyMd, slug);
  const cmts = commits(repo, values.base, values.head);
  for (const c of cmts) c.files = commitFiles(repo, c.sha);
  const files = changedFiles(repo, values.base, values.head);

  const doc = buildHtml({ slug, title: values.title, bodyHtml, bodyMd, branch, baseLabel, prNumber, cmts, files });

  mkdirSync(dirname(values.out) || ".", { recursive: true });
  writeFileSync(values.out, doc);
  process.stdout.write(values.out + "\n");
}

// Run only when invoked as the entry point, so tests can import the functions
// above without triggering the CLI.
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main().catch((e) => {
    process.stderr.write(`mock-pr-html: ${e?.stack || e}\n`);
    process.exit(1);
  });
}
