#!/usr/bin/env bash
# Claude Code statusline: repo, branch, whether this is a private worktree, the
# AWS account the tree points at, and the environment terraform is initialised
# for. Everything here must stay cheap (no git status, no network) since it runs
# on every render.
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

# A worktree is private to one session; the main checkout is shared. Name the
# repo after the main tree either way, so a worktree still says where it came
# from, and mark the worktree with its own directory name.
main_tree=$(git -C "$root" worktree list --porcelain 2>/dev/null | /usr/bin/sed -n '1s/^worktree //p')
repo=$(basename "${main_tree:-$root}")
branch=$(git -C "$root" symbolic-ref --short HEAD 2>/dev/null || echo detached)
tree=""
[ -n "$main_tree" ] && [ "$main_tree" != "$root" ] && tree="${green}wt:$(basename "$root")${off}"

# profile: the exported one if we have it, else whatever direnv would export
profile=${AWS_PROFILE:-}
if [ -z "$profile" ] && [ -r "$root/.envrc" ]; then
  profile=$(/usr/bin/sed -n 's/.*AWS_PROFILE=["'"'"']\{0,1\}\([A-Za-z0-9_-]*\).*/\1/p' "$root/.envrc" | head -1)
fi

# stage: the environment `terraform apply` would hit from this tree. The
# initialised backend names it, so no terraform run is needed to read it.
stage=""
for f in "$root/infrastructure/.terraform/terraform.tfstate" "$root/terraform/.terraform/terraform.tfstate"; do
  [ -r "$f" ] || continue
  stage=$(LC_ALL=C /usr/bin/grep -o -m1 -E -- '-(dev[0-9]*|test|beta|stg|staging|prod)-terraform-(state|lock)' "$f" 2>/dev/null)
  stage=${stage#-}; stage=${stage%-terraform-*}
  [ -n "$stage" ] && break
done
# repos that publish a generated output file instead name the stage in it
if [ -z "$stage" ] && [ -r "$root/terraform/terraform-output.json" ]; then
  stage=$(LC_ALL=C /usr/bin/grep -o -m1 -E -- '-(dev[0-9]*|test|beta|stg|prod)-eu-' "$root/terraform/terraform-output.json" 2>/dev/null)
  stage=${stage#-}; stage=${stage%-eu-}
fi

line="${cyan}${repo}${off} ${dim}${branch}${off}"
[ -n "$tree" ] && line="$line ${tree}"
if [ -n "$profile" ]; then
  case "$profile" in
    *prod*) line="$line ${dim}·${off} ${red}${profile}${off}" ;;
    *beta*|*test*|*stg*|*staging*) line="$line ${dim}·${off} ${yellow}${profile}${off}" ;;
    *) line="$line ${dim}·${off} ${green}${profile}${off}" ;;
  esac
fi
if [ -n "$stage" ]; then
  # the profile's last segment is its environment: env-prod and prod agree
  if [ -n "$profile" ] && [ "${profile##*-}" != "$stage" ]; then
    line="$line ${dim}·${off} ${red}tf:${stage}${off}"      # disagrees with the profile
  else
    line="$line ${dim}· tf:${stage}${off}"
  fi
fi
printf '%s\n' "$line"
