dsh-portable (Windows 11 x64)
=============================

Unofficial portable build of DeepSeek Harness (dsh).
Not affiliated with DeepSeek. Bundles official Node.js + @deepseek-ai/dsh + pnpm.

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
  data\cache\        npm / pnpm caches
  data\npmrc         optional npm/pnpm userconfig (copy from npmrc.example)
  data\registry.env  optional KEY=VALUE registry settings (copy from registry.env.example)

These files do NOT go to %USERPROFILE%\.dsh.
Copy the whole folder to another PC / USB drive to take your environment with you.
Prefer NTFS for USB drives that store API keys.

Optional Nexus / npm registry
-----------------------------
By default npm and pnpm use the public registry. To point them at a Sonatype Nexus
npm group/proxy (or any registry):

1. Copy data\npmrc.example to data\npmrc and/or data\registry.env.example to
   data\registry.env, then edit (no spaces around '=').
2. Restart dsh (close the console running start.cmd, then start again).

Precedence: process env (e.g. npm_config_registry) > data\registry.env >
data\npmrc > npm defaults. Use data\npmrc for //host/:_authToken= style auth.
Leave both files absent to keep the default public registry.

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
