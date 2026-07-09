# ---- Homebrew ----
export PATH="/opt/homebrew/bin:$PATH"

# ---- Environment ----
export VISUAL="nvim"
export EDITOR="nvim"

# Define location of pi agent configs
export PI_CODING_AGENT_DIR="$HOME/.config/pi/agent"

# ---- History ----
HISTFILE=$HOME/.zhistory
SAVEHIST=1000
HISTSIZE=999
setopt share_history
setopt hist_expire_dups_first
setopt hist_ignore_dups
setopt hist_verify

# ---- Completion ----
autoload -Uz compinit add-zsh-hook
compinit

# Force emacs keybindings. Without this, zsh defaults to vi keybindings
# because EDITOR/VISUAL ("nvim") contains the substring "vi".
bindkey -e

# Search history based on what's already typed, using the arrow keys
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

# Opt-left / Opt-right: move by word
bindkey '^[[1;3D' backward-word
bindkey '^[[1;3C' forward-word

# ---- Aliases ----
alias gls="gls -lGhp --group-directories-first --color=auto"
alias pandoc="/opt/homebrew/bin/pandoc"
alias copilot=/opt/homebrew/bin/copilot
alias opencode="opencode --port"

# ---- nvm ----
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# ---- Starship (prompt) ----
eval "$(starship init zsh)"

# ---- Eza (better ls) ----
# alias ls="ls -l -G -h -p" 
alias ls="eza -lh --icons=always --color=always --group-directories-first --no-permissions --no-user --git"

# ---- Zoxide (better cd) ----
eval "$(zoxide init zsh)"

# ---- FZF -----

# Set up fzf key bindings and fuzzy completion
eval "$(fzf --zsh)"

# -- Use fd instead of fzf --

export FZF_DEFAULT_COMMAND="fd --hidden --strip-cwd-prefix --exclude .git"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fd --type=d --hidden --strip-cwd-prefix --exclude .git"

# Use fd (https://github.com/sharkdp/fd) for listing path candidates.
# - The first argument to the function ($1) is the base path to start traversal
# - See the source code (completion.{bash,zsh}) for the details.
_fzf_compgen_path() {
  fd --hidden --exclude .git . "$1"
}

# Use fd to generate the list for directory completion
_fzf_compgen_dir() {
  fd --type=d --hidden --exclude .git . "$1"
}

show_file_or_dir_preview="if [ -d {} ]; then eza --tree --color=always {} | head -200; else bat -n --color=always --line-range :500 {}; fi"

export FZF_CTRL_T_OPTS="--preview '$show_file_or_dir_preview'"
export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always {} | head -200'"

# Advanced customization of fzf options via _fzf_comprun function
# - The first argument to the function is the name of the command.
# - You should make sure to pass the rest of the arguments to fzf.
_fzf_comprun() {
  local command=$1
  shift

  case "$command" in
    cd)           fzf --preview 'eza --tree --color=always {} | head -200' "$@" ;;
    export|unset) fzf --preview "eval 'echo \${}'"          "$@" ;;
    ssh)          fzf --preview 'dig {}'                   "$@" ;;
    *)            fzf --preview "$show_file_or_dir_preview" "$@" ;;
  esac
}

source ~/fzf-git.sh/fzf-git.sh

# ---- Yazi wrapper function to change the current working directory after running yazi ----
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	command rm -f -- "$tmp"
}

# ---- btop wrapper: keep its catppuccin theme in sync with system dark mode ----
# Starts the dark-mode watcher (self-deduping, self-terminating — see its
# header comment) alongside btop, mirroring the tmux/sketchybar watchers.
function btop() {
	~/.config/btop/scripts/btop_dark_mode_watcher.sh &!
	command btop "$@"
}

# ---- OSC 7: report CWD to tmux and WezTerm ----
# Keeps #{pane_current_path} accurate so new panes/windows open in the right dir.
# Also benefits WezTerm's own CWD-aware features.
_osc7_cwd() {
  printf '\e]7;file://%s%s\a' "$HOST" "$PWD"
}
add-zsh-hook chpwd _osc7_cwd
_osc7_cwd  # emit once at shell startup

# ---- OSC 0: set pane title to "zsh - <cwd>" for tmux's pane-border-status ----
# Mirrors nvim's own titlestring (see nvim's options.lua); tmux's
# pane-border-format just displays whichever program last set the pane's
# title (#T), so this keeps shell panes from falling back to the hostname.
_pane_title() {
  printf '\e]0;zsh - %s\a' "${PWD/#$HOME/~}"
}
add-zsh-hook precmd _pane_title
_pane_title  # emit once at shell startup

# ---- Autosuggestions & syntax highlighting ----
# zsh-syntax-highlighting must be sourced last so it can wrap every
# widget defined above (fzf, zoxide, autosuggestions, etc).
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
