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
| `data\npmrc` | Optional npm/pnpm userconfig (copy from `npmrc.example`) |
| `data\portable.env` | Feature switches (`SHELL=pwsh` or `SHELL=bash`) |

**Nothing is written to `%USERPROFILE%\.dsh`.** Copy the whole folder to move your environment.

### Optional Nexus / npm registry

By default npm and pnpm use the public registry. To use a Sonatype Nexus npm group/proxy (or any registry) at runtime:

1. Copy `data\npmrc.example` → `data\npmrc`, then edit (no spaces around `=`).
2. Restart `dsh` / `start.cmd`.

Precedence: process env (for example `npm_config_registry`) → `data\npmrc` → npm defaults. Put `//host/:_authToken=` style auth in `data\npmrc`. Secrets in `data\` travel with the portable folder; leave the file absent to keep the public registry.

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

### pwsh vs Git Bash

The agent shell defaults to **pwsh** (upstream Windows behavior). To use bundled Git Bash instead, edit `data\portable.env`:

```
SHELL=bash
```

Restart `start.cmd`. Bundled `git.exe` stays first on PATH in both modes. Git identity is stored in `data\dsh-home\gitconfig`, not `%USERPROFILE%\.gitconfig`. SSH still uses your existing `%USERPROFILE%\.ssh` keys unless you set `HOME` yourself. Git Credential Manager uses the Windows Credential Manager.

A Git Bash window is `runtime\git\git-bash.exe`.

## Releases follow upstream

When [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) publishes a `dsh-v*` release tag (e.g. `dsh-v0.1.2-alpha.1` / title `v0.1.2-alpha.1`), GitHub Actions here builds and publishes a matching portable ZIP automatically — **no need to wait for npm**.

If `@deepseek-ai/dsh@<ver>` is on the registry, the build uses it; otherwise it clones the Git tag, runs `pnpm run build:official` + official `release:pack` (dsh + vendor), then installs the packed tarballs into `app/`.

Manual release: Actions → **release** → Run workflow → set `dsh_version` (e.g. `0.1.2-alpha.1`).

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
