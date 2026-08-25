// Tests for the CLI's git parsing and HTML escaping -- the code paths where the
// adversarial review found real bugs (rename +/- counts, path escaping). Uses
// node's built-in runner plus a throwaway git repo, so it needs git on PATH
// (pr-feedback.nix supplies it to the check phase via nativeCheckInputs).
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { esc, changedFiles, commitFiles } from "./cli.mjs";

const CLI = fileURLToPath(new URL("./cli.mjs", import.meta.url));

test("esc escapes the five HTML-significant characters", () => {
  assert.equal(esc(`<img src=x onerror="a">&'`), "&lt;img src=x onerror=&quot;a&quot;&gt;&amp;&#x27;");
  assert.equal(esc(42), "42");
});

function initRepo() {
  const dir = mkdtempSync(join(tmpdir(), "mockpr-"));
  const g = (...a) =>
    execFileSync(
      "git",
      ["-C", dir, "-c", "user.email=t@t", "-c", "user.name=t",
       "-c", "init.defaultBranch=main", "-c", "commit.gpgsign=false", ...a],
      { encoding: "utf8" },
    );
  g("init", "-q");
  return { dir, g };
}

test("changedFiles: rename+edit counts, add/delete/modify, spaced+unquoted paths", () => {
  const { dir, g } = initRepo();
  try {
    writeFileSync(join(dir, "old.txt"), "one\ntwo\nthree\nfour\n");
    writeFileSync(join(dir, "gone.txt"), "bye\n");
    writeFileSync(join(dir, "keep.txt"), "a\n");
    g("add", "-A");
    g("commit", "-qm", "base");

    // rename old.txt -> "renamed file.txt" (a spaced path) with a one-line add;
    // add a file; delete a file; modify a file.
    g("mv", "old.txt", "renamed file.txt");
    writeFileSync(join(dir, "renamed file.txt"), "one\ntwo\nthree\nfour\nfive\n");
    writeFileSync(join(dir, "added.txt"), "new\n");
    rmSync(join(dir, "gone.txt"));
    writeFileSync(join(dir, "keep.txt"), "a\nb\n");
    g("add", "-A");
    g("commit", "-qm", "change");

    const files = changedFiles(dir, "HEAD~1", "HEAD");
    const by = Object.fromEntries(files.map((f) => [f.path, f]));

    // The rename bug: without -z this keyed on "old => new" and reported 0/0.
    const ren = by["renamed file.txt"]; // spaced path must arrive UNQUOTED
    assert.ok(ren, "renamed (spaced) path present");
    assert.equal(ren.status, "R");
    assert.deepEqual([ren.additions, ren.deletions], [1, 0]);

    assert.equal(by["added.txt"].status, "A");
    assert.equal(by["added.txt"].old, "");
    assert.equal(by["gone.txt"].status, "D");
    assert.equal(by["gone.txt"].new, "");
    assert.deepEqual([by["keep.txt"].additions, by["keep.txt"].deletions], [1, 0]);

    // deterministic: output sorted by path
    const paths = files.map((f) => f.path);
    assert.deepEqual(paths, [...paths].sort());
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("commitFiles: each commit's own diff, distinct from the unified range diff", () => {
  const { dir, g } = initRepo();
  try {
    // base -> add X (commit A) -> add Y (commit B), all to the same file.
    writeFileSync(join(dir, "f.txt"), "a\n");
    g("add", "-A");
    g("commit", "-qm", "base");
    writeFileSync(join(dir, "f.txt"), "a\nX\n");
    g("add", "-A");
    g("commit", "-qm", "add X");
    writeFileSync(join(dir, "f.txt"), "a\nX\nY\n");
    g("add", "-A");
    g("commit", "-qm", "add Y");

    // The unified range diff (base..HEAD) folds both edits together.
    const [range] = changedFiles(dir, "HEAD~2", "HEAD");
    assert.equal(range.path, "f.txt");
    assert.deepEqual([range.additions, range.deletions], [2, 0]);
    assert.equal(range.new, "a\nX\nY\n");

    // Commit A adds only X; its "new" side stops before Y exists.
    const [a] = commitFiles(dir, "HEAD~1");
    assert.equal(a.path, "f.txt");
    assert.deepEqual([a.additions, a.deletions], [1, 0]);
    assert.equal(a.old, "a\n");
    assert.equal(a.new, "a\nX\n");

    // Commit B adds only Y, on top of A's contents.
    const [b] = commitFiles(dir, "HEAD");
    assert.deepEqual([b.additions, b.deletions], [1, 0]);
    assert.equal(b.old, "a\nX\n");
    assert.equal(b.new, "a\nX\nY\n");

    // Each per-commit diff really is narrower than the folded range diff.
    assert.notEqual(a.new, range.new);
    assert.notEqual(b.old, range.old);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("commitFiles: a root commit diffs against the empty tree (all adds)", () => {
  const { dir, g } = initRepo();
  try {
    writeFileSync(join(dir, "seed.txt"), "hello\n");
    g("add", "-A");
    g("commit", "-qm", "root");
    const files = commitFiles(dir, "HEAD");
    const seed = files.find((f) => f.path === "seed.txt");
    assert.ok(seed, "root commit's file present");
    assert.equal(seed.status, "A");
    assert.equal(seed.old, "");
    assert.equal(seed.new, "hello\n");
    assert.deepEqual([seed.additions, seed.deletions], [1, 0]);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("changedFiles: binary file reports 0/0 rather than NaN", () => {
  const { dir, g } = initRepo();
  try {
    g("commit", "-qm", "empty", "--allow-empty");
    writeFileSync(join(dir, "blob.bin"), Buffer.from([0, 1, 2, 0, 255, 0, 3]));
    g("add", "-A");
    g("commit", "-qm", "add binary");
    const [f] = changedFiles(dir, "HEAD~1", "HEAD");
    assert.equal(f.path, "blob.bin");
    assert.deepEqual([f.additions, f.deletions], [0, 0]);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("page has three exclusive tab panels, Conversation active by default", () => {
  const { dir, g } = initRepo();
  const out = join(dir, "out.html");
  const body = join(dir, "body.md");
  try {
    writeFileSync(join(dir, "a.txt"), "one\n");
    g("add", "-A");
    g("commit", "-qm", "base");
    writeFileSync(join(dir, "a.txt"), "one\ntwo\n");
    g("add", "-A");
    g("commit", "-qm", "second");
    writeFileSync(body, "# hi\n");
    execFileSync(
      process.execPath,
      [CLI, "--title", "T", "--body-file", body, "--base", "HEAD~1", "--head", "HEAD", "--repo-path", dir, "--out", out],
      { encoding: "utf8" },
    );
    const html = readFileSync(out, "utf8");

    // Exactly three tab panels, exactly one active -- one section shown at a time.
    assert.equal((html.match(/class="tab-panel[^"]*"/g) || []).length, 3);
    assert.equal((html.match(/class="tab-panel active"/g) || []).length, 1);
    // Conversation is the default-active section; the other two start hidden.
    assert.match(html, /<section id="conversation" class="tab-panel active">/);
    assert.match(html, /<section id="commits" class="tab-panel">/);
    assert.match(html, /<section id="files" class="tab-panel">/);
    // Tab buttons target the sections by id.
    for (const t of ["#conversation", "#commits", "#files"]) {
      assert.match(html, new RegExp(`data-target="${t}"`));
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
