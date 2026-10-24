// Read-only checks; --live additionally inspects the current Omarchy session.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdtempSync, readdirSync, readFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const overlay = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const source = join(overlay, 'home/.config');
const patches = ['workspace-icons-commons.patch', 'workspace-icons-rainbow-mono.patch']
    .map(name => join(overlay, 'patches', name));
const style = readFileSync(join(source, 'omarchy/shell.toml'), 'utf8');
assert.match(style, /^\[bar\]$/m);
assert.match(style, /^size-horizontal = 32$/m);
assert.match(style, /^scale-with-font = false$/m);
assert.doesNotMatch(style, /^(background|text|active)\s*=/m, 'Colors must remain theme-owned');
// The bar is the same translucent material as the terminal.
const kittyOpacity = readFileSync(join(source, 'kitty/kitty.conf'), 'utf8').match(/^background_opacity\s+([\d.]+)$/m)[1];
assert.equal(Number(style.match(/^background-alpha = ([\d.]+)$/m)[1]), Number(kittyOpacity),
    'Bar background-alpha matches Kitty background_opacity');
// Island geometry lives in its own section, read only by our island bar.
assert.match(style, /^\[island-bar\]$/m);
const islandValues = Object.fromEntries([...style.slice(style.indexOf('[island-bar]'))
    .matchAll(/^([a-z-]+) = (\S+)$/gm)].map(match => [match[1], Number(match[2])]));
assert.deepEqual(Object.keys(islandValues).sort(), ['edge-gap', 'radius', 'side-gap']);
for (const [key, value] of Object.entries(islandValues)) assert.ok(Number.isFinite(value) && value >= 0, key);

// Evaluate our Lua with inert API stubs, never with the live compositor API.
const lua = `
local config, layers, windows = nil, {}, {}
hl = {
    config = function(value) config = value end,
    layer_rule = function(value) table.insert(layers, value) end,
}
o = { window = function(match, rules) table.insert(windows, { match, rules }) end }
assert(loadfile(arg[1]))()
assert(config.decoration.rounding == 8)
assert(config.decoration.blur.enabled == true)
assert(config.decoration.blur.size == 4 and config.decoration.blur.passes == 2)
assert(#layers == 1 and layers[1].match.namespace == '^omarchy-bar$')
assert(layers[1].blur == true and layers[1].ignore_alpha == 0.2)
assert(#windows == 4, 'Existing window rules must be preserved')
assert(windows[1][2].border_size == 0)
assert(windows[2][1] == '.*' and windows[2][2].no_blur == true)
assert(windows[3][2].no_blur == false and windows[4][2].no_blur == false)
local gaps = config.general.gaps_out
print(type(gaps) == 'table' and gaps.top or gaps)
`;
const configuredTopGap = Number(execFileSync('lua', ['-', join(source, 'hypr/looknfeel.lua')], { input: lua, encoding: 'utf8' }).trim());
assert.ok(Number.isFinite(configuredTopGap), 'looknfeel.lua sets the top window gap');
console.log('PASS authored bar dimensions, theme ownership, and targeted layer blur');

// Vendored sketchybar-app-font glyphs: pinned, well-formed, black-on-transparent
// SVGs, every one referenced by the mapping script and nothing else inside.
const glyphDir = join(source, 'omarchy/app-glyphs');
assert.match(readFileSync(join(glyphDir, 'UPSTREAM_COMMIT'), 'utf8').trim(), /^[0-9a-f]{40}$/);
const glyphs = readdirSync(glyphDir).filter(name => name.endsWith('.svg'));
assert.ok(glyphs.length >= 20);
for (const name of glyphs) {
    const svg = readFileSync(join(glyphDir, name), 'utf8');
    assert.match(svg, /^\s*<svg[\s>]/, name);
    assert.match(svg, /<\/svg>\s*$/, name);
    assert.doesNotMatch(svg, /fill="#(?!0{3,6}")[0-9a-fA-F]{3,6}"|fill="(?!none|black)[a-z]+"|<image|<script/i,
        `${name} must stay a single black glyph`);
}
assert.deepEqual(readdirSync(glyphDir).filter(name => !name.endsWith('.svg')), ['UPSTREAM_COMMIT']);
const script = join(overlay, 'home/.local/bin/bar-app-glyphs');
execFileSync('bash', ['-n', script]);
const mapping = readFileSync(script, 'utf8').match(/^mapping='\n([\s\S]*?)'$/m)[1].trim().split('\n')
    .map(line => line.split(' '));
