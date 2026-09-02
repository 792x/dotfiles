#!/usr/bin/env bash
# PreToolUse(Bash) guard for a checkout that several Claude sessions share.
#
# A git command that restores or discards working-tree state in a shared tree
# destroys another session's uncommitted work with no warning and no recovery:
# it was never a commit, so there is no reflog to go back to. Worktrees are
# private to one session, so they are left alone.
#
# A tree counts as shared when it is the main worktree of a repo that currently
# has at least one other worktree attached, or when it is named explicitly by
# GUARD_SHARED_TREE. That needs no per-machine configuration: a repo nobody
# parallelises is never guarded, and one that grows worktrees is guarded from
# the moment the first one appears.
#
# Runs on every Bash call, so it forks python once and reaches for git only
# after a destructive verb has already matched.
#
# Exit 2 blocks the call and shows stderr to the agent.
set -uo pipefail

# One pass over the payload: which directory would the command run in, and does
# it carry a verb that discards working-tree state?
read -r -d '' _PARSE <<'PY' || true
import json, re, sys

try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)

ti = d.get("tool_input") or {}
cmd = ti.get("command") or d.get("command") or ""
cwd = ti.get("cwd") or d.get("cwd") or ""
if not cmd:
    raise SystemExit(0)

# Match only git in a command position (start, or after ; | newline && || $( ).
# A bare "(" is deliberately not a separator: command text often quotes these
# verbs (editing an allowlist, grepping a log, writing this very file) and that
# must not be blocked.
SEP = r"(?:\A|[;|\n]|&&|\|\||\$\()[ \t]*"
GIT = r"git\s+(?:-C\s+\S+\s+)?"
CHECKS = [
    (GIT + r"checkout\s+--(\s|$)",   "git checkout with -- restores tracked files"),
    (GIT + r"checkout\s+\.(\s|$|/)", "git checkout of . restores every tracked file"),
    (GIT + r"restore(\s|$)",         "git restore discards working-tree changes"),
    (GIT + r"stash(\s|$)",           "git stash removes changes from the tree, including edits made by other sessions"),
    (GIT + r"clean\s+-\S*f",         "git clean with -f deletes untracked files"),
    (GIT + r"reset\s+--hard(\s|$)",  "git reset --hard discards every uncommitted change in the tree"),
]
reason = ""
for pat, msg in CHECKS:
    if re.search(SEP + pat, cmd):
        reason = msg
        break
else:
    m = re.search(SEP + GIT + r"checkout\s+(?!-)(\S+)", cmd)
    if m:
        reason = "PATH:" + m.group(1)
if not reason:
    raise SystemExit(0)

# Which tree would this actually run in? An explicit -C wins, then a `cd` inside
# the command (the payload's cwd is the session's, not the command's), then cwd.
m = re.search(r"git\s+-C\s+(\S+)", cmd) or re.search(
    r"(?:\A|[;|\n]|&&|\|\|)[ \t]*cd\s+(?!-)([^\s;|&]+)", cmd
)
target = m.group(1).strip("\"'") if m else ""
print(target)
print(cwd)
print(reason)
PY

parsed=$(/usr/bin/python3 -c "$_PARSE" 2>/dev/null) || exit 0
[ -z "$parsed" ] && exit 0
target=$(printf '%s' "$parsed" | /usr/bin/sed -n 1p)
cwd=$(printf '%s' "$parsed" | /usr/bin/sed -n 2p)
reason=$(printf '%s' "$parsed" | /usr/bin/sed -n 3p)

[ -z "$cwd" ] && cwd=$PWD
[ -z "$target" ] && target=$cwd
case "$target" in
  /*|"~"*) ;;
  *) target="$cwd/$target" ;;               # a relative cd is relative to cwd
esac
resolve() { ( cd "$1" 2>/dev/null && pwd -P ) || printf '%s' "$1"; }
target=$(resolve "${target/#\~/$HOME}")

# The main worktree of the repo the command targets, and how many trees it has.
list=$(git -C "$target" worktree list --porcelain 2>/dev/null) || exit 0
main_tree=$(printf '%s' "$list" | /usr/bin/sed -n '1s/^worktree //p')
[ -n "$main_tree" ] || exit 0
main_tree=$(resolve "$main_tree")
trees=$(printf '%s' "$list" | /usr/bin/grep -c '^worktree ')

shared=0
[ "$target" = "$main_tree" ] && [ "${trees:-1}" -gt 1 ] && shared=1
if [ -n "${GUARD_SHARED_TREE:-}" ] && [ "$target" = "$(resolve "$GUARD_SHARED_TREE")" ]; then
  shared=1
fi
[ "$shared" = 1 ] || exit 0

deny() {
  printf 'Blocked in the shared checkout %s: %s\n' "$target" "$1" >&2
  printf 'This tree has %s worktrees attached, so other sessions are working in it right now. Discarding working-tree state here destroys their uncommitted edits with nothing to recover from.\n' "$trees" >&2
  printf 'Do this instead: set work aside with a WIP commit on your own branch, work in a private worktree, or revert only the lines you own with an explicit edit.\n' >&2
  exit 2
}

case "$reason" in
  PATH:*)
    arg=${reason#PATH:}
    [ -e "$target/$arg" ] && deny "git checkout of $arg restores a path that exists in the tree"
    ;;
  *) deny "$reason" ;;
esac

exit 0
