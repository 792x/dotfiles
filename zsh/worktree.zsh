# wt: one git worktree per task. Repo-agnostic; set WT_ROOT to move the tree
# root, WT_BRANCH_PREFIX to change the branch namespace, WT_CARRY to change
# which untracked files a new tree inherits.
#
#   wt ABC-367          worktree + branch feature/abc-367 off origin/main
#   wt ABC-367 main     ... off a different base
#   wt                  fzf over existing worktrees, cd to the pick
#   wt rm               remove the worktree you are standing in
# Parallel Claude sessions in a single checkout clobber each other's uncommitted
# work (a `git checkout <path>` in one destroys the other's edits). One worktree
# per ticket removes the shared state entirely.
_wt_root() { print -r -- "${${WT_ROOT:-$HOME/Code/wt}:A}" }

wt() {
  local repo_root repo slug branch base dest
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || { print -u2 "wt: not in a git repo"; return 1 }
  repo=${repo_root:t}

  if [[ -z "$1" ]]; then
    local pick
    pick=$(git worktree list | fzf --height 40% --reverse --prompt "worktree ▸ ") || return
    cd "${pick%% *}"
    return
  fi

  if [[ "$1" == (rm|-d|--remove) ]]; then
    local here force=0 untracked
    [[ "$2" == (-f|--force) || "$1" == (-d) && "$2" == (-f) ]] && force=1
    here=$(git rev-parse --show-toplevel)
    [[ "$here" == "$(_wt_root)"/* ]] || { print -u2 "wt rm: $here is not under $(_wt_root)"; return 1 }
    if [[ -n $(git status --porcelain -uno) ]]; then
      print -u2 "wt rm: tracked changes here, commit or discard them first"
      return 1
    fi
    untracked=$(git ls-files --others --exclude-standard)
    if [[ -n "$untracked" && $force -eq 0 ]]; then
      print -u2 "wt rm: untracked files would be deleted:"
      print -u2 -- "${untracked//(#m)*/  $MATCH}"
      print -u2 "wt rm: re-run as  wt rm -f  to remove anyway"
      return 1
    fi
    local main=$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')
    cd "$main" || return 1
    git worktree remove ${force:+--force} "$here" && print "removed $here"
    return
  fi

  slug=${${1:l}//[^a-z0-9]/-}          # ABC-367 -> abc-367
  slug=${slug//--/-}
  branch="${WT_BRANCH_PREFIX:-feature/}$slug"
  base=${2:-origin/main}
  git -C "$repo_root" rev-parse --verify --quiet "$base" >/dev/null \
    || { print -u2 "wt: no $base, branching off HEAD instead"; base=HEAD }
  dest="$(_wt_root)/$repo-$slug"

  if [[ -d "$dest" ]]; then
    print "wt: reusing $dest"
    cd "$dest"
    return
  fi

  # A branch can live in only one worktree. Usually it is checked out in the
  # shared tree you are standing in, which is the whole reason you want a
  # private one, so say what to do rather than letting git's fatal land.
  local holder
  holder=$(git -C "$repo_root" worktree list --porcelain \
    | awk -v b="refs/heads/$branch" '/^worktree /{w=$2} /^branch /{if($2==b){print w; exit}}')
  if [[ -n "$holder" ]]; then
    print -u2 "wt: $branch is already checked out in $holder"
    print -u2 "wt: work there, or take a second branch off it with  wt $slug-2"
    return 1
  fi

  git -C "$repo_root" fetch --quiet origin 2>/dev/null
  mkdir -p "$(_wt_root)"
  if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$repo_root" worktree add "$dest" "$branch" || return 1
  elif git -C "$repo_root" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    git -C "$repo_root" worktree add "$dest" --track -b "$branch" "origin/$branch" || return 1
  else
    # --no-track: branching off origin/main must not leave main as the upstream
    git -C "$repo_root" worktree add "$dest" --no-track -b "$branch" "$base" || return 1
  fi

  # git config is per-worktree for these, and the prompt's dirty check needs them
  git -C "$dest" config core.fsmonitor true
  git -C "$dest" config core.untrackedCache true

  # Carry over local state the tree needs, but only files git does not track:
  # a tracked .envrc is already in the new tree, and replacing it with a symlink
  # would show up as a typechange in every worktree you create.
  local f
  for f in ${WT_CARRY:-.envrc .env .env.local}; do
    [[ -f "$repo_root/$f" ]] || continue
    git -C "$repo_root" ls-files --error-unmatch "$f" >/dev/null 2>&1 && continue
    mkdir -p "$dest/${f:h}"
    cp "$repo_root/$f" "$dest/$f"
  done

  cd "$dest"
  if [[ -z "$WT_NO_INSTALL" && -f package.json ]]; then
    print "wt: pnpm install in $dest"
    pnpm install --child-concurrency=4 || print -u2 "wt: pnpm install failed, run it yourself"
  fi
  print "wt: $branch in $dest"
}

