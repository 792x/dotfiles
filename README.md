# dotfiles

macOS shell + terminal setup: zsh (Oh My Zsh) + Ghostty + VSCode/Claude Code.

## Layout

| File | Linked to | Purpose |
|------|-----------|---------|
| `.zshrc` | `~/.zshrc` | Interactive zsh: OMZ, nvm (lazy+autoload), fzf, direnv, pnpm, aliases |
| `.zshenv` | `~/.zshenv` | Minimal (runs for all shells) |
| `.zprofile` | `~/.zprofile` | Login-shell PATH: Homebrew, JetBrains Toolbox |
| `ghostty/config` | `~/.config/ghostty/config` | Ghostty: JetBrains Fleet theme, JetBrains Mono, translucent |

## Install (new machine)

```sh
git clone <repo-url> ~/.dotfiles
~/.dotfiles/install.sh
```

Prereqs: Homebrew, Oh My Zsh, `fzf`, `direnv`, `nvm`, `pnpm`, `awscli`, Ghostty, VSCode (`code` CLI).

## AWS account switching

`assume` — AWS-native SSO account picker (awscli + direnv + fzf). See
[docs/aws-assume.md](docs/aws-assume.md) for how it works, required tools, and per-machine
`~/.aws/config` / `.envrc` setup.

## Secrets

Tokens live in `~/.zsh_secrets` (git-ignored, `chmod 600`), sourced from `.zshrc`:

```sh
echo 'export GITHUB_AUTH_TOKEN=...' >> ~/.zsh_secrets
chmod 600 ~/.zsh_secrets
```
