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

# ─── Aliases ──────────────────────────────────────────────────────────────
# AWS session switching via Granted: `assume` (fzf picker) / `assume <profile>`
alias assume="source assume"

# ─── Secrets ──────────────────────────────────────────────────────────────
[ -f "$HOME/.zsh_secrets" ] && source "$HOME/.zsh_secrets"
