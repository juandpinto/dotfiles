# ---- Homebrew ----
export PATH="/opt/homebrew/bin:$PATH"

# ---- uv-installed tools (e.g. ruff via `uv tool install`) ----
export PATH="$HOME/.local/bin:$PATH"

# ---- Environment ----
export VISUAL="nvim"
export EDITOR="nvim"

# Define location of pi agent configs
export PI_CODING_AGENT_DIR="$HOME/.config/pi/agent"

# Hint the terminal's light/dark background via COLORFGBG. Apps like pi's
# theme auto-detection query the terminal directly (OSC 11 / DSR), but that
# round-trip is unreliable through tmux and silently falls back to "dark"
# when it fails/times out. Setting COLORFGBG from the actual macOS appearance
# gives those tools a fast, correct fallback instead.
if defaults read -g AppleInterfaceStyle &>/dev/null; then
    export COLORFGBG="15;0" # dark background
else
    export COLORFGBG="0;15" # light background
fi

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
# EZA_COLORS is read fresh on every invocation (a plain env var read on
# process start, no config file involved), so recomputing it here from the
# shared appearance state file (~/.cache/appearance, see
# bin/appearance-watcher.sh and AGENTS.md's "Auto dark/light mode syncing"
# section) keeps `ls` in sync with dark/light mode without needing the
# watcher to know anything about eza. Hex values: sainnhe/everforest's
# official "medium" contrast palettes
# (https://github.com/sainnhe/everforest/blob/master/palette.md), the same
# ones used in nvim/tmux/WezTerm/btop/starship. See `man eza_colors` for
# what each two-letter code controls.
_eza_colors_dark="di=38;2;127;187;179:ex=1;38;2;230;152;117:ln=38;2;214;153;182:or=1;38;2;230;126;128:pi=38;2;219;188;127:so=38;2;214;153;182:bd=38;2;230;152;117:cd=38;2;230;152;117:sn=38;2;167;192;128:sb=38;2;167;192;128:da=38;2;122;132;120:hd=1;4;38;2;211;198;170:lp=38;2;131;192;146:xx=38;2;86;99;95:ga=38;2;167;192;128:gm=38;2;219;188;127:gd=38;2;230;126;128:gv=38;2;214;153;182:gt=38;2;230;152;117:gi=38;2;122;132;120:gc=1;38;2;230;126;128:Gm=38;2;214;153;182:Go=38;2;131;192;146:Gc=38;2;167;192;128:Gd=38;2;230;126;128:sc=38;2;167;192;128:bu=38;2;122;132;120:do=4;38;2;219;188;127:im=38;2;214;153;182:vi=38;2;214;153;182:mu=38;2;131;192;146:lo=38;2;131;192;146:cr=38;2;230;126;128:co=38;2;230;152;117:tm=38;2;86;99;95:cm=38;2;86;99;95"
_eza_colors_light="di=38;2;58;148;197:ex=1;38;2;245;125;38:ln=38;2;223;105;186:or=1;38;2;248;85;82:pi=38;2;223;160;0:so=38;2;223;105;186:bd=38;2;245;125;38:cd=38;2;245;125;38:sn=38;2;141;161;1:sb=38;2;141;161;1:da=38;2;166;176;160:hd=1;4;38;2;92;106;114:lp=38;2;53;167;124:xx=38;2;189;195;175:ga=38;2;141;161;1:gm=38;2;223;160;0:gd=38;2;248;85;82:gv=38;2;223;105;186:gt=38;2;245;125;38:gi=38;2;166;176;160:gc=1;38;2;248;85;82:Gm=38;2;223;105;186:Go=38;2;53;167;124:Gc=38;2;141;161;1:Gd=38;2;248;85;82:sc=38;2;141;161;1:bu=38;2;166;176;160:do=4;38;2;223;160;0:im=38;2;223;105;186:vi=38;2;223;105;186:mu=38;2;53;167;124:lo=38;2;53;167;124:cr=38;2;248;85;82:co=38;2;245;125;38:tm=38;2;189;195;175:cm=38;2;189;195;175"

# unalias first: if this file is re-sourced in a shell that still has `ls`
# defined as a plain alias (e.g. from before this function existed), zsh's
# parser alias-expands `ls` before it reaches the `()`  and errors out with
# "defining function based on alias". A fresh shell never hits this since it
# never had the alias, but re-sourcing needs it to be idempotent either way.
unalias ls 2>/dev/null
ls() {
  local appearance eza_colors
  appearance=$(cat ~/.cache/appearance 2>/dev/null)
  eza_colors="$_eza_colors_dark"
  [ "$appearance" = "light" ] && eza_colors="$_eza_colors_light"
  EZA_COLORS="$eza_colors" eza -lh --icons=always --color=always --group-directories-first --no-permissions --no-user --git "$@"
}

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

# ---- OSC 133: mark shell prompts for tmux's next-prompt/previous-prompt ----
# tmux's copy-mode ]/[ bindings (see tmux.conf) jump between prompts, but only
# if the shell emits this escape before drawing each prompt. Starship doesn't
# emit it itself, so we do it ourselves, same pattern as the OSC 0/7 hooks above.
_osc133_prompt_mark() {
  printf '\e]133;A\e\\'
}
add-zsh-hook precmd _osc133_prompt_mark

# ---- Autosuggestions & syntax highlighting ----
# zsh-syntax-highlighting must be sourced last so it can wrap every
# widget defined above (fzf, zoxide, autosuggestions, etc).
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