assert.ok(mapping.length >= 25);
for (const [key, glyph, extra] of mapping) {
    assert.ok(key && glyph && extra === undefined, `mapping line: ${key}`);
    assert.ok(glyphs.includes(`${glyph}.svg`), `${key} -> ${glyph}.svg`);
}
assert.deepEqual(new Set(mapping.map(([, glyph]) => `${glyph}.svg`)), new Set(glyphs), 'No unused glyphs');
assert.equal(new Set(mapping.map(([key]) => key)).size, mapping.length, 'No duplicate classes');
for (const [key, glyph] of [['kitty', 'kitty'], ['brave-origin', 'brave'], ['nvim', 'neovim'], ['herdr', 'herdr']]) {
    assert.ok(mapping.some(entry => entry[0] === key && entry[1] === glyph), key);
}
const fakeConfig = mkdtempSync(join(tmpdir(), 'bar-app-glyphs.'));
cpSync(glyphDir, join(fakeConfig, 'omarchy/app-glyphs'), { recursive: true });
const produced = JSON.parse(execFileSync('bash', [script, 'json'], { encoding: 'utf8', env: { ...process.env, XDG_CONFIG_HOME: fakeConfig } }));
assert.equal(Object.keys(produced).length, mapping.length);
for (const value of Object.values(produced)) {
    assert.match(value, /^mono:\/.*\.svg$/);
    assert.ok(existsSync(value.slice(5)), value);
}
for (const patch of patches) assert.match(readFileSync(patch, 'utf8'), /^diff --git /m);
const rainbow = readFileSync(patches[1], 'utf8');
assert.match(rainbow, /\+\s+readonly property bool rainbow: boolOption\("rainbowWorkspaces", false\)/);
assert.match(rainbow, /\+\s+readonly property bool isMono: String\(group\.source \|\| ""\)\.indexOf\("mono:"\) === 0/);
assert.match(rainbow, /\+\s+brightness: root\.isMono \? 1 :/);
assert.match(rainbow, /\+\s+"rainbowWorkspaces": false$/m, 'Rainbow is opt-in by default');
console.log('PASS vendored glyphs, mapping script, and recorded patches');

