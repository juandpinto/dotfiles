// Inspect real Pi resource loading over RPC, without sending a model prompt.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir, homedir } from 'node:os';
import { join } from 'node:path';

const cwd = mkdtempSync(join(tmpdir(), 'pi-linux-resource-audit-'));
const child = spawn('pi', ['--offline', '--mode', 'rpc', '--no-session', '--no-context-files', '--no-mcp'], {
  cwd,
  env: { ...process.env, PI_OFFLINE: '1' },
  stdio: ['pipe', 'pipe', 'pipe'],
});
let buffer = '';
let stderr = '';
const records = [];
const received = new Set();
child.stderr.on('data', data => { stderr += data.toString(); });
child.stdout.on('data', data => {
  buffer += data.toString();
  while (buffer.includes('\n')) {
    const end = buffer.indexOf('\n');
    const line = buffer.slice(0, end).replace(/\r$/, '');
    buffer = buffer.slice(end + 1);
    if (!line) continue;
    const record = JSON.parse(line);
    records.push(record);
    if (record.type === 'response' && ['state', 'commands'].includes(record.id)) {
      received.add(record.id);
      if (received.size === 2) child.stdin.end();
    }
  }
});
child.stdin.write('{"id":"state","type":"get_state"}\n');
child.stdin.write('{"id":"commands","type":"get_commands"}\n');
const code = await new Promise((resolve, reject) => {
  child.on('error', reject);
  child.on('exit', resolve);
});
assert.equal(code, 0, stderr);
assert.equal(received.size, 2);
const commands = records.find(r => r.id === 'commands').data.commands;
const names = commands.map(c => c.name);
for (const name of ['lookback', 'rewind', 'skill:python', 'skill:documentation', 'skill:grill-me',
  'skill:mh-wiki', 'skill:personal-wiki', 'skill:officecli', 'skill:officecli-docx',
  'skill:officecli-pptx', 'skill:officecli-xlsx', 'skill:omarchy', 'skill:diagnose-crash']) {
  assert.ok(names.includes(name), `Missing resource ${name}`);
}
const state = records.find(r => r.id === 'state').data;
assert.equal(state.isStreaming, false);
assert.equal(state.messageCount, 0);
const result = { skills: names.filter(n => n.startsWith('skill:')), commands: names.filter(n => !n.startsWith('skill:')),
  model: `${state.model.provider}/${state.model.id}`, thinking: state.thinkingLevel, stderr };
writeFileSync(join(homedir(), '.local/state/dotfiles-migration/pi-resource-audit.json'), JSON.stringify(result, null, 2) + '\n', { mode: 0o600 });
assert.ok(!stderr.match(/error|failed|collision|invalid/i), stderr);
console.log(JSON.stringify(result, null, 2));
console.log('No prompt/model request was sent; no real project was opened.');
