import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const repo=resolve(dirname(fileURLToPath(import.meta.url)),'../../..');
const root=mkdtempSync(join(tmpdir(),'herdr-launcher-check.')), bin=join(root,'bin');
mkdirSync(bin);mkdirSync(join(root,'home'));
const script=join(repo,'platforms/omarchy/home/.local/bin/herdr-widget-open');
function tool(name,body){writeFileSync(join(bin,name),'#!/usr/bin/env bash\nset -eu\n'+body,{mode:0o755})}
tool('setsid','exec "$@"\n');
tool('uwsm-app','[[ $1 == -- ]] && shift\nexec "$@"\n');
tool('xdg-terminal-exec','printf "%s\\0" "$@" > "$LAUNCH_LOG"\n');
tool('herdr','if [[ $* == "machine list --json" ]]; then printf \'[{"id":"work","enabled":true,"target":"user@host"}]\\n\'; else printf "%s\\0" "$@" > "$AGENT_LOG"; fi\n');
tool('hyprctl','if [[ $1 == clients ]]; then printf "%s\\n" "${CLIENTS_JSON:-[]}"; else printf "%s\\n" "$2" >> "$FOCUS_LOG"; fi\n');
const env={...process.env,HOME:join(root,'home'),XDG_CACHE_HOME:join(root,'cache'),PATH:bin+':'+process.env.PATH,
 LAUNCH_LOG:join(root,'launch'),AGENT_LOG:join(root,'agent'),FOCUS_LOG:join(root,'focus')};
const base={name:'default',machineId:'',windowAddress:''};
function run(row,pane='',extra={}){for(const p of [env.LAUNCH_LOG,env.AGENT_LOG,env.FOCUS_LOG])if(existsSync(p))rmSync(p);return spawnSync('bash',[script,JSON.stringify(row),pane],{env:{...env,...extra},encoding:'utf8'})}
function args(file){return readFileSync(file,'utf8').split('\0').filter(Boolean)}
assert.equal(run(base).status,0);
assert.deepEqual(args(env.LAUNCH_LOG),['--app-id=org.omarchy.herdr','--dir='+env.HOME,'--','herdr']);
assert.equal(run({...base,name:'project'},'w1:p2').status,0);
assert.deepEqual(args(env.AGENT_LOG),['--session','project','agent','focus','w1:p2']);
assert.deepEqual(args(env.LAUNCH_LOG).slice(-3),['herdr','--session','project']);
assert.equal(run({...base,windowAddress:'0xabc'},'',{CLIENTS_JSON:'[{"address":"0xabc","workspace":{"name":"2"}}]'}).status,0);
assert.ok(!existsSync(env.LAUNCH_LOG));assert.match(readFileSync(env.FOCUS_LOG,'utf8'),/address:0xabc/);
assert.equal(run({...base,name:'project',machineId:'work',remote:true}).status,0);
assert.deepEqual(args(env.LAUNCH_LOG).slice(-5),['herdr','--remote','user@host','--session','project']);
assert.notEqual(run({...base,name:'$(bad)'}).status,0);
assert.ok(!existsSync(env.LAUNCH_LOG));
assert.notEqual(run(base,'invalid;pane').status,0);
mkdirSync(join(env.XDG_CACHE_HOME,'omarchy-herdr'),{recursive:true});writeFileSync(join(env.XDG_CACHE_HOME,'omarchy-herdr/demo'),'');
assert.equal(run(base).status,0);assert.ok(!existsSync(env.LAUNCH_LOG));
console.log('PASS launcher: default terminal, named/local/remote routing, existing-window reuse, validation and demo no-op');
