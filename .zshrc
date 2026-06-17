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
# `assume`            — context-aware picker with risk badge ([dev]/[test] green, [beta]/[stg] amber, [prod] red):
#                         · inside a repo → only that repo's SSO-session accounts
#                         · outside a repo → all accounts
# `assume <profile>`  — jump straight to one (any org)
# `assume -a`         — force the full all-accounts picker, even inside a repo
export GRANTED_ALIAS_CONFIGURED=true   # our `assume` function is the alias; stop Granted prompting to install one
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
unalias assume 2>/dev/null   # drop the old alias so re-sourcing this file is safe
assume() {
  local scope
  case "$1" in
    -a|--all) scope=all ;;
    "")       scope=auto ;;
    *)        source assume "$@"; return ;;   # explicit profile or Granted flag (-c …)
  esac

  # parse ~/.aws/config once with awk (no per-profile `aws` subprocess = instant)
  local cfg="${AWS_CONFIG_FILE:-$HOME/.aws/config}" sess="" profiles
  [[ "$scope" == auto && -n "$AWS_PROFILE" ]] && \
    sess=$(awk -v p="$AWS_PROFILE" '
      /^\[profile /{c=$2; sub(/\]$/,"",c)}
      /^[[:space:]]*sso_session[[:space:]]*=/{v=$NF; if(c==p){print v; exit}}' "$cfg")
  profiles=$(awk -v want="$sess" '
    /^\[profile /{c=$2; sub(/\]$/,"",c); o[++n]=c}
    /^[[:space:]]*sso_session[[:space:]]*=/{s[c]=$NF}
    END{for(i=1;i<=n;i++) if(want==""||s[o[i]]==want) print o[i]}' "$cfg")

  local pick
  pick=$(for p in ${(f)profiles}; do printf '%-12s %s\n' "$p" "$(_aws_badge "$p")"; done \
    | fzf --ansi --prompt "${sess:-all} ▸ " --height 40% --reverse) || return   # Esc/Ctrl-C → bail cleanly
  pick=${pick%% *}   # keep only the profile name (strip the badge)
  [[ -n "$pick" ]] && source assume "$pick"
}

# ─── Secrets ──────────────────────────────────────────────────────────────
[ -f "$HOME/.zsh_secrets" ] && source "$HOME/.zsh_secrets"
