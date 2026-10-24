" Keep Herdr transport separate from the existing Mac/tmux/WezTerm targets.
function! slime#targets#herdr#config() abort
  let b:slime_config = luaeval("require('juan.herdr').configure_repl()")
endfunction

function! slime#targets#herdr#send(config, text) abort
  call luaeval("require('juan.herdr').slime_send(_A[1], _A[2])", [a:config, a:text])
endfunction

function! slime#targets#herdr#ValidEnv() abort
  return luaeval("require('juan.herdr').active()")
endfunction
