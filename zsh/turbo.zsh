# ck: run a turbo task and end with the short list of what failed.
# turbo's output is long and the useful part is which task failed. Keep the
# stream (you want to watch it) but end with the short list.
ck() {
  local log rc
  log=$(mktemp -t ck)
  setopt local_options pipe_fail
  local -a target; target=(${@:-check:affected})   # ck / ck check:pkg <pkg> / ck lint
  pnpm run $target 2>&1 | tee "$log"
  rc=$?
  if (( rc )); then
    # turbo prefixes streamed output with "<pkg>:<task>: " and closes a broken
    # one with "command finished with error"; older/summary output uses pkg#task.
    # turbo keeps colouring even when piped, so strip escapes before parsing
    local plain=$(mktemp -t ckplain)
    sed -E $'s/\x1b\\[[0-9;]*[A-Za-z]//g' "$log" > "$plain"
    local -a failed
    failed=(${(f)"$(grep -E ': *command finished with error' "$plain" \
      | sed -E 's/: *command finished with error.*//' | sort -u)"})
    (( ${#failed} )) || failed=(${(f)"$(grep -oE '[@A-Za-z0-9/._-]+#[A-Za-z0-9:._-]+' "$plain" | sort -u)"})
    print -r -- ""
    print -r -- "── failed ──────────────────────────────────────"
    if (( ${#failed} )); then
      local t first
      for t in $failed; do
        print -r -- "  $t"
        first=$(grep -F -- "$t" "$plain" | grep -iE 'error|✗|FAIL' \
          | grep -v 'command finished with error' | head -1)
        [[ -n "$first" ]] && print -r -- "      ${${first#$t: }##[[:space:]]#}"
      done
    else
      print -r -- "  (no task markers in the output, see the log)"
    fi
    print -r -- "full log: $log"
    rm -f "$plain"
  else
    rm -f "$log"
  fi
  return $rc
}

