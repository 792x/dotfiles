#!/usr/bin/env bash
# Claude Code statusline: repo, branch, the AWS account this tree points at, and
# which stage terraform-output.json was generated for. Everything here must stay
# cheap (no git status, no network) since it runs on every render.
set -uo pipefail

input=$(cat)
cwd=$(printf '%s' "$input" | /usr/bin/sed -n 's/.*"current_dir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -z "$cwd" ] && cwd=$(printf '%s' "$input" | /usr/bin/sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -z "$cwd" ] && cwd=$PWD

dim=$'\033[2m'; off=$'\033[0m'; cyan=$'\033[36m'; yellow=$'\033[33m'; red=$'\033[31m'; green=$'\033[32m'

root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$root" ]; then
  printf '%s%s%s\n' "$dim" "${cwd/#$HOME/~}" "$off"
  exit 0
fi

# In a private worktree the directory is named <repo>-<slug>; show the repo it
# belongs to and let the wt marker carry the rest.
main_tree=$(git -C "$root" worktree list --porcelain 2>/dev/null | /usr/bin/sed -n '1s/^worktree //p')
repo=$(basename "${main_tree:-$root}")
branch=$(git -C "$root" symbolic-ref --short HEAD 2>/dev/null || echo detached)
# a worktree under the wt root is a private tree; the main checkout is shared
case "$root" in
  "${WT_ROOT:-$HOME/Code/wt}"/*) tree="${green}wt${off}" ;;
  *) tree="" ;;
esac

# profile: the exported one if we have it, else whatever direnv would export
profile=${AWS_PROFILE:-}
if [ -z "$profile" ] && [ -r "$root/.envrc" ]; then
  profile=$(/usr/bin/sed -n 's/.*AWS_PROFILE=["'"'"']\{0,1\}\([A-Za-z0-9_-]*\).*/\1/p' "$root/.envrc" | head -1)
fi

out="$root/terraform/terraform-output.json"
stage=""
if [ -r "$out" ]; then
  stage=$(LC_ALL=C /usr/bin/grep -o -m1 'env-\(dev3\|dev2\|dev\|test\|beta\|prod\)-eu-' "$out" 2>/dev/null)
  stage=${stage#env-}; stage=${stage%-eu-}
fi

line="${cyan}${repo}${off} ${dim}${branch}${off}"
[ -n "$tree" ] && line="$line ${tree}"
if [ -n "$profile" ]; then
  case "$profile" in
    *prod*) line="$line ${dim}·${off} ${red}${profile}${off}" ;;
    *beta*|*test*) line="$line ${dim}·${off} ${yellow}${profile}${off}" ;;
    *) line="$line ${dim}·${off} ${green}${profile}${off}" ;;
  esac
fi
if [ -n "$stage" ]; then
  if [ -n "$profile" ] && [ "${profile#env-}" != "$stage" ]; then
    line="$line ${dim}·${off} ${red}tf:${stage}${off}"      # disagrees with the profile
  else
    line="$line ${dim}· tf:${stage}${off}"
  fi
fi
printf '%s\n' "$line"
