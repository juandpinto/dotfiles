# Mail on Omarchy (aerc + mbsync + msmtp + notmuch)

Local, TUI-driven mail for iCloud+ and Gmail: mbsync keeps a Maildir under `~/mail` in sync with each provider over real IMAP (so every archive/trash is a server-side operation visible from any other client), notmuch indexes it for search and a unified inbox, msmtp sends, and aerc is the frontend. The backend is frontend-agnostic.

This is the Linux port of the Mac setup documented in [`Archive/mail-setup-macos.md`](../../Archive/mail-setup-macos.md) (recovered history, read it for the *why* behind the unified-tab filing helper, the lost-sent-replies fix and the aerc watcher saga). Search/filter semantics are in [mail-search.md](mail-search.md). Unlike the Mac, **every config file here is tracked**: the Mac's untracked `accounts.conf`/`isyncrc`/`msmtp`/`notmuch` configs survived only because of a one-off backup. None of them contain secrets, but the four account configs do contain email addresses and logins, so they live in the **private companion repo** (`~/.dotfiles-private`, same `omarchy/home/` layout) rather than this public one; `link.sh` links them when that repo is present. The addresses below are therefore written as placeholders.

## Accounts

- **iCloud+** (`icloud`): login is the Apple ID (`<icloud-login>`); the default From is our primary custom-domain address, and the family address, a second personal domain and, provisionally, two addresses on a third domain are custom-domain aliases on this one mailbox. msmtp's `from %F` sends with whatever ends up in From:.
- **Gmail** (`gmail`): `<gmail-login>`, single identity. Only a curated set of label-folders is synced (Inbox, Archive=All Mail, Sent, Drafts, Trash, Spam) to avoid label duplication.
- **unified**: notmuch virtual account over both; the tab aerc opens on. Virtual folders come from `notmuchmap.conf`.

**The third-domain aliases are unverified.** That domain's MX points at iCloud, and iCloud+ custom domains are aliases on the owning Apple ID, so they are configured as aliases. After the first full sync, confirm with `notmuch search to:<alias>` that such mail is in `~/mail/icloud/`. If nothing shows up although mail was received, the domain belongs to a different Apple ID: add a second `IMAPAccount`/`MaildirStore`/`Channel` block, msmtp account and aerc account for it, and drop the two aliases.

## Where everything lives

| Component                                  | Path                                                                                                               | Source                      |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------ | --------------------------- |
| Maildir (mail itself)                      | `~/mail/`                                                                                                          | runtime, never in Git       |
| notmuch index                              | `~/mail/.notmuch/`                                                                                                 | runtime                     |
| mbsync config                              | `~/.config/isyncrc`                                                                                                | private repo                |
| msmtp config                               | `~/.config/msmtp/config`                                                                                           | private repo                |
| notmuch config                             | `~/.config/notmuch/default/config`                                                                                 | private repo                |
| aerc accounts                              | `~/.config/aerc/accounts.conf`                                                                                     | private repo                |
| aerc main config (hooks, filters, openers) | `~/.config/aerc/aerc.conf`                                                                                         | overlay (Linux copy)        |
| aerc keybindings, query map, stylesets     | `~/.config/aerc/{binds.conf,notmuchmap.conf,stylesets/}`                                                           | shared root `.config/aerc/` |
| w3m keymap (HTML view scrolling)           | `~/.w3m/keymap`                                                                                                    | shared root                 |
| sync script                                | `~/.local/bin/mailsync`                                                                                            | shared root                 |
| push-on-move hook script                   | `~/.local/bin/mailsync-push`                                                                                       | shared root                 |
| unified-tab archive/trash/undo             | `~/.local/bin/notmuch-unified-file`, `aerc_unified_journal.py`                                                     | shared root                 |
| serialized `notmuch new`                   | `~/.local/bin/notmuch-new-locked`                                                                                  | shared root                 |
| To/Cc/From address completion              | `~/.local/bin/aerc-address-book`                                                                                   | overlay                     |
| mailto: handler, Super+Shift+E             | `~/.local/bin/aerc-open`, `~/.local/share/applications/aerc-open.desktop`                                          | overlay                     |
| background sync                            | `~/.config/systemd/user/mailsync.{service,timer}`                                                                  | overlay                     |
| logs                                       | `journalctl --user -u mailsync`, `-t mailsync-push`; `~/.local/state/mail/*.log`; `~/.local/state/msmtp/msmtp.log` | runtime                     |
| undo journal                               | `~/.local/state/aerc/unified-move-undo/`                                                                           | runtime                     |

