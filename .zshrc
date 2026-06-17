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
# `assume`            — context-aware picker with risk tags (🟢 dev/test, 🟡 beta/stg, 🔴 prod):
#                         · inside a repo → only that repo's SSO-session accounts
#                         · outside a repo → all accounts
# `assume <profile>`  — jump straight to one (any org)
# `assume -a`         — force the full all-accounts picker, even inside a repo
_aws_risk() {   # risk tag per profile name
  case "$1" in
    *prod*)              echo "🔴" ;;
    *beta*|*stg*|*stag*) echo "🟡" ;;
    *dev*|*test*|*tst*)  echo "🟢" ;;
    *)                   echo "⚪️" ;;
  esac
}
assume() {
  local scope
  case "$1" in
    -a|--all) scope=all ;;
    "")       scope=auto ;;
    *)        source assume "$@"; return ;;   # explicit profile or Granted flag (-c …)
  esac

  local sess profiles
  [[ "$scope" == auto && -n "$AWS_PROFILE" ]] && \
    sess=$(aws configure get sso_session --profile "$AWS_PROFILE" 2>/dev/null)
  if [[ -n "$sess" ]]; then
    profiles=$(for p in $(aws configure list-profiles); do
      [[ "$(aws configure get sso_session --profile "$p" 2>/dev/null)" == "$sess" ]] && echo "$p"
    done)
  else
    profiles=$(aws configure list-profiles)
  fi

  local pick
  pick=$(for p in ${(f)profiles}; do printf '%s  %s\n' "$(_aws_risk "$p")" "$p"; done \
    | fzf --prompt "${sess:-all} ▸ " --height 40% --reverse \
          --header '🟢 low risk   🟡 medium   🔴 high (prod)' \
    | awk '{print $NF}')
  [[ -n "$pick" ]] && source assume "$pick"
}

# ─── Secrets ──────────────────────────────────────────────────────────────
[ -f "$HOME/.zsh_secrets" ] && source "$HOME/.zsh_secrets"
