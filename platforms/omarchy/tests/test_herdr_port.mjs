// Disposable server/profile only; never stop or send input to the user's server.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createServer, createConnection } from 'node:net';
import { mkdtempSync, mkdirSync, writeFileSync, copyFileSync, readdirSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const repo=resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const realHome=process.env.HOME;
const work=mkdtempSync(join(tmpdir(),'herdr-port-test.'));
const home=join(work,'home'), config=join(home,'.config/herdr/config.toml');
mkdirSync(dirname(config),{recursive:true});
writeFileSync(config,'onboarding=false\n[terminal]\ndefault_shell="/bin/bash"\nshell_mode="non_login"\n[update]\nversion_check=false\nmanifest_check=false\n[session]\nresume_agents_on_restore=false\n');
const profile=join(work,'ipython/profile_default/startup');
mkdirSync(profile,{recursive:true});
for(const file of ['00-nvim-helpers.py','01-output-box.py','02-execution-timer.py','03-quiet-queued-input.py']){
 copyFileSync(join(repo,'.ipython/profile_default/startup',file),join(profile,file));
}
const env={...process.env, HOME:home, XDG_CONFIG_HOME:join(home,'.config'), XDG_STATE_HOME:join(home,'.local/state'),
 XDG_CACHE_HOME:join(home,'.cache'), IPYTHONDIR:join(work,'ipython'), MPLCONFIGDIR:join(work,'matplotlib'), UV_OFFLINE:'1'};
for(const key of Object.keys(env))if(key.startsWith('HERDR_'))delete env[key];
env.HERDR_CONFIG_PATH=config;
const name='dotfiles-port-check';
const server=spawn('herdr',['--session',name,'server'],{env,cwd:work,stdio:['ignore','pipe','pipe']});
let serverLog='';server.stdout.on('data',s=>serverLog+=s);server.stderr.on('data',s=>serverLog+=s);
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
function sockets(dir){if(!existsSync(dir))return [];return readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?sockets(join(dir,e.name)):e.name==='herdr.sock'?[join(dir,e.name)]:[])}
let socket,sequence=0;
async function request(method,params={}){
 return new Promise((resolve,reject)=>{
  let buffer='';const client=createConnection(socket);const timer=setTimeout(()=>{client.destroy();reject(Error('test request timeout: '+method))},5000);
  client.on('error',reject);client.on('connect',()=>client.write(JSON.stringify({id:'test:'+ ++sequence,method,params})+'\n'));
  client.on('data',data=>{buffer+=data;const end=buffer.indexOf('\n');if(end<0)return;clearTimeout(timer);client.destroy();const reply=JSON.parse(buffer.slice(0,end));if(reply.error)reject(Error(JSON.stringify(reply.error)));else resolve(reply.result)});
 });
}
try{
 for(let i=0;i<100;i++){socket=sockets(home)[0];if(socket)break;if(server.exitCode!==null)throw Error(serverLog);await sleep(100)}
 assert.ok(socket?.startsWith(work+'/'),'Private server socket missing: '+serverLog);
 const created=await request('workspace.create',{cwd:work,label:'isolated-check',focus:false});
 const current=created.root_pane;
 assert.ok(current?.pane_id,'Creation must return the caller pane');
 const python=join(realHome,'.local/share/uv/tools/ipython/bin/python');
 const quote=s=>"'"+s.replaceAll("'","'\\''")+"'";
 const command=['uv','run','--offline','--no-project','--python',python,python,'-m','IPython','--no-autoindent'].map(quote).join(' ');
 const childEnv={...env,HERDR_ENV:'1',HERDR_SOCKET_PATH:socket,HERDR_PANE_ID:current.pane_id,
  HERDR_WORKSPACE_ID:created.workspace.workspace_id,HERDR_TAB_ID:created.tab.tab_id,
  HERDR_TEST_REPO:repo,HERDR_TEST_SLIME:join(realHome,'.local/share/nvim/site/pack/core/opt/vim-slime'),
  HERDR_TEST_SIDEKICK:join(realHome,'.local/share/nvim/site/pack/core/opt/sidekick.nvim'),HERDR_TEST_IPYTHON_COMMAND:command};
 const output=await new Promise((resolve,reject)=>{
  const child=spawn('nvim',['--headless','-u','NONE','-i','NONE','-l',join(repo,'platforms/omarchy/tests/test_herdr_live.lua')],{env:childEnv,cwd:work});
  let text='';child.stdout.on('data',s=>text+=s);child.stderr.on('data',s=>text+=s);
  child.on('error',reject);child.on('exit',code=>code===0?resolve(text):reject(Error(text)));
 });
 console.log(output.trim());
}finally{
 // Explicit named namespace + private HOME: this can never select the live server.
 const stopped=spawnSync('herdr',['--session',name,'server','stop'],{env,cwd:work,encoding:'utf8',timeout:5000});
 writeFileSync(join(work,'server.log'),serverLog);
 assert.equal(stopped.status,0,'Could not stop private test server: '+stopped.stderr);
}

