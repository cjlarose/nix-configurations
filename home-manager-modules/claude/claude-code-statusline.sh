input=$(cat)

blue=$'\e[34m'
green=$'\e[32m'
yellow=$'\e[33m'
red=$'\e[31m'
reset=$'\e[0m'

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')

# Try to parse ~/worktrees/<owner>/<repo>/<worktree> layout
if [[ "$cwd" =~ ^${HOME}/worktrees/([^/]+)/([^/]+)/([^/]+) ]]; then
  repo_owner="${BASH_REMATCH[1]}"
  repo_name="${BASH_REMATCH[2]}"
  worktree_name="${BASH_REMATCH[3]}"
  location="${blue}${repo_owner}/${repo_name}${reset} ${green}[${worktree_name}]${reset}"
else
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

parts=()
parts+=("$location")
parts+=("$model")
[ -n "$effort" ] && parts+=("effort:$effort")
[ -n "$token_part" ] && parts+=("$token_part")

printf "%s" "${parts[*]}"