`~/.config/aerc` is a real directory holding links from the private repo, the overlay and the shared root, which is why `link.sh` links its files individually. `link.sh` also `chmod 600`s the private repo's `accounts.conf`: aerc refuses to start when that file is group/world-readable ("too open permissions ... it contains passwords"—a blanket check, ours has none), it stats through the symlink, and Git does not preserve a 0600 mode, so a fresh clone needs this re-applied.

Not ported from the Mac: the launchd plists, the 20-second `notmuch-reindex` timer, `aerc-refresh-view`, the `SASL_PATH` Homebrew workaround, and the locally patched aerc build (see "Differences from the Mac").

## Secrets

Passwords live in gnome-keyring and are read through `secret-tool` (the Secret Service D-Bus API). gnome-keyring is started and unlocked by PAM at login, so interactive runs and the systemd timer both get the password silently. Both apps use app-specific passwords (no OAuth), and IMAP and SMTP share the same one per provider, so there are exactly two items:

```bash
secret-tool store --label='Mail: iCloud app password' mail-account icloud
secret-tool store --label='Mail: Gmail app password' mail-account gmail
# verify (prints the secret):
secret-tool lookup mail-account icloud
```

Paste the value from 1Password when prompted. Re-running `store` with the same attributes replaces the item. The attribute `mail-account` is the only key; it matches the mbsync/msmtp/aerc account names.

Why not `pass`+GPG as on the Mac: the old GPG key was never backed up and is gone, `pass` would still need a once-per-boot pinentry prompt for the background timer, and gnome-keyring is the Linux equivalent of the macOS Keychain the Mac setup originally wanted. Caveat: with Omarchy's autologin the keyring has no password of its own and is stored in gnome-keyring's plaintext format, so its protection is the LUKS disk encryption plus the lock screen, the same boundary as a `0600` file. If autologin is ever disabled, gnome-keyring encrypts it with the login password and PAM still unlocks it.

## First-time setup

```bash
omarchy pkg add aerc isync msmtp notmuch w3m   # all in [extra]
git clone <private-remote> ~/.dotfiles-private && chmod 700 ~/.dotfiles-private
~/.dotfiles/platforms/omarchy/link.sh          # links configs, scripts, units
mkdir -p ~/mail/icloud ~/mail/gmail ~/.local/state/msmtp ~/.local/state/mail
secret-tool store --label='Mail: iCloud app password' mail-account icloud
secret-tool store --label='Mail: Gmail app password' mail-account gmail
mbsync -l icloud && mbsync -l gmail            # list server folders: auth + folder names OK?
notmuch config get database.path               # expect /home/<you>/mail
```

Then the initial download, **by hand, before enabling the timer or opening aerc** (it ran for hours on the Mac; the index would otherwise go stale for the whole run and aerc shows "could not get MessageInfo" for files mbsync renames under it):

```bash
mbsync -a; echo "mbsync exit: $?"   # 0 = every channel clean; non-zero = at least one transient error
mbsync -a                           # second pass should be quick and show only +0/0 counts
notmuch new
systemctl --user daemon-reload
systemctl --user enable --now mailsync.timer
systemctl --user list-timers mailsync.timer
aerc
```

How to tell the backfill is done: `mbsync -a` returns to the prompt with exit status 0, a second run finishes in seconds with `N: +0/0` for every channel, and every synced folder has a `.mbsyncstate` file (`find ~/mail -name .mbsyncstate | wc -l` equals the folder count). A non-zero exit during a multi-hour run is usually one transient IMAP timeout on one channel, not a failed download: everything else is already on disk and a rerun picks up only what is missing. Do not chain `mbsync -a && notmuch new` for the first run for that reason—the `&&` silently skips the index build on any such hiccup.

First-launch checks:

1. `mbsync -l icloud` shows exactly `INBOX`, `Archive`, `Sent Messages`, `Drafts`, `Junk`, `Deleted Messages`; binds.conf and notmuchmap.conf hard-code those names.
2. **Send a test message from the `unified` tab** and confirm a new file lands in `~/mail/icloud/Sent Messages/cur/`. The `copy-to = icloud/Sent Messages` fix was reasoned from the aerc-notmuch(5) docs and never verified against a live send on the Mac. Also confirm one line was appended to `~/.local/state/mail/aerc-mail-sent.log`.
3. Archive one message from `unified` (`a`), check `journalctl --user -t mailsync-push` and `~/.local/state/mail/notmuch-unified-file.log`, then `u` to undo it.
4. Open an HTML message, cycle to the HTML part with `Ctrl+j`, confirm w3m renders and that a link click fails (network namespace isolation working); `Ctrl+l` opens it in the browser instead. `o` on an HTML part opens it in the browser via the `.html` rename.
5. Verify the third-domain aliases as described under "Accounts".

