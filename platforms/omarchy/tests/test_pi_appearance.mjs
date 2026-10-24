// Isolated HOME and mocked Omarchy/tmux only. --tui also checks a disposable,
// offline Pi process in its own PTY; no real terminal, credentials, or model calls.
import assert from 'node:assert/strict';
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import { closeSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, openSync,
    readFileSync, readdirSync, renameSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const overlay = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repo = resolve(overlay, '../..');
const hook = join(overlay, 'home/.config/omarchy/hooks/theme-set.d/20-shared-appearance');
const work = mkdtempSync(join(tmpdir(), 'pi-appearance-test.'));
const bin = join(work, 'bin');
mkdirSync(bin);
writeFileSync(join(bin, 'omarchy-theme-color'), '#!/bin/sh\nprintf "%s\\n" "$TEST_APPEARANCE_MODE"\n', { mode: 0o755 });
writeFileSync(join(bin, 'tmux'), `#!/bin/sh
case "$1" in
  list-sessions) test -f "$HOME/tmux-running" ;;
  source-file) printf '%s\\n' "$2" >> "$HOME/tmux-sourced" ;;
  *) exit 2 ;;
esac
`, { mode: 0o755 });

const palettes = Object.fromEntries(['dark', 'light'].map(mode => [mode,
    JSON.parse(readFileSync(join(repo, '.config/pi/agent/themes', `everforest-${mode}.json`), 'utf8'))]));
let homes = 0;
function fixture(withPi = true) {
    const home = join(work, `home-${++homes}`);
    const agent = join(home, '.pi/agent');
    const themes = join(agent, 'themes');
    const palette = join(home, '.local/state/omarchy/current/theme');
    mkdirSync(palette, { recursive: true });
    writeFileSync(join(palette, 'tmux.conf'), '# synthetic palette; never sourced by real tmux\n');
    if (withPi) {
        mkdirSync(themes, { recursive: true });
        for (const mode of ['dark', 'light']) {
            copyFileSync(join(repo, '.config/pi/agent/themes', `everforest-${mode}.json`), join(themes, `everforest-${mode}.json`));
        }
        writeFileSync(join(agent, 'settings.json'), JSON.stringify({ theme: 'everforest-omarchy', packages: [] }));
    }
    return { home, agent, themes, target: join(themes, 'everforest-omarchy.json') };
}
function environment(f, mode) {
    return {
        HOME: f.home, PATH: `${bin}:${process.env.PATH}`, SHELL: '/bin/bash',
        XDG_CACHE_HOME: join(f.home, '.cache'), XDG_CONFIG_HOME: join(f.home, '.config'),
        XDG_STATE_HOME: join(f.home, '.local/state'), PI_CODING_AGENT_DIR: f.agent,
        TEST_APPEARANCE_MODE: mode,
    };
}
function runHook(f, mode, expectedSuccess = true) {
    const result = spawnSync('bash', [hook], { env: environment(f, mode), encoding: 'utf8', timeout: 5000 });
    if (expectedSuccess) assert.equal(result.status, 0, result.stderr);
    else assert.notEqual(result.status, 0, 'Invalid input must fail');
    return result;
}
function assertTheme(f, mode) {
    assert.deepEqual(JSON.parse(readFileSync(f.target, 'utf8')),
        { ...palettes[mode], name: 'everforest-omarchy', appearance: mode });
    assert.equal(readFileSync(join(f.home, '.cache/appearance'), 'utf8'), `${mode}\n`);
    assert.equal(statSync(f.target).mode & 0o777, 0o600);
    assert.ok(!readdirSync(f.themes).some(name => name.startsWith('.everforest-omarchy.')));
}

const f = fixture();
const settingsBefore = readFileSync(join(f.agent, 'settings.json'), 'utf8');
for (const mode of ['dark', 'light', 'dark', 'light', 'dark']) {
    runHook(f, mode);
    assertTheme(f, mode);
}
assert.equal(readFileSync(join(f.agent, 'settings.json'), 'utf8'), settingsBefore);
for (const mode of ['dark', 'light']) {
    assert.deepEqual(JSON.parse(readFileSync(join(f.themes, `everforest-${mode}.json`), 'utf8')), palettes[mode]);
}
console.log('PASS repeated dark/light/dark selection, exact palettes, private output, and unchanged sources/settings');

const oldContents = readFileSync(f.target, 'utf8');
const oldFile = openSync(f.target, 'r');
try {
    runHook(f, 'light');
    assert.equal(readFileSync(oldFile, 'utf8'), oldContents, 'Publish by atomic rename, not an in-place rewrite');
    assertTheme(f, 'light');
} finally { closeSync(oldFile); }
console.log('PASS atomic publication keeps existing file readers intact');

writeFileSync(join(f.home, 'tmux-running'), '');
runHook(f, 'dark');
assert.match(readFileSync(join(f.home, 'tmux-sourced'), 'utf8'), /current\/theme\/tmux\.conf\n$/);
const beforeInvalid = readFileSync(f.target, 'utf8');
runHook(f, 'unknown', false);
assert.equal(readFileSync(f.target, 'utf8'), beforeInvalid);
assert.equal(readFileSync(join(f.home, '.cache/appearance'), 'utf8'), 'dark\n');
console.log('PASS existing tmux integration and invalid appearance rejection');

writeFileSync(join(f.themes, 'everforest-light.json'), '{ invalid JSON');
runHook(f, 'light', false);
assert.equal(readFileSync(f.target, 'utf8'), beforeInvalid);
assert.ok(!readdirSync(f.themes).some(name => name.startsWith('.everforest-omarchy.')));
console.log('PASS malformed source preserves the last valid Pi theme and cleans temporary output');

const missing = fixture(false);
runHook(missing, 'dark');
assert.ok(!existsSync(missing.agent), 'Do not create Pi state when Pi themes are absent');
assert.equal(readFileSync(join(missing.home, '.cache/appearance'), 'utf8'), 'dark\n');
const custom = fixture();
const customAgent = join(custom.home, 'custom-agent');
renameSync(custom.agent, customAgent);
custom.agent = customAgent;
custom.themes = join(customAgent, 'themes');
custom.target = join(custom.themes, 'everforest-omarchy.json');
runHook(custom, 'light');
assertTheme(custom, 'light');
console.log('PASS absent Pi resources and explicit PI_CODING_AGENT_DIR');

if (process.argv.includes('--tui')) {
    const live = fixture();
    runHook(live, 'dark');
    const reports = join(work, 'observed-themes.jsonl');
    const observer = join(work, 'observe-theme.ts');
    // This observer never sets a theme or reloads Pi. Its timer exists only in
    // the disposable test process and shuts down even if the driver fails.
    writeFileSync(observer, `
import { appendFileSync, watch } from 'node:fs';
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';
export default function (pi: ExtensionAPI) {
    let interval: ReturnType<typeof setInterval>;
    let deadline: ReturnType<typeof setTimeout>;
    let watcher: ReturnType<typeof watch>;
    pi.on('session_start', (_event, ctx) => {
        if (ctx.mode !== 'tui') return;
        let previous = '';
        const sample = () => {
            const theme = ctx.ui.theme;
            const report = JSON.stringify({ pid: process.pid, name: theme.name, appearance: theme.appearance,
                accent: theme.getFgAnsi('accent'), text: theme.getFgAnsi('text'), pending: theme.getBgAnsi('toolPendingBg') });
            if (report !== previous) {
                appendFileSync(${JSON.stringify(reports)}, JSON.stringify({ at: Date.now(), ...JSON.parse(report) }) + '\\n');
                previous = report;
            }
        };
        watcher = watch(${JSON.stringify(live.themes)}, (event, filename) => {
            appendFileSync(${JSON.stringify(join(work, 'watch-events.jsonl'))}, JSON.stringify({ event, filename }) + '\\n');
        });
        sample();
        interval = setInterval(sample, 30);
        deadline = setTimeout(() => ctx.shutdown(), 12000);
    });
    pi.on('session_shutdown', () => { clearInterval(interval); clearTimeout(deadline); watcher?.close(); });
}
`);
    const pi = execFileSync('which', ['pi'], { encoding: 'utf8' }).trim();
    const args = [pi, '--offline', '--no-session', '--no-context-files', '--no-extensions',
        '--no-mcp', '--no-skills', '--no-prompt-templates', '--no-tools', '--no-approve', '-e', observer];
    const quote = value => `'${value.replaceAll("'", "'\\''")}'`;
    const child = spawn('script', ['-q', '-e', '-f', '-c', args.map(quote).join(' '), join(work, 'terminal.log')], {
        cwd: live.home,
        env: { ...environment(live, 'dark'), TERM: 'xterm-256color', COLORTERM: 'truecolor',
            COLORFGBG: '15;0', PI_OFFLINE: '1' },
        stdio: ['pipe', 'pipe', 'pipe'],
    });
    let output = '';
    child.stdout.on('data', data => { output = (output + data).slice(-200000); });
    child.stderr.on('data', data => { output = (output + data).slice(-200000); });
    child.stdin.on('error', () => {});
    const exited = new Promise((resolveExit, reject) => { child.on('error', reject); child.on('exit', resolveExit); });
    const sleep = ms => new Promise(resolveSleep => setTimeout(resolveSleep, ms));
    const ansi = (mode, token, background = false) => {
        let value = palettes[mode].colors[token];
        while (!value.startsWith('#')) value = palettes[mode].vars[value];
        const rgb = [1, 3, 5].map(at => parseInt(value.slice(at, at + 2), 16));
        return `\x1b[${background ? 48 : 38};2;${rgb.join(';')}m`;
    };
    let observedPid;
    async function waitForTheme(mode, count) {
        const deadline = Date.now() + 5000;
        while (Date.now() < deadline) {
            let rows = [];
            try { rows = readFileSync(reports, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse); } catch {}
            const last = rows.at(-1);
            if (rows.length >= count && last?.appearance === mode) {
                assert.equal(last.name, 'everforest-omarchy');
                assert.equal(last.accent, ansi(mode, 'accent'));
                assert.equal(last.text, ansi(mode, 'text'));
                assert.equal(last.pending, ansi(mode, 'toolPendingBg', true));
                observedPid ??= last.pid;
                assert.equal(last.pid, observedPid, 'All transitions must happen in one Pi process');
                return;
            }
            assert.equal(child.exitCode, null, output);
            await sleep(40);
        }
        throw new Error(`Pi never applied ${mode} at transition ${count}; inspect ${reports} and ${join(work, 'terminal.log')}`);
    }
    try {
        await waitForTheme('dark', 1);
        // session_start precedes the startup color-query timeout and final UI setup.
        await sleep(500);
        let transitions = 1;
        for (const mode of ['light', 'dark', 'light', 'dark']) {
            runHook(live, mode);
            await waitForTheme(mode, ++transitions);
            await sleep(200);
        }
        for (const mode of ['dark', 'light']) {
            assert.ok(output.includes(ansi(mode, 'muted')), `Rendered ${mode} text`);
            assert.ok(output.includes(ansi(mode, 'borderMuted')), `Rendered ${mode} editor border`);
        }
        console.log('PASS real Pi native hot-reload and UI repaint: dark → light → dark → light → dark, one process, no /reload or terminal notifications');
    } finally {
        child.stdin.end('\x04');
        const code = await exited;
        assert.equal(code, 0, output);
    }
}
console.log(`Isolated test artifacts: ${work}`);
