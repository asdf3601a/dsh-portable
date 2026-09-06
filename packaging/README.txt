dsh-portable (Windows 11 x64)
=============================

Unofficial portable build of DeepSeek Harness (dsh).
Not affiliated with DeepSeek. Bundles official Node.js + @deepseek-ai/dsh + pnpm
+ Git for Windows Portable.

Quick start
-----------
1. Unzip anywhere (prefer a short path, e.g. C:\dsh-portable).
2. Double-click start.cmd
3. Open the Web UI (default http://127.0.0.1:3080) and add your API key.

CLI
---
  dsh.cmd --version
  dsh.cmd web
  dsh.cmd web --port 8080
  dsh.cmd web --no-open
  dsh.cmd plugin --profile web list

Portable data (stays in this folder)
------------------------------------
  data\dsh-home\     settings, credentials, sessions, plugins  (DSH_HOME)
  data\workspace\    default working directory
  data\cache\        npm, pnpm, and runtime native addon caches
  data\portable.env  feature switches (shell, proxy, npm registry)
  data\npmrc         optional legacy npm/pnpm userconfig (multi-registry)

These files do NOT go to %USERPROFILE%\.dsh.
Copy the whole folder to another PC / USB drive to take your environment with you.
Prefer NTFS for USB drives that store API keys.

Edit data\portable.env (KEY=value, no spaces around '='), then restart start.cmd.
Standard parent variables win; use DSH_SHELL=pwsh or DSH_SHELL=bash to
override the shell from the parent console.

Git and shell
-------------
Bundled Git is always first on PATH (runtime\git\cmd\git.exe). System Git is
not used unless you remove the bundled copy.

The agent shell defaults to pwsh. To use Git Bash instead, set:

  SHELL=bash

For a one-session parent override, set DSH_SHELL=bash before launching.

All built-in agent presets follow this switch, including minimal's persistent
shell. Packaging adjusts shell plugin settings in place and keeps the original
names, IDs, order, and standard default. No Portable profile is added, and
custom presets are not edited.

Git Bash can fail inside dsh's Windows restricted-token sandbox with
"couldn't create signal pipe, Win32 error 5". Use PowerShell for sandboxed
sessions. The shell switch does not change permission settings.

Git config is data\dsh-home\gitconfig. SSH keys still come from
%USERPROFILE%\.ssh unless you set HOME yourself.

To open Git Bash: runtime\git\git-bash.exe

HTTP(S) / SOCKS proxy
---------------------
  PROXY=http://proxy.example.com:8080

PROXY fills HTTP_PROXY and HTTPS_PROXY when those keys are omitted.
ALL_PROXY=socks5://host:port is for git and Git Bash curl only; Node and
npm/pnpm do not honor SOCKS. When an HTTP(S) proxy is set, loopback is
bypassed unless you set NO_PROXY yourself.

Corporate MITM CA:

  NODE_EXTRA_CA_CERTS=data\certs\corp.pem

Optional Nexus / npm registry
-----------------------------
By default npm and pnpm use the public registry. For a single private registry:

  NPM_REGISTRY=https://nexus.example.com/repository/npm-group/
  NPM_ALWAYS_AUTH=true
  NPM_AUTH_TOKEN=YOUR_TOKEN_HERE

Precedence: process env (e.g. npm_config_registry) > data\npmrc if present >
portable.env NPM_* > npm defaults. Keep data\npmrc only for multiple registries.

Temp files
----------
By default TMP/TEMP use the system temp directory so Windows disk cleanup can
reclaim short-lived files (and USB drives are not filled with temp junk).

To keep temp files inside this folder instead, edit dsh.cmd and uncomment:

  rem set "TEMP=%ROOT%\data\tmp"
  rem set "TMP=%ROOT%\data\tmp"

then create data\tmp yourself.

Upgrade
-------
1. Quit dsh (close the console running start.cmd).
2. Unzip the new release to a new folder.
3. Copy your old data\ directory over the new data\ directory.
4. Run start.cmd from the new folder.

SmartScreen
-----------
Builds are unsigned. If Windows warns on first run: More info → Run anyway.

First launch
------------
First start may need network while dsh initializes the web profile.
Core packages are already inside this ZIP.

More info: see the repository README and NOTICE.txt.