## Day-to-day

- `mailsync` from any shell, or `Ctrl+r` in aerc, or just wait for the timer. All three run the same `mailsync.service`; systemd refuses to overlap it, so nothing can collide.
- `?` in aerc lists the live keybindings. Highlights: `tu`/`ti`/`tg` jump to a tab; `a`/`A` archive, `d`/`D` trash (permanent delete only inside Trash/Spam/Junk, with a prompt on `d`); `u` undoes the last unified archive/trash to the exact original folder; `F` flags; `rr`/`rq` reply-all (quoted); `s`/`S` split preview with `Zj`/`Zk` to scroll it; `zj`/`zk` move by a count.
- `~/.local/bin/notmuch-unified-file` does the unified tab's archive/trash: aerc's own `:archive`/`:move` on a notmuch account have one static destination with no idea which real account a message belongs to and once mis-filed mail into a bogus `~/mail/Archive/`. The helper resolves each message's real file via notmuch, moves it into that account's own Archive/Trash, journals the move for `u`, reindexes under the shared lock and kicks a targeted mbsync push.
- Address completion in To/Cc/From comes from `~/.local/bin/aerc-address-book` (the `address-book-cmd` of every account). It suggests people you have written to (recipients of mail sent from any `user.*_email` in the notmuch config) and people who have written to you. Results must contain every typed word, matched as word prefixes in any order, and are ranked by how often you have written to them, then how often they have written to you. No-reply addresses are dropped. A bare `notmuch address` query cannot do this. It matches *messages*, not addresses, so `to:ju*` matched all mail addressed to Juan and listed every sender in the mailbox. It also returns results in an unspecified order with `--deduplicate=address`, and aerc keeps only the first 100 lines without filtering them.
- Status: `systemctl --user status mailsync.timer mailsync.service`, `journalctl --user -u mailsync -n 50`, `journalctl --user -t mailsync-push -n 50`.

## Default mail client

aerc opens `mailto:` links and replaces Omarchy's HEY web app on `Super+Shift+E` (open or focus aerc) and `Super+Shift+Alt+E` (new message). All three go through `~/.local/bin/aerc-open`. If aerc is running, it hands the link to that instance over aerc's IPC socket (`$XDG_RUNTIME_DIR/aerc.sock`) and focuses its terminal window. Otherwise it starts aerc in a terminal (app ID `org.omarchy.aerc`) with the link. After `link.sh`, register the handler once:

```bash
update-desktop-database ~/.local/share/applications
xdg-mime default aerc-open.desktop x-scheme-handler/mailto
```

The packaged `aerc.desktop` can't be the handler: it sets `Terminal=true`, which `xdg-open` (what browsers call) ignores on Hyprland, so aerc would start without a terminal. Our `aerc-open.desktop` is hidden from the launcher, so the packaged entry stays the visible one. It launches through `uwsm-app -t service`, like `yazi.desktop`, because `xdg-open` waits for its handler to exit.

What `aerc-open` works around:

