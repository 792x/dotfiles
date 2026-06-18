#!/usr/bin/env bash
# Symlink dotfiles into $HOME. Safe to re-run.
set -euo pipefail
DOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

link() {
  local src="$DOT/$1" dest="$HOME/$2"
  mkdir -p "$(dirname "$dest")"
  [ -e "$dest" ] && [ ! -L "$dest" ] && mv "$dest" "$dest.bak.$(date +%Y%m%d%H%M%S)"
  ln -sfn "$src" "$dest"
  echo "linked $dest -> $src"
}

link .zshrc        .zshrc
link .zshenv       .zshenv
link .zprofile     .zprofile
link ghostty/config .config/ghostty/config
link config/direnv/direnv.toml .config/direnv/direnv.toml

echo
echo "Done. Create ~/.zsh_secrets for tokens (see README)."
