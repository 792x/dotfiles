# ~/.zshrc — interactive zsh config
# Layout: Oh My Zsh → PATH/env → tools → aliases → secrets
# (Login-shell env like brew/Toolbox PATH lives in ~/.zprofile)

# ─── Oh My Zsh ────────────────────────────────────────────────────────────
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="eastwood"

plugins=(git nvm)

# nvm via OMZ plugin: lazy-load (fast startup) + auto-switch on .nvmrc/.node-version
zstyle ':omz:plugins:nvm' lazy yes
zstyle ':omz:plugins:nvm' autoload yes

source "$ZSH/oh-my-zsh.sh"

# ─── Environment ──────────────────────────────────────────────────────────
export EDITOR="code --wait"   # git commits, `kubectl edit`, etc. open in VSCode

# pnpm
export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# ─── Completions ──────────────────────────────────────────────────────────
# Docker CLI completions
fpath=("$HOME/.docker/completions" $fpath)
autoload -Uz compinit
compinit

# ─── Tools ────────────────────────────────────────────────────────────────
source <(fzf --zsh)            # fzf keybindings + history search (Ctrl-R)
eval "$(direnv hook zsh)"      # per-repo .envrc (sets AWS_PROFILE, etc.)

# ─── AWS ────────────────────────────────────────────────────────────────────
# `assume`            — pick an AWS profile (fzf, risk-badged), log in via SSO if
#                       needed, and set AWS_PROFILE for the shell. One token store
#                       (~/.aws/sso/cache) used by CLI + terraform + SDK + repo scripts.
#                         · inside a repo → picker scoped to that repo's SSO session
#                         · outside a repo → all profiles
# `assume <profile>`  — jump straight to one
# `assume -a`         — force the full all-profiles picker, even inside a repo
_aws_badge() {   # colored [env] badge per profile risk
  case "$1" in
    *prod*)       printf '\033[31m[prod]\033[0m' ;;  # red
    *beta*)       printf '\033[33m[beta]\033[0m' ;;  # amber
    *stg*|*stag*) printf '\033[33m[stg]\033[0m'  ;;  # amber
    *test*|*tst*) printf '\033[32m[test]\033[0m' ;;  # green
    *dev*)        printf '\033[32m[dev]\033[0m'  ;;  # green
    *)            printf '\033[2m[?]\033[0m'     ;;  # dim
  esac
}
_aws_session_of() {   # echo the sso_session of a profile (empty if none)
  awk -v p="$1" '
    /^\[profile /{c=$2; sub(/\]$/,"",c)}
    /^[[:space:]]*sso_session[[:space:]]*=/{if(c==p){print $NF; exit}}' "${AWS_CONFIG_FILE:-$HOME/.aws/config}"
}
assume() {
  local cfg="${AWS_CONFIG_FILE:-$HOME/.aws/config}" pick scope sess
  case "$1" in
    -a|--all) scope=all ;;
    "")       scope=auto ;;
    *)        pick="$1" ;;   # explicit profile name
  esac

  if [[ -z "$pick" ]]; then
    local cursess="" profiles
    [[ "$scope" == auto && -n "$AWS_PROFILE" ]] && cursess=$(_aws_session_of "$AWS_PROFILE")
    profiles=$(awk -v want="$cursess" '
      /^\[profile /{c=$2; sub(/\]$/,"",c); o[++n]=c}
      /^[[:space:]]*sso_session[[:space:]]*=/{s[c]=$NF}
      END{for(i=1;i<=n;i++) if(want==""||s[o[i]]==want) print o[i]}' "$cfg")
    pick=$(for p in ${(f)profiles}; do printf '%-12s %s\n' "$p" "$(_aws_badge "$p")"; done \
      | fzf --ansi --prompt "${cursess:-all} ▸ " --height 40% --reverse) || return   # Esc/Ctrl-C → bail
    pick=${pick%% *}   # strip the badge, keep the profile name
  fi
  [[ -z "$pick" ]] && return

  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN   # let AWS_PROFILE win
  export AWS_PROFILE="$pick"

  if ! aws sts get-caller-identity >/dev/null 2>&1; then            # only log in if token missing/expired
    sess=$(_aws_session_of "$pick")
    if [[ -n "$sess" ]]; then aws sso login --sso-session "$sess"; else aws sso login --profile "$pick"; fi
  fi
  aws sts get-caller-identity --query Account --output text 2>/dev/null \
    | sed "s/.*/✔ AWS_PROFILE=$pick (account &)/"
}

# Right-prompt segment: active AWS profile + SSO token state.
# Reads expiresAt from the session's cache file (sha1(session).json) — no network.
# green `aws:<profile>` = valid token; red `aws:<profile> ✗` = expired / not logged in.
_aws_prompt() {
  [[ -n "$AWS_PROFILE" ]] || return
  local sess hash f body exp now
  sess=$(_aws_session_of "$AWS_PROFILE")
  if [[ -n "$sess" ]]; then
    hash=$(printf '%s' "$sess" | shasum | cut -c1-40)
    f="$HOME/.aws/sso/cache/$hash.json"
    [[ -r "$f" ]] && body=$(<"$f") && \
      [[ "$body" =~ '"expiresAt":[[:space:]]*"([0-9T:Z-]+)"' ]] && exp=$match[1]
  fi
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if [[ -n "$exp" && "$exp" > "$now" ]]; then
    print -n "%F{green}aws:${AWS_PROFILE}%f"
  else
    print -n "%F{red}aws:${AWS_PROFILE} ✗%f"
  fi
}
setopt prompt_subst
RPROMPT='$(_aws_prompt)'

# ─── Secrets ──────────────────────────────────────────────────────────────
[ -f "$HOME/.zsh_secrets" ] && source "$HOME/.zsh_secrets"
