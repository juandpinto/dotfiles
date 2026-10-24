# Omarchy Bash foundation, followed by Juan's portable interactive helpers.
[[ $- == *i* ]] || return

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export EDITOR=nvim
export VISUAL=nvim
export SUDO_EDITOR=nvim
# Normalize the earlier Linux checkout name in already-running shells too.
if [[ -z ${DOTFILES_DIR:-} || $DOTFILES_DIR == "$HOME/dotfiles" ]]; then
    export DOTFILES_DIR="$HOME/.dotfiles"
fi
export STARSHIP_CONFIG="$HOME/.local/state/omarchy/current/theme/starship.toml"

# Do not duplicate mise/Starship/fzf/zoxide hooks on a manual `source ~/.bashrc`.
if [[ ${_JUAN_OMARCHY_BASH_READY:-0} != 1 ]]; then
    source "${OMARCHY_PATH:-/usr/share/omarchy}/default/bash/rc"
    _JUAN_OMARCHY_BASH_READY=1
fi
source "$XDG_CONFIG_HOME/shell/interactive.bash"
