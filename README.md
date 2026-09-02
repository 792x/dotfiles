# dotfiles

macOS shell + terminal setup: zsh (Oh My Zsh) + Ghostty + VSCode/Claude Code.

## Layout

| File | Linked to | Purpose |
|------|-----------|---------|
| `.zshrc` | `~/.zshrc` | Interactive zsh: OMZ, nvm (lazy+autoload), fzf, direnv, pnpm, aliases |
| `.zshenv` | `~/.zshenv` | Minimal (runs for all shells) |
| `.zprofile` | `~/.zprofile` | Login-shell PATH: Homebrew, JetBrains Toolbox |
| `ghostty/config` | `~/.config/ghostty/config` | Ghostty: JetBrains Fleet theme, JetBrains Mono, translucent |
| `config/direnv/direnv.toml` | `~/.config/direnv/direnv.toml` | direnv: trust `.envrc` under `~/Code` (no per-change `allow`) |
| `zsh/*.zsh` | sourced by `.zshrc` | Shell tools: `wt` (worktree per task), `ck` (turbo summary), `assume` completion |
| `claude/statusline.sh` | `~/.claude/statusline.sh` | Claude Code statusline: repo, branch, worktree, AWS profile, terraform stage |
| `claude/hooks/guard-shared-worktree.sh` | `~/.claude/hooks/` | Blocks git commands that discard a shared checkout's uncommitted work |

## What belongs here

This repo is public and every machine clones all of it, so a work machine's
client detail would land on a personal machine and in a public commit. The rule
is one line: **tracked files may name a tool, never a project.** No client or
employer name, repo path, ticket prefix, package scope, deploy stage, account
id, hostname or internal script name.

Anything that names one of those goes in the overlay instead:

```
~/.config/zsh.local/*.zsh     # sourced last by .zshrc, untracked, per machine
```

Point `ZSH_LOCAL_DIR` elsewhere to move it, and make it a private git repo if
you want the work machine's helpers backed up. The tools that stay here take
their project-specific parts as variables: `WT_ROOT`, `WT_BRANCH_PREFIX`,
`WT_CARRY`, `GUARD_SHARED_TREE`. Set those in the overlay.

A project's own agent config (hooks, `launch.json`, `CLAUDE.md`, permissions)
belongs in that project's repo, not here. It travels with the code it describes
and inherits that repo's access control.

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
