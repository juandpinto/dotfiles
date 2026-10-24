# Interactive Bash additions. Omarchy supplies mise, Starship, zoxide and fzf.
# No Homebrew/NVM paths, macOS commands, or changes to the Pi agent directory.

alias lg='lazygit'

# Match the Mac's fd-backed completion, excluding Git internals.
export FZF_DEFAULT_COMMAND='fd --hidden --strip-cwd-prefix --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type=d --hidden --strip-cwd-prefix --exclude .git'
_fzf_compgen_path() { fd --hidden --exclude .git . "$1"; }
_fzf_compgen_dir() { fd --type=d --hidden --exclude .git . "$1"; }
_juan_file_preview='if [ -d {} ]; then eza --tree --color=always -- {} | head -200; else bat -n --color=always --line-range :500 -- {}; fi'
export FZF_CTRL_T_OPTS="--preview '$_juan_file_preview'"
export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always -- {} | head -200'"
_fzf_comprun() {
    local command=$1
    shift
    case "$command" in
        cd) fzf --preview 'eza --tree --color=always -- {} | head -200' "$@" ;;
        export|unset) fzf --preview 'printenv -- {}' "$@" ;;
        *) fzf --preview "$_juan_file_preview" "$@" ;;
    esac
}
# Avoid the stock Kitty image-preview alias clearing images in other tmux panes.
unalias ff 2>/dev/null || true
ff() { fzf --preview "$_juan_file_preview" "$@"; }

# Re-source after a checkout rename: existing widgets capture __fzf_git's path.
if [[ -r "$DOTFILES_DIR/.config/zsh/plugins/fzf-git.sh/fzf-git.sh" ]] && \
   [[ ${_JUAN_FZF_GIT_READY:-0} != 1 || ${__fzf_git:-} != "$DOTFILES_DIR/.config/zsh/plugins/fzf-git.sh/fzf-git.sh" ]]; then
    source "$DOTFILES_DIR/.config/zsh/plugins/fzf-git.sh/fzf-git.sh"
    _JUAN_FZF_GIT_READY=1
fi

# Keep ls theme-aware without spawning a process to read the appearance state.
source "${XDG_CONFIG_HOME:-$HOME/.config}/shell/eza-colors.bash"
unalias ls 2>/dev/null || true
ls() {
    local appearance=dark eza_colors
    if [[ -r $HOME/.cache/appearance ]]; then
        IFS= read -r appearance < "$HOME/.cache/appearance" || true
    fi
    eza_colors=$_eza_colors_dark
    [[ $appearance == light ]] && eza_colors=$_eza_colors_light
    EZA_COLORS="$eza_colors" command eza -lh --icons=auto --color=auto \
        --group-directories-first --no-permissions --no-user --git "$@"
}

y() {
    local tmp cwd result
    tmp=$(mktemp -t yazi-cwd.XXXXXX) || return
    command yazi "$@" --cwd-file="$tmp"
    result=$?
    IFS= read -r cwd < "$tmp" || true
    command rm -f -- "$tmp"
    if [[ -n $cwd && $cwd != "$PWD" && -d $cwd ]]; then
        builtin cd -- "$cwd" || return
    fi
    return "$result"
}

# Preserve the Mac's prefix-history search and Alt-arrow word movement.
bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'
bind '"\e[1;3D": backward-word'
bind '"\e[1;3C": forward-word'

_juan_prompt_integration() {
    local appearance=dark title path host encoded='' char i
    if [[ -r $HOME/.cache/appearance ]]; then
        IFS= read -r appearance < "$HOME/.cache/appearance" || true
    fi
    if [[ $appearance == light ]]; then export COLORFGBG='0;15'
    else export COLORFGBG='15;0'; fi
    [[ -t 1 && ${TERM:-dumb} != dumb ]] || return 0

    # A multiplexer owns the inner terminal even when Kitty hosts its client.
    # Report inner-shell CWD/prompt markers rather than relying on outer Kitty.
    if [[ -n ${TMUX:-} || ${HERDR_ENV:-} == 1 || -z ${KITTY_PID:-} ]]; then
        path=$PWD
        host=${HOSTNAME//[^a-zA-Z0-9.-]/}
        local LC_ALL=C
        for ((i=0; i<${#path}; i++)); do
            char=${path:i:1}
            case "$char" in
                [a-zA-Z0-9/._~-]) encoded+=$char ;;
                *) printf -v char '%%%02X' "'$char"; encoded+=$char ;;
            esac
        done
        printf '\e]7;file://%s%s\e\\' "$host" "$encoded"
        printf '\e]133;A\e\\'
    fi
    title=${PWD/#$HOME/\~}
    title=${title//[[:cntrl:]]/}
    printf '\e]0;bash - %s\e\\' "$title"
}
# PROMPT_COMMAND can be a string or an array; keep other integrations intact.
if [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == 'declare -a '* ]]; then
    _juan_has_prompt_hook=0
    for _juan_hook in "${PROMPT_COMMAND[@]}"; do
        [[ $_juan_hook == _juan_prompt_integration ]] && _juan_has_prompt_hook=1
    done
    ((_juan_has_prompt_hook)) || PROMPT_COMMAND+=(_juan_prompt_integration)
    unset _juan_has_prompt_hook _juan_hook
elif [[ ${PROMPT_COMMAND:-} != *'_juan_prompt_integration'* ]]; then
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }_juan_prompt_integration"
fi
