-- PR-style commit-by-commit review of the current feature branch
vim.keymap.set("n", "<leader>dp", ":DiffviewFileHistory --range=origin/main..HEAD --reverse ",
  { desc = "Diffview: PR-style commit-by-commit review" })

-- Merged diff of the feature branch vs. merge-base with origin/main
vim.keymap.set("n", "<leader>dd", ":DiffviewOpen origin/main...HEAD ",
  { desc = "Diffview: whole diff against origin/main" })
