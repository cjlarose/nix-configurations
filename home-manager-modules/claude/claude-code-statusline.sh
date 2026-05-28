input=$(cat)

repo_owner=$(echo "$input" | jq -r '.workspace.repo.owner // empty')
repo_name=$(echo "$input" | jq -r '.workspace.repo.name // empty')
worktree=$(echo "$input" | jq -r '.workspace.git_worktree // empty')

if [ -n "$repo_owner" ] && [ -n "$repo_name" ]; then
  location="${repo_owner}/${repo_name}"
  [ -n "$worktree" ] && location="${location} [${worktree}]"
else
  cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
  location="${cwd/#"$HOME"/\~}"
fi

model=$(echo "$input" | jq -r '.model.display_name')
effort=$(echo "$input" | jq -r '.output_style.name // "default"')

used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
input_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')

if [ -n "$input_tokens" ] && [ -n "$used_pct" ]; then
  # Format tokens: if >= 1000, display as e.g. 24.4k
  if [ "$input_tokens" -ge 1000 ]; then
    tokens_fmt=$(awk "BEGIN { printf \"%.1fk\", $input_tokens / 1000 }")
  else
    tokens_fmt="${input_tokens}"
  fi
  pct_fmt=$(printf "%.1f%%" "$used_pct")
  token_part="${tokens_fmt} (${pct_fmt})"
else
  token_part=""
fi

parts=()
parts+=("$location")
parts+=("$model")
[ -n "$effort" ] && parts+=("effort:$effort")
[ -n "$token_part" ] && parts+=("$token_part")

printf "%s" "${parts[*]}"
