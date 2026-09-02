input=$(cat)

yellow=$'\e[33m'
red=$'\e[31m'
dim=$'\e[2m'
reset=$'\e[0m'

model=$(echo "$input" | jq -r '.model.display_name')

used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
input_tokens=$(echo "$input" | jq -r '.context_window.current_usage | if . then (.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens) else empty end')

if [ -n "$input_tokens" ] && [ -n "$used_pct" ]; then
  # Format tokens: if >= 1000, display as e.g. 24.4k
  if [ "$input_tokens" -ge 1000 ]; then
    tokens_fmt=$(awk "BEGIN { printf \"%.1fk\", $input_tokens / 1000 }")
  else
    tokens_fmt="${input_tokens}"
  fi
  pct_fmt=$(printf "%.1f%%" "$used_pct")
  if [ "$input_tokens" -ge 100000 ]; then
    token_part="${red}${tokens_fmt} (${pct_fmt})${reset}"
  elif [ "$input_tokens" -ge 80000 ]; then
    token_part="${yellow}${tokens_fmt} (${pct_fmt})${reset}"
  else
    token_part="${tokens_fmt} (${pct_fmt})"
  fi
else
  token_part=""
fi

# Location segment. Labels mirror the JSON object names (.workspace / .worktree).
# A Claude-managed worktree is detected by current_dir sitting under
# .claude/worktrees/ — the path is always present, unlike the .worktree.* fields
# which don't populate for background auto-isolation. The worktree's origin
# (the checkout it lives under) is the path segment before .claude/worktrees/;
# we hide it when it's the main "default" tree and show it otherwise.
main_tree_dir="default"

owner=$(echo "$input" | jq -r '.workspace.repo.owner // empty')
repo=$(echo "$input" | jq -r '.workspace.repo.name // empty')
cwd=$(echo "$input" | jq -r '(.workspace.current_dir // .cwd) // empty')
git_worktree=$(echo "$input" | jq -r '.workspace.git_worktree // empty')
wt_name=$(echo "$input" | jq -r '.worktree.name // empty')

loc=""
if [ -n "$repo" ]; then
  if [ -n "$owner" ]; then or="$owner/$repo"; else or="$repo"; fi

  case "$cwd" in
    */.claude/worktrees/*)
      before="${cwd%%/.claude/worktrees/*}"
      after="${cwd##*/.claude/worktrees/}"
      origin="${before##*/}"
      [ -z "$wt_name" ] && wt_name="${after%%/*}"
      if [ "$origin" = "$main_tree_dir" ]; then
        loc="workspace: $or | worktree: $wt_name"
      else
        loc="workspace: $or ($origin) | worktree: $wt_name"
      fi
      ;;
    *)
      if [ -n "$git_worktree" ]; then
        loc="workspace: $or ($git_worktree)"
      else
        loc="workspace: $or"
      fi
      ;;
  esac
fi

parts=()
[ -n "$loc" ] && parts+=("${dim}${loc}${reset}")
parts+=("$model")
[ -n "$token_part" ] && parts+=("$token_part")

printf "%s" "${parts[*]}"
