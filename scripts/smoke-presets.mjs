// Loaded only by smoke-windows.ps1 through the packaged dsh launcher.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { join, resolve } from 'node:path';

export const name = 'portable-preset-smoke';
export const inject = ['appReady', 'appExit', 'agentPresets', 'agents', 'tools', 'shell', 'loader', 'permissionPresets'];

export function apply(ctx, config) {
  ctx.effect(() => ctx.appReady.onReady(() => {
    const timeout = setTimeout(() => {
      console.error('preset smoke timed out');
      ctx.appExit(1);
    }, 120_000);
    run(ctx, config.permissionMode).then(() => {
      console.log(`DSH_PRESET_SMOKE_OK ${process.env.DSH_SHELL}`);
      ctx.appExit(0);
    }, error => {
      console.error(error);
      ctx.appExit(1);
    }).finally(() => clearTimeout(timeout));
  }));
}

async function run(ctx, permissionMode) {
  const shell = process.env.DSH_SHELL;
  assert.ok(shell === 'bash' || shell === 'pwsh');
  const ids = ['cordis', 'minimal', 'ptc', 'standard'];
  assert.deepEqual((await ctx.agentPresets.list()).map(preset => preset.id).sort(), ids);
  assert.equal(ctx.agentPresets.defaultId, 'standard');
  for (const dialect of ['bash', 'pwsh']) {
    const entries = [...ctx.loader.entries()].filter(entry => entry.options.id === `${dialect}-sandbox`);
    assert.equal(entries.length, 1);
    assert.equal(entries[0].disabled, dialect !== shell);
    assert.equal(Boolean(entries[0].fiber), dialect === shell);
  }

  for (const id of ids) {
    const preset = await ctx.agentPresets.resolve(id);
    assert.equal(resolve(preset.path), join(process.env.DSH_PORTABLE_ROOT,
      'app', 'node_modules', '@deepseek-ai', 'dsh-agent-presets', 'presets', id, 'agent.cordis.yml'));
    const handle = await ctx.agents.create({
      sessionId: `portable-smoke-${randomUUID()}`,
      meta: { cwd: process.cwd(), agentPreset: id },
      setup: agentCtx => ctx.agentPresets.mount(agentCtx, id).then(() => undefined),
    });
    try {
      // ponytail: default probes isolate shell selection from Windows/MSYS pipe restrictions;
      // use -ShellPermissionMode workspace-write to exercise that upstream sandbox boundary.
      ctx.permissionPresets.set(handle.agent.session, permissionMode);
      const names = ctx.tools.schemas(handle.agent).map(tool => tool.name);
      assert.deepEqual(names.filter(name => name === 'bash' || name === 'pwsh'), [shell], id);
      const execute = async command => {
        const args = id === 'minimal' ? { command } : { command, description: 'Check portable shell execution' };
        const result = await ctx.tools.execute({
          callId: `portable-smoke-${randomUUID()}`,
          name: id === 'ptc' ? 'run_code' : shell,
          arguments: id === 'ptc'
            ? { code: `return await tools.${shell}(${JSON.stringify(args)});`, description: args.description }
            : args,
          agent: handle.agent,
          signal: AbortSignal.timeout(30_000),
        });
        assert.equal(result.isError, false, JSON.stringify(result));
        if (id !== 'minimal') {
          const value = id === 'ptc' ? result.value.result : result.value;
          assert.equal(value.exitCode, 0, JSON.stringify(result));
          return value.stdout.text;
        }
        return result.content.filter(block => block.type === 'text').map(block => block.text).join('\n');
      };
      const output = await execute(shell === 'bash'
        ? 'test -n "$BASH_VERSION" && echo DSH_SHELL_SMOKE_OK'
        : "if (-not $PSVersionTable.PSVersion) { throw 'Expected PowerShell' }; Write-Output 'DSH_SHELL_SMOKE_OK'");
      assert.match(output, /DSH_SHELL_SMOKE_OK/);
      if (id === 'minimal') {
        await execute(shell === 'bash'
          ? 'export DSH_PORTABLE_SMOKE_STATE=retained'
          : "$env:DSH_PORTABLE_SMOKE_STATE='retained'");
        const retained = await execute(shell === 'bash'
          ? 'echo "$DSH_PORTABLE_SMOKE_STATE"'
          : 'Write-Output $env:DSH_PORTABLE_SMOKE_STATE');
        assert.match(retained.trim(), shell === 'bash'
          ? /^retained(?:\r?\n\[Command finished with exit code 0\])?$/
          : /^retained$/);
      }
      console.log(`    ${id}: ${shell} tool executed${id === 'minimal' ? ', state retained' : ''}`);
    } finally {
      await handle.dispose();
    }
  }
}
