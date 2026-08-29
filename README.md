# dsh-portable

Unofficial **Windows 11 x64** portable packager for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`dsh`).

> **Not affiliated with DeepSeek.** This repo only bundles the official `@deepseek-ai/dsh` npm package with an official Node.js runtime, pnpm, and Git for Windows Portable so you can unzip and run — no system install, no PATH changes.

## Download

Grab the latest `dsh-portable-*-win-x64.zip` from [Releases](../../releases).

1. Unzip (prefer a short path such as `C:\dsh-portable`)
2. Double-click **`start.cmd`**
3. Use the Web UI at `http://127.0.0.1:3080` and add your API key

CLI from the same folder:

```bat
dsh.cmd --version
dsh.cmd web
dsh.cmd plugin --profile web list
```

## Portable data

Persistent state stays inside the folder under `data\`:

| Path | Purpose |
|------|---------|
| `data\dsh-home\` | `DSH_HOME` — settings, credentials, sessions, plugins |
| `data\workspace\` | Default cwd when launching |
| `data\cache\` | npm, pnpm, and runtime native addon caches |
| `data\portable.env` | Feature switches (shell, proxy, npm registry) |
| `data\npmrc` | Optional legacy npm/pnpm userconfig (advanced / multi-registry) |

**Nothing is written to `%USERPROFILE%\.dsh`.** Copy the whole folder to move your environment.

Edit `data\portable.env` (`KEY=value`, no spaces around `=`), then restart `start.cmd` / `dsh.cmd`. A parent process environment variable already set wins over this file.

### Shell

The agent shell defaults to **pwsh** (upstream Windows behavior). To use bundled Git Bash instead:

```
SHELL=bash
```

Bundled `git.exe` stays first on PATH in both modes. Git identity is stored in `data\dsh-home\gitconfig`, not `%USERPROFILE%\.gitconfig`. SSH still uses your existing `%USERPROFILE%\.ssh` keys unless you set `HOME` yourself. Git Credential Manager uses the Windows Credential Manager.

A Git Bash window is `runtime\git\git-bash.exe`.

### HTTP(S) / SOCKS proxy

```
PROXY=http://proxy.example.com:8080
```

`PROXY` sets both `HTTP_PROXY` and `HTTPS_PROXY` when those keys are omitted. You can set `HTTP_PROXY` / `HTTPS_PROXY` separately instead. `ALL_PROXY=socks5://127.0.0.1:1080` is for git and Git Bash curl only.

When an HTTP(S) proxy is set, the launcher turns on Node's `NODE_USE_ENV_PROXY` and, if you did not set `NO_PROXY`, bypasses `localhost,127.0.0.1,::1` so the local Web UI is not sent through the proxy.

| Client | HTTP(S) proxy | SOCKS |
|--------|---------------|-------|
| Node (`fetch` / `http(s)`, including LLM and plugin downloads) | yes | no |
| npm / pnpm | yes | no |
| Git | yes | yes |
| Git Bash curl | yes | yes |

dsh `web_fetch` uses a pinned-DNS agent and does not use this proxy (upstream SSRF control). SOCKS will not carry dsh's own HTTPS; put an HTTP proxy in front, or set `PROXY` to that HTTP endpoint.

Passwords should avoid cmd-special characters (`%` `&` `^` `!`). To inject those, set `HTTP_PROXY` in the parent console before launching.

Corporate TLS interception: `NODE_EXTRA_CA_CERTS=data\certs\corp.pem` (path relative to the portable root, or absolute).

### Optional Nexus / npm registry

By default npm and pnpm use the public registry. To use a Sonatype Nexus npm group (or any single registry):

```
NPM_REGISTRY=https://nexus.example.com/repository/npm-group/
NPM_ALWAYS_AUTH=true
NPM_AUTH_TOKEN=YOUR_TOKEN_HERE
```

The launcher writes `data\cache\generated.npmrc` from the token (not an editable user file). Restart `dsh` / `start.cmd`.

Precedence: process env (for example `npm_config_registry`) → `data\npmrc` if that file exists → `portable.env` `NPM_*` → npm defaults. Keep `data\npmrc` only for multiple registries or `//host/:_authToken=` lines you do not want in `portable.env`. Secrets in `data\` travel with the portable folder.

### Temp files

`TMP` / `TEMP` are **not** redirected by default. Short-lived temp files use the system temp directory so Windows cleanup can reclaim them.

To keep temps inside the portable folder, uncomment these lines in `dsh.cmd` and create `data\tmp`:

```bat
rem set "TEMP=%ROOT%\data\tmp"
rem set "TMP=%ROOT%\data\tmp"
```

## What gets bundled

- Official Node.js **win-x64** zip (SHA-256 verified from nodejs.org)
- Official DeepSeek Harness from Git tag `dsh-v*` via upstream `release:pack` (or npm when that version is already published)
- Official **pnpm** Windows binary (for `dsh plugin`)
- Official **Git for Windows Portable** x64 (SHA-256 verified). `git` on PATH is this copy, not a system Git.
- Launchers: `dsh.cmd`, `start.cmd`

Native modules are installed on `windows-latest` so the tree is win32-x64.

## Releases follow upstream

Every Wednesday, GitHub Actions here builds a portable ZIP for the **latest** `dsh-v*` GitHub Release on [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) (e.g. `dsh-v0.1.2-alpha.1` / title `v0.1.2-alpha.1`) — **no need to wait for npm**. Older unpublished tags are not backfilled.

If `@deepseek-ai/dsh@<ver>` is on the registry, the build uses it; otherwise it clones the Git tag, runs `pnpm run build:official` + official `release:pack` (dsh + vendor), then installs the packed tarballs into `app/`.

Manual: Actions → **watch-upstream** (latest only) or **release** → Run workflow → set `dsh_version` (e.g. `0.1.2-alpha.1`) for a specific version.

## Build locally (Windows)

```powershell
# Force git-tag pack (needed when the version is not on npm yet)
powershell -ExecutionPolicy Bypass -File .\scripts\build-windows.ps1 -DshVersion 0.1.2-alpha.1 -Source git

powershell -ExecutionPolicy Bypass -File .\scripts\smoke-windows.ps1 `
  -StageDir .\build\win-x64\dsh-portable -ExpectedDshVersion 0.1.2-alpha.1
```

Artifacts land in `dist\`. The git-pack path requires **git** on PATH.

## License

Packaging scripts: [MIT](LICENSE). Bundled upstream components keep their own licenses — see [NOTICE.txt](packaging/NOTICE.txt) / the shipped `NOTICE.txt`.
