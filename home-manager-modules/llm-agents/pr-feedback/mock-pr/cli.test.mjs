// Tests for the CLI's git parsing and HTML escaping -- the code paths where the
// adversarial review found real bugs (rename +/- counts, path escaping). Uses
// node's built-in runner plus a throwaway git repo, so it needs git on PATH
// (pr-feedback.nix supplies it to the check phase via nativeCheckInputs).
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { esc, changedFiles } from "./cli.mjs";

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