// The front-app custom module: the bar's documented module contract, muted
// theme color, no hard-coded colors, and parseable QML. qmllint cannot
// resolve Quickshell's `qs.*` import root, so only real errors fail here.
const frontApp = readFileSync(join(source, 'omarchy/bar/modules/front-app.qml'), 'utf8');
assert.match(frontApp, /^Item \{$/m);
for (const line of ['property var bar', 'property string moduleName', 'property var settings', 'implicitWidth:', 'implicitHeight:']) {
    assert.ok(frontApp.includes(line), line);
}
assert.match(frontApp, /color: Commons\.Color\.muted/);
assert.doesNotMatch(frontApp, /#[0-9a-fA-F]{6}/, 'Colors must remain theme-owned');
assert.match(frontApp, /ToplevelManager\.activeToplevel/);
assert.match(frontApp, /DesktopEntries\.(byId|heuristicLookup)/);
assert.match(frontApp, /\(\?:brave\|chrome\|chromium\|msedge\|vivaldi\)-/, 'Web app windows resolve to their launcher');
const lint = execFileSync('/usr/lib/qt6/bin/qmllint', ['-I', '/usr/share/omarchy/shell', '-I', '/usr/lib/qt6/qml',
    join(source, 'omarchy/bar/modules/front-app.qml')], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
assert.doesNotMatch(lint, /^Error:/m, lint);
console.log('PASS front-app module contract and lint');

// The derived island bar: a recorded overlay that must still apply to the
// installed engine, plus the generator and post-update hook that rebuild it.
const islandPatch = join(overlay, 'patches/island-bar-overlay.patch');
const islandOverlay = readFileSync(islandPatch, 'utf8');
for (const marker of ['component IslandBackdrop: Rectangle', 'readonly property int barThickness: barSize + islandEdgeGap',
    'Commons.Color.shellValues["island-bar." + key]', 'islandSetting("edge-gap", 4)', 'islandSetting("side-gap", 8)',
    'islandSetting("radius", 10)', 'color: root.background', 'visible: !root.transparent',
    'Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.25', 'property string omarchyPath: ""']) {
    assert.ok(islandOverlay.includes(marker), marker);
}
assert.equal(islandOverlay.match(/^\+\s+IslandBackdrop \{$/gm).length, 2, 'One island per orientation');
assert.doesNotMatch(islandOverlay, /^\+.*#[0-9a-fA-F]{6}/m, 'Island colors must remain theme-owned');
const stockBar = '/usr/share/omarchy/shell/plugins/bar/Bar.qml';
if (existsSync(stockBar)) {
    const scratch = mkdtempSync(join(tmpdir(), 'island-overlay.'));
    cpSync(stockBar, join(scratch, 'Bar.qml'));
    execFileSync('patch', ['-s', '--dry-run', '-p1', '-d', scratch, '-i', islandPatch]);
}
for (const file of ['home/.local/bin/build-island-bar', 'home/.config/omarchy/hooks/post-update.d/30-island-bar']) {
    execFileSync('bash', ['-n', join(overlay, file)]);
}
assert.match(readFileSync(join(overlay, 'home/.config/omarchy/hooks/post-update.d/30-island-bar'), 'utf8'), /build-island-bar$/m);
console.log('PASS island overlay applies to the installed engine; generator and hook parse');

if (process.argv.includes('--live')) {
    const command = (file, args = []) => execFileSync(file, args, { encoding: 'utf8', timeout: 15000 });
    const json = (file, args) => JSON.parse(command(file, args));
    const pluginId = 'woodenplastic.workspace-icons';
    const plugin = join(homedir(), '.config/omarchy/plugins', pluginId);
    const config = JSON.parse(readFileSync(join(homedir(), '.config/omarchy/shell.json'), 'utf8'));
    assert.equal(config.bar.id, 'jdpinto.island-bar', 'The derived island bar is in use');
    assert.equal(command('build-island-bar', ['--check']).trim(), 'island bar matches the installed engine plus overlay');
    assert.ok(existsSync(join(homedir(), '.config/omarchy/hooks/post-update.d/30-island-bar')), 'Post-update rebuild hook is linked');
    assert.equal(config.bar.transparent, false, 'Islands show; transparent would hide them');
    assert.match(command('omarchy', ['plugin', 'list']), /^omarchy\.flush-bar\s+disabled/m,
        'flush-bar would override the window gap below the bar');
    const gapsOut = json('hyprctl', ['-j', 'getoption', 'general:gaps_out']).css.trim().split(/\s+/).map(Number);
    assert.equal(gapsOut[0], configuredTopGap, 'The configured top window gap is in effect');
    assert.ok(json('hyprctl', ['-j', 'monitors']).every(monitor => monitor.reserved[1] === 32 + islandValues['edge-gap']),
        'Windows reserve the island plus its gap to the screen edge');
    const entries = Object.values(config.bar.layout).flat();
    const widget = entries.find(entry => entry.id === pluginId);
    assert.ok(widget, 'Workspace Icons must be enabled');
    assert.equal(entries.filter(entry => entry.id === pluginId).length, 1);
    assert.ok(!entries.some(entry => entry.id === 'omarchy.workspaces'));
    for (const [key, value] of Object.entries({
        barStyle: 'tiles', activeTile: 'accent', coloredIcons: false, tintStyle: 'normal',
        showNumbers: true, maxIcons: 3, showCounts: true, showTerminalPrograms: true,
        hideEmpty: true, showSpecial: false, showPreview: false, rainbowWorkspaces: true,
    })) assert.equal(widget[key], value, key);
    assert.deepEqual(widget.iconOverrides, JSON.parse(command('bar-app-glyphs', ['json'])),
        'Live overrides must match the mapping script');
    const leftIds = config.bar.layout.left.map(entry => entry.id ?? entry);
    assert.equal(leftIds[leftIds.indexOf(pluginId) + 1], 'front-app', 'App name follows the workspaces');
    assert.deepEqual(config.bar.layout.left.find(entry => entry.id === 'front-app'), { id: 'front-app', type: 'qml' });
    assert.equal(readFileSync(join(homedir(), '.config/omarchy/bar/modules/front-app.qml'), 'utf8'), frontApp, 'Module is linked');
    const rightIds = config.bar.layout.right.map(entry => entry.id ?? entry);
    assert.ok(rightIds.indexOf('omarchy.media') !== -1 && rightIds.indexOf('omarchy.media') < rightIds.indexOf('omarchy.weather'),
        'Now playing sits before the weather');
    assert.equal(config.bar.layout.right.at(-1).id, 'omarchy.clock');
    assert.equal(command('hyprctl', ['configerrors']).trim(), '');

    // The checkout must equal upstream HEAD plus our two patches, in order.
    const pristine = mkdtempSync(join(tmpdir(), 'workspace-icons-pristine.'));
    execFileSync('bash', ['-c', 'git -C "$1" archive HEAD | tar -x -C "$2" && git -C "$2" init -q', '-', plugin, pristine]);
    for (const patch of patches) command('git', ['-C', pristine, 'apply', patch]);
    for (const file of ['Workspaces.qml', 'WorkspaceButton.qml', 'WorkspacePreview.qml', 'AppIconButton.qml', 'manifest.json']) {
        assert.equal(readFileSync(join(plugin, file), 'utf8'), readFileSync(join(pristine, file), 'utf8'), file);
    }
    assert.deepEqual(command('git', ['-C', plugin, 'status', '--short']).trim().split('\n').map(line => line.trim()).sort(),
        ['M AppIconButton.qml', 'M WorkspaceButton.qml', 'M WorkspacePreview.qml', 'M Workspaces.qml', 'M manifest.json']);
    for (const file of ['Workspaces.qml', 'WorkspacePreview.qml']) {
        assert.doesNotMatch(readFileSync(join(plugin, file), 'utf8'), /(?<![\w.])Color\./);
    }
    const states = json('omarchy-shell', [pluginId, 'status']);
    assert.ok(states.length > 0);
    let monoIcons = 0;
    for (const state of states) {
        assert.ok(state.workspaces.length > 0);
        assert.equal(state.settingsOpen, false);
        assert.equal(state.preview.can, false);
        for (const workspace of state.workspaces) {
            assert.match(workspace.key, /^\d+$/);
            assert.ok(workspace.focused || workspace.apps.length > 0, 'Hide empty workspaces');
            for (const app of workspace.apps) {
                assert.ok(app.icon && app.count > 0);
                if (app.icon.startsWith('mono:')) {
                    monoIcons += 1;
                    assert.match(app.icon, /^mono:file:\/\/\/.*\.svg$/);
                    assert.ok(existsSync(app.icon.slice('mono:file://'.length)), app.icon);
                }
            }
        }
    }
    assert.ok(monoIcons > 0, 'At least one open app resolves to a vendored glyph');
    const activeWorkspace = json('hyprctl', ['-j', 'activeworkspace']);
    assert.ok(states.some(state => state.workspaces.some(workspace =>
        workspace.key === String(activeWorkspace.id) && workspace.focused)), 'Focus matches Hyprland');
    const geometry = json('omarchy-shell', ['shell', 'debugBarGeometry']).filter(slot => slot.visible);
    const left = geometry.filter(slot => slot.section === 'left');
    const right = geometry.filter(slot => slot.section === 'right');
    assert.ok(left.some(slot => slot.id === pluginId));
    const frontAppSlot = left.find(slot => slot.id === 'front-app');
    assert.ok(frontAppSlot && frontAppSlot.width > 0, 'The focused app name is shown');
    assert.ok(frontAppSlot.x > left.find(slot => slot.id === pluginId).x, 'App name is right of the workspaces');
    assert.ok(right.some(slot => slot.id === 'omarchy.clock'));
    assert.ok(geometry.every(slot => slot.height === 32));
    assert.ok(geometry.every(slot => slot.y === islandValues['edge-gap']), 'Widgets sit inside the island, past the edge gap');
    assert.ok(Math.max(...left.map(slot => slot.x + slot.width)) < Math.min(...right.map(slot => slot.x)),
        'Workspace and status sections must not overlap');
    const logs = command('quickshell', ['log', '-p', '/usr/share/omarchy/shell', '-t', '1000', '--no-color']);
    const warnings = logs.split('\n').filter(line => /WARN|ERROR/.test(line)
        && (line.includes(pluginId) || line.includes('front-app') || line.includes('island-bar')));
    assert.deepEqual(warnings, [], 'No Workspace Icons, front-app, or island bar warnings in the current shell log');
    console.log('PASS live island bar, widget settings, glyph overrides, rainbow option, patched checkout, app name, now playing, geometry, clock position, and clean log');
}