// Fresh processes prove that the shared edits preserve Mac/tmux precedence.
for(const mode of ['tmux-in-herdr','mac-wezterm','herdr-in-wezterm']){
 const matrix={...env,HERDR_TEST_REPO:repo,HERDR_TEST_SIDEKICK:join(realHome,'.local/share/nvim/site/pack/core/opt/sidekick.nvim')};
 delete matrix.TMUX;delete matrix.WEZTERM_PANE;delete matrix.HERDR_ENV;delete matrix.HERDR_SOCKET_PATH;
 if(mode!=='mac-wezterm'){matrix.HERDR_ENV='1';matrix.HERDR_SOCKET_PATH='/unused-test-socket'}
 if(mode==='tmux-in-herdr')matrix.TMUX='/unused-test-tmux';else matrix.WEZTERM_PANE='1';
 matrix.HERDR_TEST_EXPECT_SLIME=mode==='tmux-in-herdr'?'tmux':mode==='mac-wezterm'?'wezterm':'herdr';
 matrix.HERDR_TEST_EXPECT_SIDEKICK=mode==='herdr-in-wezterm'?'herdr':'tmux';
 const result=spawnSync('nvim',['--headless','-u','NONE','-i','NONE','-l',join(repo,'platforms/omarchy/tests/test_herdr_modes.lua')],{env:matrix,cwd:work,encoding:'utf8',timeout:15000});
 assert.equal(result.status,0,result.stdout+result.stderr);console.log((result.stdout+result.stderr).trim());
}

// Test the installed official extension against a fake local socket, not Pi/model APIs.
const hookSocket=join(work,'official-hook.sock'), messages=[];
const receiver=createServer(client=>{
 let buffer='';client.on('data',data=>{buffer+=data;const end=buffer.indexOf('\n');if(end<0)return;messages.push(JSON.parse(buffer.slice(0,end)));client.end('{}\n')});
});
await new Promise(r=>receiver.listen(hookSocket,r));
const saved={...process.env};
try{
 Object.assign(process.env,{HERDR_ENV:'1',HERDR_SOCKET_PATH:hookSocket,HERDR_PANE_ID:'test:p1'});
 const agentDir=process.env.PI_CODING_AGENT_DIR || join(realHome,'.pi/agent');
 const factory=(await import(pathToFileURL(join(agentDir,'extensions/herdr-agent-state.ts')).href)).default;
 const events=new Map(),bus=new Map();
 factory({on:(name,fn)=>events.set(name,fn),events:{on:(name,fn)=>bus.set(name,fn)}});
 let idle=true;
 const ctx={mode:'tui',isIdle:()=>idle,sessionManager:{getSessionFile:()=>join(work,'fictional-session.jsonl'),getSessionId:()=> 'test-session'}};
 await events.get('session_start')({reason:'startup'},ctx);
 idle=false;events.get('agent_start')({},ctx);
 for(let i=0;i<50&&!messages.some(m=>m.params.state==='working');i++)await sleep(20);
 bus.get('herdr:blocked')({active:true,label:'test approval'});
 for(let i=0;i<50&&!messages.some(m=>m.params.state==='blocked');i++)await sleep(20);
 bus.get('herdr:blocked')({active:false});idle=true;events.get('agent_settled')({},ctx);
 for(let i=0;i<50&&messages.at(-1)?.params.state!=='idle';i++)await sleep(20);
 assert.ok(messages.some(m=>m.method==='pane.report_agent_session'));
 for(const state of ['idle','working','blocked'])assert.ok(messages.some(m=>m.params.state===state));
 console.log('PASS official Pi hook: local socket, session reference, working/blocked/settled lifecycle');
}finally{
 for(const key of ['HERDR_ENV','HERDR_SOCKET_PATH','HERDR_PANE_ID']){
  if(saved[key]===undefined)delete process.env[key];else process.env[key]=saved[key];
 }
 await new Promise(r=>receiver.close(r));
}
console.log('Private test artifacts: '+work);
