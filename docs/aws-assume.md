# AWS account switching (`assume`)

One command — `assume` — to pick an AWS account, log in via SSO if needed, and run any
CLI / terraform / SDK / repo script against it. Pure AWS-native: no extra tools, one token
store.

## Mental model

- **`cd` into a repo** → [direnv](https://direnv.net) reads the repo's `.envrc` and sets
  `AWS_PROFILE`. Every `aws` / terraform / `pnpm iac:*` command in that repo then targets the
  right account automatically. This is the 90% case — you run nothing.
- **`assume`** → fzf picker to switch account in the current shell. It logs in via
  `aws sso login` only if the cached token is missing/expired, then exports `AWS_PROFILE`.

Everything — CLI, terraform, the AWS SDK, repo scripts — resolves credentials the same way:
`AWS_PROFILE` → the SSO token in `~/.aws/sso/cache`. So **one** `assume` (or `aws sso login`)
covers all of them. The token is valid ~8–12h and one login covers every profile sharing the
same `sso_session`.

| Invocation | Behaviour |
|---|---|
| `assume` inside a repo | picker scoped to **that repo's SSO session** only |
| `assume` outside a repo | picker over **all** profiles |
| `assume <profile>` | switch straight to one |
| `assume -a` | force the full all-profiles picker, even inside a repo |

The picker shows a risk badge after each name — `[dev]`/`[test]` green, `[beta]`/`[stg]`
amber, `[prod]` red (derived from the profile name, so new accounts classify automatically).

## OS dependencies

All via Homebrew:

```sh
brew install awscli   # AWS CLI v2 — native SSO + [sso-session] token provider
brew install direnv   # per-repo env via .envrc
brew install fzf      # the picker UI
```

Verify:

```sh
aws --version      # must be aws-cli/2.x (v1 lacks the sso-session token provider)
direnv --version
fzf --version
awk 'BEGIN{print "awk ok"}'   # macOS BSD awk is sufficient
```

`.zshrc` wires it together (the `── AWS ──` section): `eval "$(direnv hook zsh)"` plus the
`assume` / `_aws_badge` / `_aws_session_of` shell functions. No daemon, no keychain, no extra
binary.

> History: an earlier version used [Granted](https://granted.dev) for the picker. It was
> dropped — it cached SSO tokens in the macOS Keychain, a *separate* store from
> `~/.aws/sso/cache`, so `assume` could report "logged in" while terraform/SDK saw an expired
> token. The native CLI does everything needed from one store. `brew uninstall granted` if
> it's still around.

## Per-machine setup (NOT in this repo)

`~/.aws/config` holds account IDs / org-specific data, so it is **not** tracked here. Set it
up once per machine using the `[sso-session]` format (one login covers every profile sharing
a session, with refreshable tokens):

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
>
> Do **not** add `credential_process` to SSO profiles — the CLI prioritises `sso_session` and
> ignores it, and it only adds a second credential path to go wrong.

Then per repo:

```sh
echo 'export AWS_PROFILE=myorg-dev' > /path/to/repo/.envrc
direnv allow /path/to/repo
```

`.envrc` files live in each project repo, not here.

## How it works

1. **Picker** — `assume` (no args) reads the current `AWS_PROFILE` (set by direnv), finds its
   `sso_session`, and lists only profiles sharing that session. Parsing is a single `awk`
   pass over `~/.aws/config` (no subprocess per profile) so it's instant.
2. **Login if needed** — after picking, it clears any stale `AWS_*` creds, sets
   `AWS_PROFILE`, and runs `aws sts get-caller-identity`. Only if that fails does it
   `aws sso login --sso-session <session>` (browser).
3. **Done** — `AWS_PROFILE` is set in the shell; everything reads `~/.aws/sso/cache`.

## Troubleshooting

- **Repo script says token expired** — your SSO token lapsed. `assume <profile>` (or
  `aws sso login --sso-session <session>`) refreshes it; one login covers the whole session.
- **Picker shows all accounts inside a repo** — the repo has no `.envrc`, or you didn't
  `direnv allow` it, so `AWS_PROFILE` is unset and scoping falls back to all.
- **A tool ignores `AWS_PROFILE`** — stale exported creds in the shell. `assume` unsets them,
  but if set by something else: `unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN`.
- **Need raw env creds** (for a tool that can't do SSO): `aws configure export-credentials
  --profile X --format env`.
