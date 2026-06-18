# AWS account switching (`assume`)

One command — `assume` — to pick an AWS account and run any CLI/terraform against it.
Replaces juggling per-repo `aws sso login` commands and GUI tools like Leapp.

## Mental model

- **`cd` into a repo** → [direnv](https://direnv.net) reads the repo's `.envrc` and sets
  `AWS_PROFILE`. Every `aws`/terraform/`pnpm iac:*` command in that repo now targets the
  right account automatically. This is the 90% case — you run nothing.
- **`assume`** → interactive [Granted](https://granted.dev) picker for ad-hoc switching.
  It logs in via SSO on demand (only the session you pick) and exports temp creds into the
  current shell, so any command afterward hits that account regardless of directory.

`assume` is **context-aware** (defined as a shell function in `.zshrc`, not the stock Granted alias):

| Invocation | Behaviour |
|---|---|
| `assume` inside a repo | picker scoped to **that repo's SSO session** only |
| `assume` outside a repo | picker over **all** profiles |
| `assume <profile>` | jump straight to one (any org) |
| `assume -a` | force the full all-accounts picker, even inside a repo |
| `assume -c` | open the AWS web console (Granted flag, passed through) |

The picker shows a risk badge after each name — `[dev]`/`[test]` green, `[beta]`/`[stg]`
amber, `[prod]` red — so prod is hard to pick by accident.

## OS dependencies

All via Homebrew. Verify or install:

```sh
brew install awscli                       # AWS CLI v2 — native SSO + [sso-session] support
brew install common-fate/granted/granted  # provides `assume` / `assumego`
brew install direnv                        # per-repo env via .envrc
brew install fzf                           # the picker UI
```

Verify:

```sh
aws --version      # must be aws-cli/2.x  (v1 lacks sso-session token provider)
assumego --help    # Granted core present
direnv --version
fzf --version
awk --version 2>/dev/null || awk 'BEGIN{print "awk ok"}'   # macOS BSD awk is sufficient
```

`.zshrc` wires the last three together:

- `eval "$(direnv hook zsh)"` — direnv hook
- `export GRANTED_ALIAS_CONFIGURED=true` — tells Granted our function *is* the alias, so it
  stops prompting to install one
- the `assume()` / `_aws_badge()` functions in the `── AWS ──` section

No extra config needed beyond installing the four tools and running `install.sh`.

## Per-machine setup (NOT in this repo)

`~/.aws/config` holds account IDs / org-specific data, so it is **not** tracked here. Set it
up once per machine using the modern `[sso-session]` format (one login covers every profile
sharing a session, with refreshable tokens):

```ini
[sso-session myorg]
sso_start_url = https://myorg.awsapps.com/start
sso_region = eu-west-1
sso_registration_scopes = sso:account:access

[profile myorg-dev]
sso_session = myorg
sso_account_id = 111111111111
sso_role_name = AdministratorAccess
region = eu-west-1

[profile myorg-prod]
sso_session = myorg
sso_account_id = 222222222222
sso_role_name = AdministratorAccess
region = eu-west-1
```

> Avoid the legacy inline format (`sso_start_url` repeated in each `[profile]`). It is not
> refreshable and each profile logs in separately. The `[sso-session]` block fixes both and
> is what `assume`'s repo-scoping keys off (it groups profiles by their `sso_session`).

Then per repo:

```sh
echo 'export AWS_PROFILE=myorg-dev' > /path/to/repo/.envrc
direnv allow /path/to/repo
```

`.envrc` files live in each project repo, not here.

## One credential source (Granted `credential_process`)

By default Granted caches SSO tokens in the **macOS Keychain**, while the AWS CLI / SDK /
terraform read `~/.aws/sso/cache/` when resolving an `AWS_PROFILE`. That split means
`assume` can report "logged in" while `AWS_PROFILE=...; terraform/aws/SDK` still sees an
expired token (it's reading a different store).

To unify on Granted as the single source, add a `credential_process` line to **every**
profile so all `AWS_PROFILE`-based tooling pulls creds from Granted (refreshing/logging in
as needed):

```ini
[profile myorg-dev]
credential_process = granted credential-process --profile myorg-dev --auto-login
sso_session = myorg
sso_account_id = 111111111111
sso_role_name = AdministratorAccess
region = eu-west-1
```

`--auto-login` opens the browser to complete SSO when the token is expired, so
`terraform apply` / `pnpm iac:*` self-heal auth instead of failing. Requires `granted` on
`PATH` for whatever launches the tool (fine from a terminal; GUI-launched apps may not have
it). Keep the `sso_session` lines — Granted reads them to know how to fetch creds.

Validate after editing config:

```sh
aws sts get-caller-identity --profile myorg-dev   # 1st run may open the browser, then prints identity
```

Caveats / gotchas:
- A stale `assume` in the same shell exports `AWS_ACCESS_KEY_ID` etc., which **override**
  `credential_process`. If a tool uses old creds, `unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN`
  or open a fresh shell.
- `--auto-login` would hang a non-interactive/CI run waiting for a browser — this setup is for
  local dev only.
- Rollback: every edit keeps a backup at `~/.aws/config.bak-*`.

## How repo-scoping works

`assume` (no args) reads the current `AWS_PROFILE` (set by direnv), looks up its
`sso_session` in `~/.aws/config`, and lists only profiles sharing that session. Parsing is a
single `awk` pass over the config file (no `aws` subprocess per profile) so the picker is
instant. The risk badge is derived from the profile name, so new accounts classify
automatically (`*prod*`→red, `*beta*`/`*stg*`→amber, `*dev*`/`*test*`→green).

## Troubleshooting

- **Granted keeps prompting "Install zsh alias?"** — ensure `GRANTED_ALIAS_CONFIGURED=true`
  is exported (it is, in `.zshrc`) and there is **no** stray `alias assume=...` in
  `~/.zshenv` (Granted writes one if you answer "y" — delete it; answer "n").
- **`defining function based on alias 'assume'` on re-source** — a live `assume` alias exists
  in the current shell. Run `unalias assume` once. `.zshrc` has an `unalias assume 2>/dev/null`
  guard so new shells and re-sources are fine.
- **Picker is slow** — it shouldn't be (awk parse, no subprocesses). Slowness is the actual
  SSO browser login on first use of an expired session, not the picker.
- **Picker shows wrong/all accounts in a repo** — the repo has no `.envrc`, or you didn't
  `direnv allow` it, so `AWS_PROFILE` is unset and scoping falls back to all.
