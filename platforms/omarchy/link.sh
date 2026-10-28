#!/usr/bin/env bash
# Selective Linux deployment, never the legacy root/macOS Stow package.
set -euo pipefail
[[ $(uname -s) == Linux ]] || { printf 'This overlay is Linux-only.\n' >&2; exit 1; }
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
state="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-migration"
backup="$state/backups/link-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
chmod 700 "$state" "$state/backups" "$backup"
link_file() {
    local source=$1 relative=$2 target="$HOME/$2"
    if [[ -L $target && $(readlink -f -- "$target") == "$source" ]]; then return; fi
    if [[ -e $target || -L $target ]]; then
        mkdir -p "$backup/$(dirname -- "$relative")"
        mv -- "$target" "$backup/$relative"
    fi
    mkdir -p "$(dirname -- "$target")"
    ln -sr -- "$source" "$target"
    printf '%s -> %s\n' "$target" "$source"
}
for relative in .config/nvim .config/shell .config/stylua .config/ruff .config/yazi .markdownlint.jsonc; do
    link_file "$repo/$relative" "$relative"
done
# Herdr: ~/.config/herdr is Herdr's runtime directory (sockets, logs, session
# state), so only the shared config file is linked into it. The lastfocus and
# labels plugins beside it are registered by path, once each:
#   herdr plugin link ~/.dotfiles/.config/herdr/lastfocus
#   herdr plugin link ~/.dotfiles/.config/herdr/labels
link_file "$repo/.config/herdr/config.toml" .config/herdr/config.toml
# Mail: the aerc keybindings/query map/stylesets, the w3m keymap and the
# platform-neutral sync/filing helpers are shared with the Mac. The
# Linux-specific aerc.conf, accounts.conf, isyncrc, msmtp, notmuch and the
# systemd timer come from the overlay (linked by the generic loop below).
# ~/.config/aerc stays a real directory so both sources can coexist in it.
for relative in .config/aerc/binds.conf .config/aerc/notmuchmap.conf \
    .config/aerc/stylesets .w3m/keymap \
    .local/bin/mailsync .local/bin/mailsync-push .local/bin/notmuch-new-locked \
    .local/bin/notmuch-unified-file .local/bin/aerc_unified_journal.py; do
    link_file "$repo/$relative" "$relative"
done
# Link only tracked startup/config files, never IPython history/db/security.
while IFS= read -r -d '' file; do
    link_file "$repo/$file" "$file"
done < <(git -C "$repo" ls-files -z -- .ipython)
# Keep Pi's real Linux agent directory and credentials/history/cache intact.
# Only authored resources are shared with the Mac's XDG-layout source.
mkdir -p "$HOME/.pi/agent"
chmod 700 "$HOME/.pi/agent"
for name in AGENTS.md keybindings.json models.json; do
    link_file "$repo/.config/pi/agent/$name" ".pi/agent/$name"
done
for kind in skills extensions themes; do
    mkdir -p "$HOME/.pi/agent/$kind"
    for source in "$repo/.config/pi/agent/$kind/"*; do
        [[ -e $source ]] || continue
        link_file "$source" ".pi/agent/$kind/$(basename -- "$source")"
    done
done
# npm/, git/, sessions/, auth.json and model caches never link into the repo.
# Link complete theme directories, NOT their individual files. Omarchy copies
# theme files to a differently nested staging path; relative file links would
# break there. Directory links expose ordinary files for that copy operation.
for relative in .config/omarchy/themes/everforest .config/omarchy/themes/everforest-light; do
    link_file "$repo/platforms/omarchy/home/$relative" "$relative"
done
# Kanata is one unit (keymaps, guard daemons, tests, README, the staged copies
# that kanata-install-system installs under /etc), so link the directory.
link_file "$repo/platforms/omarchy/home/.config/kanata" .config/kanata
# User-owned Omarchy plugins also need ordinary files inside the plugin root.
omarchy_plugins="$repo/platforms/omarchy/home/.config/omarchy/plugins"
if [[ -d $omarchy_plugins ]]; then
    for source in "$omarchy_plugins/"*; do
        [[ -d $source ]] || continue
        link_file "$source" ".config/omarchy/plugins/$(basename -- "$source")"
    done
fi
# Keystroke permits a linked extension root, but no symlinks inside an extension.
# Link the complete self-contained directory, just as we do for theme assets.
keystroke_extensions="$repo/platforms/omarchy/home/.local/share/keystroke/extensions"
if [[ -d $keystroke_extensions ]]; then
    for source in "$keystroke_extensions/"*; do
        [[ -d $source ]] || continue
        link_file "$source" ".local/share/keystroke/extensions/$(basename -- "$source")"
    done
fi
# Everything else in an overlay root is linked file by file, so real
# directories such as ~/.config/aerc or ~/.local/share/applications can hold
# links from several sources. Subtrees linked as whole directories above are
# skipped; so are Python bytecode and .git (find does not honour .gitignore,
# and authored overlay files may legitimately be uncommitted).
link_tree() {
    local root=$1 file
    [[ -d $root ]] || return 0
    while IFS= read -r -d '' file; do
        link_file "$file" "${file#"$root/"}"
    done < <(find "$root" \( -name __pycache__ -o -name .git \) -prune -o -type f \
        ! -path '*/.config/kanata/*' \
        ! -path '*/.config/omarchy/themes/*' \
        ! -path '*/.config/omarchy/plugins/*' \
        ! -path '*/.local/share/keystroke/extensions/*' -print0)
}
link_tree "$repo/platforms/omarchy/home"
# Mail account configs (addresses and logins, never passwords) stay out of the
# public repo; the private companion repo mirrors the overlay layout.
private="${DOTFILES_PRIVATE_DIR:-$HOME/.dotfiles-private}"
link_tree "$private/omarchy/home"
# aerc refuses to start if accounts.conf is group/world-readable (it assumes
# the file may hold passwords; ours does not). Git only records the
# executable bit, so a fresh clone yields 0644 -- tighten the link target.
accounts="$private/omarchy/home/.config/aerc/accounts.conf"
if [[ -f $accounts ]]; then
    chmod 600 "$accounts"
else
    printf 'Note: %s not found; mail is not configured on this machine.\n' "$accounts" >&2
fi
printf '%s\n' "$backup" > "$state/link-backup-path"
printf '\nBackup of replaced paths: %s\n' "$backup"
printf 'Next: everforest dark; hyprctl reload; hyprctl configerrors\n'
