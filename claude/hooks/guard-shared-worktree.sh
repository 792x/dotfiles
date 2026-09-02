#!/usr/bin/env bash
# PreToolUse(Bash) guard for a shared checkout.
#
# ~/Code/<repo> is opened by several Claude sessions at once. Any git command
# that restores or discards working-tree state there destroys another session's
# uncommitted work with no warning and no recovery (it is not a commit, so there
# is no reflog to go back to). Per-task worktrees under ~/Code/wt are private, so
# they are left alone.
#
# Exit 2 blocks the call and shows stderr to the agent.
set -uo pipefail

SHARED=${GUARD_SHARED_TREE:-$HOME/Code/<repo>}

input=$(cat)
parse() { printf '%s' "$input" | /usr/bin/python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: raise SystemExit(0)
print((d.get("tool_input") or {}).get(sys.argv[1]) or d.get(sys.argv[1]) or "")' "$1" 2>/dev/null; }

cmd=$(parse command)
cwd=$(parse cwd)
[ -z "$cwd" ] && cwd=$PWD
[ -z "$cmd" ] && exit 0

# Which tree would this actually run in? An explicit -C wins, then a `cd` inside
# the command (the payload's cwd is the session's, not the command's), then cwd.
target=$(printf '%s' "$cmd" | /usr/bin/python3 -c '
import re, sys
cmd = sys.stdin.read()
m = re.search(r"git\s+-C\s+(\S+)", cmd)
if not m:
    m = re.search(r"(?:\A|[;|\n]|&&|\|\|)[ \t]*cd\s+(?!-)([^\s;|&]+)", cmd)
print(m.group(1).strip("\"") if m else "")
' 2>/dev/null)
[ -z "$target" ] && target=$cwd

resolve() { ( cd "$1" 2>/dev/null && pwd -P ) || printf '%s' "$1"; }
case "$target" in
  /*|"~"*) ;;
  *) target="$cwd/$target" ;;                 # a relative cd is relative to cwd
esac
target=$(resolve "${target/#\~/$HOME}")
shared=$(resolve "$SHARED")

# Only the shared checkout itself, not worktrees that merely share its history.
[ "$target" = "$shared" ] || exit 0

deny() {
  printf 'Blocked in the shared checkout %s: %s\n' "$shared" "$1" >&2
  printf 'Several Claude sessions work in this tree at once, so discarding working-tree state here destroys their uncommitted edits with nothing to recover from.\n' >&2
  printf 'Do this instead: work in a private worktree (`wt <ticket>`, which lands in ~/Code/wt/), or revert only the lines you own with an explicit edit.\n' >&2
  exit 2
}

# Match only git in a command position (start, or after ; | newline && || $( ).
# A bare "(" is deliberately not a separator: command text often quotes these
# verbs (editing an allowlist, grepping a log, writing this very file) and that
# must not be blocked.
reason=$(printf '%s' "$cmd" | /usr/bin/python3 -c '
import re, sys
cmd = sys.stdin.read()
SEP = r"(?:\A|[;|\n]|&&|\|\||\$\()[ \t]*"
GIT = r"git\s+(?:-C\s+\S+\s+)?"
checks = [
    (GIT + r"checkout\s+--(\s|$)",    "git checkout with -- restores tracked files"),
    (GIT + r"checkout\s+\.(\s|$|/)",  "git checkout of . restores every tracked file"),
    (GIT + r"restore(\s|$)",          "git restore discards working-tree changes"),
    (GIT + r"stash(\s|$)",            "git stash removes changes from the tree, including edits made by other sessions"),
    (GIT + r"clean\s+-\S*f",          "git clean with -f deletes untracked files"),
    (GIT + r"reset\s+--hard(\s|$)",   "git reset --hard discards every uncommitted change in the tree"),
]
for pat, msg in checks:
    if re.search(SEP + pat, cmd):
        print(msg)
        break
else:
    m = re.search(SEP + GIT + r"checkout\s+(?!-)(\S+)", cmd)
    if m:
        print("PATH:" + m.group(1))
' 2>/dev/null)

case "$reason" in
  "") ;;
  PATH:*)
    arg=${reason#PATH:}
    [ -e "$shared/$arg" ] && deny "git checkout of $arg restores a path that exists in the tree"
    ;;
  *) deny "$reason" ;;
esac

exit 0