- **Closing aerc's window doesn't quit aerc.** aerc 0.22 (and upstream `master` as of October 2026) uses SIGHUP to reload its config, so when its terminal closes it keeps running without one, still holding the socket, and links handed to it vanish. `aerc-open` therefore first ends any aerc whose terminal is gone (SIGTERM, aerc's clean quit). Until the next `aerc-open`, such an aerc lingers in the background (about 250 MB). Quitting with `q` or `Ctrl+q` avoids it.
- **Percent-encoded addresses.** aerc decodes a link's `?query` but not the address before it, so `aerc-open` decodes the address (`mailto:jane%40example.org`).
- **Failures are visible.** A link aerc rejects produces a notification instead of nothing. An aerc without a window of its own (inside tmux or Herdr) still gets the link, with a notification that there is no window to focus.

New messages use the identity of the selected account tab (`unified` sends as iCloud); a link can choose with `?account=gmail`. Run `bash platforms/omarchy/tests/test_aerc_open.sh` for isolated checks with aerc, Hyprland and uwsm mocked.

## Differences from the Mac, and why

- **Stock aerc 0.22.0 from `extra`, not a local build.** The Mac's patched build existed mainly because aerc's macOS FSEvents watcher never delivered events; on Linux the notmuch worker watches the Xapian directory with inotify, and `notmuch new` creates/removes `flintlock` there, which is exactly what it listens for. Two small platform-neutral patches from the Mac branch are therefore *not* applied here:
    - `1d9fe56f notmuch: replace flags on unsolicited updates` (4 lines in `worker/notmuch/worker.go`). Without it, aerc OR-merges flags on external updates (`lib/msgstore.go`), so a flag *removed* elsewhere (read on the phone, unflagged) stays shown on the unified tab until the view is re-queried (switch folders/tabs). Known cosmetic staleness; a good candidate to send upstream via aerc's sr.ht mailing list.
    - `081f484d messages: add numbered list navigation`: see "Number column".
- **systemd instead of launchd**, and systemd is also the mutex and the logger: `check-mail-cmd` and the `aerc-startup` hook call `systemctl --user start mailsync.service`, hooks use `systemd-run`. This removed the `sleep`/redirect/backtick gymnastics in the Mac's hooks (and the `;`-truncation trap they were working around). The `mkdir` lock inside `mailsync` is kept for manual runs.
- **No 20-second reindex timer / scratch-query refresh.** Both existed for the broken macOS watcher and for the hours-long backfill. The backfill is done by hand here; after that, `mailsync`'s own `notmuch new` is enough.
- **gnome-keyring instead of pass/GPG** (see "Secrets"); **no `SASL_PATH` hack** (Apple's SASL plugin problem; the shared scripts only set it when the Homebrew dir exists).
- `[openers]` uses `xdg-open`; logs go to the journal and `~/.local/state/mail/` instead of `~/Library/Logs/`.
- w3m's network isolation is a real network namespace (`unshare --net`, aerc's shipped `html` filter) rather than an unreachable proxy.

## Number column (re-implementing later)

The Mac shows a 1-based `number` column and `zg` prompts for a number to jump to (`:select-line`). Both come from commit `081f484d` in the Mac's aerc checkout (`~/.local/src/aerc`, branch `local/fsevents-live-refresh`; also in the backup's `verification/aerc-all-refs.bundle`). The patch changes `app/msglist.go` (pass the list position `i+1` into `addMessage` instead of `len(table.Rows)`) and `commands/account/select.go` (adds `SelectLine`/`:select-line N`, 1-based). To get it back on Linux:

1. `pacman -S go` and clone/fetch upstream `https://git.sr.ht/~rjarry/aerc`; cherry-pick `081f484d` (and `1d9fe56f`) onto the tag Arch currently packages. Skip `629a9a66` (macOS-only FSEvents fix).
2. `make aerc PREFIX=/usr LIBEXECDIR=/usr/lib/aerc` with `GOFLAGS=-tags=notmuch` (needs the `notmuch` package for headers); install the binary as `~/.local/bin/aerc` so it precedes `/usr/bin/aerc` on `PATH` while the packaged filters/templates in `/usr/lib/aerc` and `/usr/share/aerc` keep being used.
3. In this `aerc.conf`, set `index-columns=number>5,flags:4,name<20%,subject,date>=` and `column-number={{.Number}}` in both `[ui]` and `[ui:account=unified]`.

The shared `binds.conf` still carries `zg = :prompt 'Go to message number:' select-line<Enter>`; it is dormant on stock aerc (the prompt accepts a number and then reports an unknown command) and works again once the patched binary is in place.

## Ideas not implemented

- **IMAP IDLE**: `goimapnotify` (AUR) can trigger `systemctl --user start mailsync.service` the moment new mail arrives, instead of waiting for the 3-minute poll.
- **Live dark/light**: aerc has `:reload -s <styleset>` and an IPC socket at `$XDG_RUNTIME_DIR/aerc.sock`; an Omarchy `theme-set.d` hook could switch the running session's styleset. Guard on the socket existing, because `aerc :cmd` with no running instance launches a new one.
- **University Exchange account**: needs OAuth2 (no basic auth); check tenant policy or front it with davmail. Purely additive: new mbsync/msmtp/aerc blocks.

## Known limitations

- No confirmation before `d`/`D` moves to Trash (recoverable; permanent delete does prompt).
- Flag-removal staleness on the unified tab (see above).
- The unified undo journal only covers moves made through `notmuch-unified-file`, not native `:move` on icloud/gmail, moves by other clients, or permanent deletes.
