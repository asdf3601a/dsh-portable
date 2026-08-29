# dsh-portable

Unofficial **Windows 11 x64** portable packager for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`dsh`).

> **Not affiliated with DeepSeek.** This repo only bundles the official `@deepseek-ai/dsh` npm package with an official Node.js runtime and pnpm so you can unzip and run — no system install, no PATH changes.

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
| `data\cache\` | npm / pnpm caches |

**Nothing is written to `%USERPROFILE%\.dsh`.** Copy the whole folder to move your environment.

### Temp files

`TMP` / `TEMP` are **not** redirected by default. Short-lived temp files use the system temp directory so Windows cleanup can reclaim them.

To keep temps inside the portable folder, uncomment these lines in `dsh.cmd` and create `data\tmp`:

```bat
rem set "TEMP=%ROOT%\data\tmp"
rem set "TMP=%ROOT%\data\tmp"
```

## What gets bundled

- Official Node.js **win-x64** zip (SHA-256 verified from nodejs.org)
- Official `@deepseek-ai/dsh` from npm (unmodified)
- Official **pnpm** Windows binary (for `dsh plugin`)
- Launchers: `dsh.cmd`, `start.cmd`

Native modules are installed on `windows-latest` so the tree is win32-x64.

## Releases follow upstream

When [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) publishes a `dsh-v*` release tag **and** that version is available on npm, GitHub Actions here builds and publishes a matching portable ZIP automatically.

Manual release: Actions → **release** → Run workflow → set `dsh_version`.

## Build locally (Windows)

```powershell
pwsh -File .\scripts\build-windows.ps1 -DshVersion 0.1.1-rc.2
pwsh -File .\scripts\smoke-windows.ps1 -StageDir .\build\stage\dsh-portable
```

Artifacts land in `dist\`.

## License

Packaging scripts: [MIT](LICENSE). Bundled upstream components keep their own licenses — see [NOTICE.txt](packaging/NOTICE.txt) / the shipped `NOTICE.txt`.
