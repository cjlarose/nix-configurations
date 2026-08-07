#!/usr/bin/env bash
# SessionStart hook: tell the session which LLM wikis exist, roughly what is in
# each, and whether any captures are waiting to be ingested.
#
# Replaces the per-wiki hook each wiki repo used to ship. Those took a single
# baked-in path and dumped that wiki's whole index.md. Two problems with that,
# and this script exists to fix both:
#
#  1. One path cannot express two wikis, and a session that does not know a
#     wiki exists will never write to it.
#  2. The indexes are 152 KB and 194 KB. Injecting them whole costs roughly
#     90k tokens before the user has typed a character, which is by a wide
#     margin the largest thing in the context window.
#
# So: the routing table is always emitted in full (it is a line or two per wiki
# and it is what makes wiki selection possible at all), and each index is
# truncated to that wiki's declared byte budget, on an entry boundary, with the
# omission stated rather than left silent.
#
# Reads $1, the registry written by the llm-agents module. No paths are baked
# in -- adding a wiki is one attribute in nix, and this script picks it up.
#
# Usage:
#   inject-wiki-context.sh <registry.json>              -> stdout (the hook)
#   inject-wiki-context.sh <registry.json> --write <p>  -> atomically into <p>
#
# The --write form exists for opencode. opencode has no session-start hook that
# can run a command; what it does have is an `instructions` config listing FILE
# paths, read at session start. So the same output that Claude Code's hook
# streams is materialised to a file, and opencode is pointed at it. One
# generator, one wording, both harnesses -- rather than a second implementation
# that drifts.
set -euo pipefail

registry="${1:?usage: inject-wiki-context.sh <registry.json> [--write <path>]}"

# --write is handled by re-running ourselves and redirecting, so the generation
# logic below stays a single straight-line path with no output plumbing threaded
# through it. Written to a temp file and renamed, because a reader (an opencode
# session starting right now) must never see a half-written digest.
if [ "${2:-}" = "--write" ]; then
  out="${3:?--write needs a path}"
  mkdir -p "$(dirname "$out")"
  tmp="$(mktemp "$out.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  "$0" "$registry" > "$tmp"
  mv "$tmp" "$out"
  trap - EXIT
  exit 0
fi

# Nothing to say on a host with no registry. Silent success, so the hook is
# harmless everywhere it is deployed but not configured.
[ -f "$registry" ] || exit 0

# Bulk operations (many `claude -p` calls in a loop) suppress this so the prompt
# prefix stays byte-stable and cacheable. Inherited from the wiki repos' hooks,
# which grew it for exactly that reason.
[ -n "${LLM_WIKI_SUPPRESS_INDEX:-}" ] && exit 0

ids=$(jq -r '.wikis | keys[]' "$registry" 2>/dev/null) || exit 0
[ -n "$ids" ] || exit 0

# --- routing table --------------------------------------------------------
# Emitted before any index, and never truncated. Without it the model cannot
# tell which wiki a piece of material belongs to, which is the one question it
# must get right and cannot recover from getting wrong.
printf '%s\n' "The user keeps the following LLM wikis. Each is a separate repository with its"
printf '%s\n' "own schema; the id is the selector the wiki skills take as an argument."
printf '\n'

while IFS= read -r id; do
  repo=$(jq -r --arg i "$id" '.wikis[$i].repoPath' "$registry")
  hint=$(jq -r --arg i "$id" '.wikis[$i].routingHint' "$registry")
  queue=$(jq -r --arg i "$id" '.wikis[$i].queueDir' "$registry")

  # Uningested captures are tracked by presence in the queue directory and
  # nowhere else -- no manifest, no derived state. Reported on every session
  # start because it is the layer that survives the standing ingest agent being
  # absent, busy or dead: any session on the box surfaces the backlog.
  pending=0
  if [ -d "$repo/$queue" ]; then
    pending=$(find "$repo/$queue" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l)
  fi

  printf -- '- %s — %s\n' "$id" "$hint"
  if [ "$pending" -gt 0 ]; then
    printf '  ⚠ %s uningested capture(s) in %s/%s awaiting ingest\n' "$pending" "$id" "$queue"
  fi
done <<< "$ids"

printf '\n'
printf '%s\n' "Before investigating anything — reading source files, running commands, drafting"
printf '%s\n' "an answer — check the catalogs below against the request. If any page plausibly"
printf '%s\n' "covers the topic, query that wiki FIRST. The wiki carries the user's own verified"
printf '%s\n' "notes: rationale, gotchas and corrections the source does not, and it should"
printf '%s\n' "override your priors where they conflict. Consult it even when you could answer"
printf '%s\n' "from a file read or general knowledge alone."
printf '\n'

# --- per-wiki catalog -----------------------------------------------------
while IFS= read -r id; do
  repo=$(jq -r --arg i "$id" '.wikis[$i].repoPath' "$registry")
  budget=$(jq -r --arg i "$id" '.wikis[$i].indexBudgetBytes' "$registry")
  index="$repo/index.md"

  [ -f "$index" ] || continue

  total=$(wc -c < "$index")
  printf -- '--- BEGIN %s index (%s) ---\n' "$id" "$repo"

  if [ "$total" -le "$budget" ]; then
    cat "$index"
  else
    # Cut on a LINE boundary, which in this file is an entry boundary: index.md
    # is one catalog entry per line, so a whole-line cut never leaves a page
    # title severed from its summary. Then say what was dropped -- a silent cut
    # reads as a complete catalog, and the model concludes with confidence that
    # a page does not exist.
    #
    # Not a heading boundary: sections here run to hundreds of entries, so
    # rounding down to the last `##` would throw away most of the budget.
    awk -v budget="$budget" -v id="$id" '
      BEGIN { used = 0; cut = 0 }
      {
        line = $0 "\n"
        if (!cut && used + length(line) > budget) cut = 1
        if (!cut) { used += length(line); print; next }
        # Past the budget: count what is being dropped, so the notice can be
        # specific rather than a vague "truncated".
        if ($0 ~ /^[[:space:]]*-[[:space:]]/) dropped_entries++
        dropped_lines++
      }
      END {
        if (cut) {
          printf "\n… truncated at this wiki%s %d-byte budget: %d further catalog entr%s (%d lines) omitted.\n", \
            "'\''s", budget, dropped_entries, (dropped_entries == 1 ? "y" : "ies"), dropped_lines
          printf "The catalog above is PARTIAL — absence from it does not mean a page does not exist.\n"
          printf "Query the %s wiki to search the full index.\n", id
        }
      }
    ' "$index"
  fi

  printf -- '--- END %s index ---\n\n' "$id"
done <<< "$ids"
