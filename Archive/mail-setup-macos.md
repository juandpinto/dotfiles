<!--
RECOVERED HISTORICAL DOCUMENT -- macOS mail setup, as of 2026-08-15.

This was `~/mail/README.md` on the Mac. It was never tracked in Git and was
not included in the 2026-10-11 restore backup, so this copy was reassembled
on 2026-10-17 from pi session transcripts (the last full read on 2026-08-23
plus partial reads/edits from 2026-08-06 and 2026-08-14 for the sections
past the 50 KB read limit). Section order and text are faithful; the
"Viewing HTML email" section is the 2026-08-05 draft (later aerc.conf
comments cover the `[openers]`/`.ehtml` fix added afterwards). Do not edit
this file as live documentation: the current Linux setup is described in
`platforms/omarchy/mail.md`.
-->

# Mail setup

This is a local, TUI-driven mail setup for iCloud+ and Gmail, built around a
local Maildir backend that both stays fully synced with each provider over
real IMAP and gives full offline/local backup of everything. aerc is the TUI
frontend, but the backend (mbsync + msmtp + notmuch) is frontend-agnostic --
neomutt or any other Maildir/notmuch-aware client can point at the same data
without any changes.

None of this is tracked in `~/.dotfiles` for now, except aerc's `aerc.conf`
and `stylesets/` (pure theming, no account details). Everything else below is
a plain, real file living directly under `~/.config`, `~/.local/bin`,
`~/.local/src`, or `~/Library/LaunchAgents` -- untouched by stow, not synced
to other machines.
See "Where everything lives" below for the full breakdown.

## Architecture

- **mbsync (isync)** syncs each IMAP account to a local Maildir under
  `~/mail`. This is the local backup, and it's also what keeps everything
  correctly organized server-side: every archive/move/delete you do locally
  is a real IMAP operation, so Gmail's/iCloud's web UI and your phone's Mail
  apps all see the identical result -- there's no separate "app-only" state.
- **msmtp** sends outgoing mail.
- **notmuch** indexes the whole Maildir tree for fast cross-account search
  and a unified inbox.
- **aerc** is the TUI frontend, reading the same Maildir/notmuch data. The
  executable launched from the shell is a local build from
  `~/.local/src/aerc`, carrying one small macOS FSEvents patch that fixes
  live refresh for external notmuch/Maildir changes; Homebrew still supplies
  its runtime resources and dependencies.

## Accounts

**iCloud+** -- one mailbox, several send-as aliases

- IMAP/SMTP login is always the Apple ID, `<icloud-login>`.
- The primary custom-domain address, the family address, and a second
  personal-domain address are
  custom-domain aliases on that *same* mailbox (not separate accounts) --
  mail to any of them lands in the same Inbox, and any of them can be used
  as the From: address when sending.
- Default From: `Juan Pinto <primary-address>`. To send as
  `Pinto Family <family-address>` occasionally, just edit the From:
  field when composing -- msmtp's `from %F` setting (see
  `~/.config/msmtp/config`) uses whatever address ends up in the message,
  no separate account/identity config needed.

**Gmail** -- `<gmail-login>` (aerc/mbsync account name: `gmail`)

- Single identity, `Juan Pinto <gmail-login>`.
- Only one Gmail account for now; the backend is structured so more Gmail
  accounts (or the university Exchange account, see "Adding Exchange
  later") are just additional, independent account blocks.

## Where everything lives

| Component                           | Path                                                         | Tracked in dotfiles? |
|-------------------------------------|--------------------------------------------------------------|----------------------|
| Maildir (actual mail)               | `~/mail/`                                                    | No (never should be) |
| This file                           | `~/mail/README.md`                                           | No                   |
| Search/filter reference             | `~/mail/SEARCH.md`                                           | No                   |
| mbsync config                       | `~/.config/isyncrc`                                          | No                   |
| msmtp config                        | `~/.config/msmtp/config`                                     | No                   |
| notmuch config                      | `~/.config/notmuch/default/config`                           | No                   |
| aerc account list                   | `~/.config/aerc/accounts.conf`                               | No                   |
| aerc keybindings                    | `~/.config/aerc/binds.conf`                                  | Yes (symlink)        |
| aerc unified-inbox query map        | `~/.config/aerc/notmuchmap.conf`                             | Yes (symlink)        |
| aerc theming/filters/hooks          | `~/.config/aerc/aerc.conf`, `stylesets/`                     | Yes (symlink)        |
| Local aerc source + patched build   | `~/.local/src/aerc/`                                         | No                   |
| Local aerc build helper             | `~/.local/bin/aerc-fsevents-build`                           | Yes (symlink)        |
| Local `aerc` PATH override          | `~/.local/bin/aerc` -> `~/.local/src/aerc/aerc`              | No                   |
| Manual/scheduled sync script        | `~/.local/bin/mailsync`                                      | Yes (symlink)        |
| Instant push-on-move hook script    | `~/.local/bin/mailsync-push`                                 | Yes (symlink)        |
| Account-aware unified archive/trash | `~/.local/bin/notmuch-unified-file`                          | Yes (symlink)        |
| Unified undo journal library        | `~/.local/bin/aerc_unified_journal.py`                       | Yes (symlink)        |
| Manual legacy view-refresh helper   | `~/.local/bin/aerc-refresh-view`                             | Yes (symlink)        |
| Frequent independent reindex script | `~/.local/bin/notmuch-reindex`                               | Yes (symlink)        |
| Shared notmuch-new lock wrapper     | `~/.local/bin/notmuch-new-locked`                            | Yes (symlink)        |
| Background sync timer               | `~/Library/LaunchAgents/com.juanpinto.mailsync.plist`        | Yes (symlink)        |
| Background reindex timer            | `~/Library/LaunchAgents/com.juanpinto.notmuch-reindex.plist` | Yes (symlink)        |
| Sync logs                           | `~/Library/Logs/mailsync.{out,err}.log`                      | No (runtime output)  |

`~/.config/aerc` is a real directory (not a whole-folder symlink) precisely
so that `aerc.conf`/`stylesets/`/`binds.conf`/`notmuchmap.conf` can be
individually symlinked into the tracked dotfiles repo (at
`~/.dotfiles/.config/aerc/`) while `accounts.conf` stays local. The latter
contains personal account identities and machine-specific Maildir layout, so
it remains intentionally untracked even though it does not currently contain
plaintext credentials.

## Credentials

No OAuth, no token refresh, for either account currently configured --
both iCloud and Gmail (2FA enabled) support app-specific passwords, which are
static credentials that don't expire or need refreshing.

Secrets are never stored in any config file. `PassCmd` (mbsync) and
`passwordeval` (msmtp) both shell out to `pass` (password-store):

```
pass show email/<icloud-login>
pass show email/<gmail-login>
```

Each password is a GPG-encrypted file under `~/.password-store/`. The GPG
key (the primary address, Ed25519 signing + Curve25519 encryption, 2-year
expiration) uses `pinentry-mac` as its passphrase prompt
(`~/.gnupg/gpg-agent.conf`), with the passphrase saved to macOS Keychain
after the first unlock -- so both interactive use (aerc, manual `mailsync`)
and the unattended background launchd timer decrypt silently, with no
repeated prompts and no dependency on a third-party app's own lock state.

This setup previously used 1Password's `op` CLI instead, which worked but
rode on the desktop app's unlocked session -- fine for manual use, but it
turned out to prompt for biometric approval on every single invocation in
practice (including from aerc's own background hooks), which is exactly
what `pass`'s GPG-agent caching avoids. If you ever see 1Password-style
approval prompts again, something has reverted to the old `op read` calls
-- grep `~/.config/isyncrc` and `~/.config/msmtp/config` for `op read` to
confirm nothing regressed.

Two macOS-specific things worth knowing about if you ever rebuild this setup
from scratch:

- macOS ships its own proprietary SASL PLAIN plugin
  (`passwordserver_saslplugins`) that conflicts with isync/mbsync's PLAIN
  auth and fails with a cryptic "invalid parameter" error. Fixed by
  installing Homebrew's `cyrus-sasl` and setting
  `SASL_PATH=/opt/homebrew/opt/cyrus-sasl/lib/sasl2` (already baked into
  `mailsync`).
- Apple's newer "Passwords" app does not create classic `security`-compatible
  generic-password Keychain items the way Keychain Access used to -- this
  setup uses `pass`/GPG instead of the native Keychain for that reason (an
  earlier iteration used 1Password, since replaced -- see above).

## Usage

**Manual sync**, any time, including while aerc is open:

```
mailsync
```

Runs `mbsync -a` (pull/push every configured account) then `notmuch new`
(re-index). Safe to run concurrently with the background timer or with
itself -- it holds a simple lock (`~/.local/state/mailsync.lock`) and skips
cleanly if another instance is already running, rather than piling up
blocked processes. The lock is self-healing: it records the holder's PID
and reclaims itself if that process is no longer actually alive, rather
than staying stuck forever -- added after a real incident where
`launchctl kickstart -k ...` (which sends `SIGKILL`, not catchable by the
script's own cleanup trap) killed a mid-run `mailsync` and left the lock
orphaned, silently skipping every scheduled sync for about two days with
no visible error anywhere except the same harmless "already running" line
repeating in `mailsync.err.log`. `Ctrl+r` inside aerc does the same thing
without leaving the TUI (`:check-mail`, wired to `mailsync` via
`check-mail-cmd` in `accounts.conf`).

**Background sync**: a launchd agent (`com.juanpinto.mailsync`) runs the
same `mailsync` script every 3 minutes and once at login/load. A second,
independent agent (`com.juanpinto.notmuch-reindex`) runs just `notmuch new`
every 20 seconds, regardless of how long any given `mailsync` run takes --
see "Keeping the notmuch index fresh during long syncs" below for why this
exists. Check status with:

**Refresh on launch**: aerc's own `aerc-startup` hook (in aerc.conf's
`[hooks]` section) fires `mailsync` the moment aerc's UI comes up, rather
than showing whatever's on disk from up to 3 minutes ago (the timer's
interval) with no indication it might be stale. Uses the same lock as
everything else above, so it can never collide with the timer or `Ctrl+r`.

**Correction to this section's earlier history**: this hook did not
actually work at all until a later session caught why. aerc.conf is
parsed with an ini library whose default inline-comment handling treats a
bare `;` or `#` *anywhere* in a value (not just at the start of a line,
with no awareness of shell syntax) as the start of a comment, silently
truncating everything after it -- confirmed directly via aerc's own
`log-level = trace` output in the sandboxed test environment (see
"Sandboxed testing environment" below), which showed the parsed hook
value cut short right at the first `;` separating `sleep 2` from the
actual `mailsync` call, with the truncated fragment then failing with a
shell syntax error on every single launch. Every earlier "confirmed
working" observation of this hook in this file's own history (a real
`mbsync -a` process appearing after opening aerc, a lock collision with
`Ctrl+r` behaving correctly, etc.) was actually the independent 3-minute
background timer coincidentally firing around the same time -- not this
hook, which was silently doing nothing useful the entire time. Fixed by
wrapping the value in backticks, which this ini library always treats as
literal quoting regardless of any option, confirmed via the same trace
logging to now parse and execute in full. A general warning about this
gotcha now lives at the top of aerc.conf's `[hooks]` section itself.

A real, separate race also turned up while testing this (independent of
the parsing bug above -- this one is a genuine timing race, not a config
mistake): aerc's own initial per-account folder listing at startup is not
synchronized with `aerc-startup` firing, so `mbsync` renaming a file
(maildir's ordinary `new/` -> `cur/` move) at the exact moment aerc is
mid-listing that same directory can leave an "error: could not get
MessageInfo" row in the message list. A `sleep 2` before `mailsync`
starts touching any files (giving aerc's own fast local listing a head
start) reduces how often this happens, but is deliberately not relied on
as a full fix -- a later, much deeper investigation found this specific
race is really just one manifestation of a considerably bigger gap in
aerc's own live-refresh mechanism, and the local FSEvents patch fixed
that instead (see "Fixed: aerc's macOS FSEvents watcher" below) -- which
also bounds how long this specific race's visible
error can persist, without needing a dedicated safety net right in this
hook.

```
launchctl list | grep mailsync
launchctl list | grep notmuch-reindex
```

Reload after editing the plist:

```
launchctl bootout gui/$(id -u)/com.juanpinto.mailsync
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.juanpinto.mailsync.plist
```

**Launching aerc**: just `aerc`. Three accounts/tabs are configured:
`icloud`, `gmail`, and `unified` (notmuch-backed, cross-account
search, plus virtual folders for Inbox/Flagged/Sent/Drafts/Archive/Trash/Spam/
All -- see `notmuchmap.conf` for the full list). Jump to the unified inbox
from anywhere with `tu`.

**To/Cc autocomplete**: harvested directly from mail already indexed by
notmuch (`notmuch address`) -- no contacts/CardDAV sync involved. Just start
typing an address when composing.

**Archive vs. delete/trash**: `a`/`A` archives (moves out of Inbox, matches
each provider's native "archive" behavior). `d`/`D` moves to Trash instead of
permanently deleting, *except* while already browsing Trash/Deleted
Messages/Junk/Spam, where `d`/`D` reverts to a real permanent delete (with a
confirmation prompt on lowercase `d`). This is on top of
`restrict-delete = true` in `accounts.conf`, which refuses outright
permanent-delete commands outside those folders as a second safety net.

## Keybindings

aerc is vim-inspired by default, and that's kept intact -- `binds.conf` only
changes the archive/trash/delete behavior described above, adds `ti`/`tg`/`tu`
for jumping directly to a tab by name, adds `Ctrl+r` to sync on demand, adds
count prompts and split-preview pager controls, and upgrades link-following
(see below). Pressing `?` inside aerc at any time pops up a live,
context-aware list of whatever's actually bound at that moment, which is
always accurate, unlike this static reference.

Global (works everywhere):

- `Ctrl+p` / `Ctrl+n`, or `[t` / `]t` -- previous/next tab
- `Ctrl+t` -- open a terminal tab
- `ti` / `tg` / `tu` -- jump straight to the icloud / Gmail / unified tab,
  regardless of which one currently has focus (`unified` is also the tab
  aerc opens on by default -- see accounts.conf's account order)
- `Ctrl+r` -- manually trigger a sync right now (`:check-mail`, runs the same
  lock-guarded `mailsync` script as the background timer)
- `Ctrl+c` / `Ctrl+q` -- quit (with confirmation prompt)
- `Ctrl+z` -- suspend

Message list (real vim bindings throughout):

- `j` / `k` -- next/previous message
- `Ctrl+d` / `Ctrl+u` -- half-page down/up
- `Ctrl+f` / `Ctrl+b` -- full page down/up
- `g` / `G` -- jump to top/bottom of the list
- `zg`, then a one-based number and `Enter` -- jump to that displayed message
  number
- `zj`, then `N` and `Enter` / `zk`, then `N` and `Enter` -- move forward /
  backward by `N` messages; aerc does not implement generic Vim count prefixes
  such as `42G` or `10j`
- `s` / `S` -- toggle the horizontal / vertical preview split; `:vsplit N`
  explicitly makes the list `N` columns wide
- With a split open, `Zj` / `Zk`, `ZCtrl+d` / `ZCtrl+u`, and `Zg` / `ZG` send
  line, half-page, top, and bottom motions to the preview pager without giving
  up normal list navigation
- `J` / `K` -- next/previous folder
- `H` / `L` -- collapse/expand folder
- `v` / `Space` -- mark a message (space also advances to the next one)
- `V` -- invert marks
- `T` -- toggle threaded view (threading is on by default -- see "Message
  threading" below)
- `za` / `zo` / `zc` / `zM` / `zR` -- fold/unfold a thread, all threads (vim's
  own fold commands, same letters)
- `zz` / `zt` / `zb` -- center/top/bottom the selected message (also straight
  from vim)
- `/` -- search; `n` / `N` -- next/previous search result (see
  `~/mail/SEARCH.md` for the full picture -- behavior genuinely differs
  between the Maildir tabs and the notmuch-backed unified tab)
- `\` -- filter results further
- `Esc` -- clear search/filter
- `Enter` -- open the selected message
- `c` -- jump to a folder by name

Reading/replying:

- `a` / `A` -- archive (single / whole thread)
- `d` / `D` -- move to Trash (single / whole thread); see "Archive vs.
  delete/trash" above
- `u` on `unified` -- undo the newest journaled unified archive/trash action,
  restoring its exact original folder; see "Undoing the last unified file
  action" below
- `F` -- toggle the flagged state (`:flag -t`; works in the message list
  and viewer)
- `C` / `m` -- compose new
- `rr` -- reply-all, `rq` -- reply-all with quote, `Rr` -- reply (sender
  only), `Rq` -- reply with quote
- `f` (in message viewer) -- forward
- `b` -- bounce/redirect

Message viewer:

- `q` -- close
- `o` / `O` -- open attachment/part
- `H` -- toggle full headers
- `J` / `K` -- next/previous message
- `Ctrl+j` / `Ctrl+k` -- next/previous MIME part
- `Ctrl+y` / `Ctrl+l` -- copy/open a link from the message (see "Viewing
  HTML email and following links" below)

Composing:

- `Tab` / `Shift+Tab` -- next/previous field
- `Alt+p` / `Alt+n` -- switch account while composing

Review screen (right before sending):

- `y` -- send
- `n` -- abort (discard, no confirmation)
- `p` -- postpone (save as draft)
- `e` -- edit again
- `a` / `d` -- attach/detach a file

Two gaps worth knowing about: there's no confirmation prompt before `d`/`D`
move a message to Trash in the general case (only permanent delete inside
Trash/Spam prompts first, and this applies equally on `unified`'s
pipe-based trash), and links clicked directly in the w3m HTML view
won't load (by design -- see "Viewing HTML email and following links" below
for the actual way to open them).

### Fixed: trash/archive from the unified tab (custom account-aware filing)

aerc's built-in `:archive`/`:move` on a notmuch-backed account like `unified`
resolve their destination from a single *static* per-account config value
(`archive =`, defaults to bare `"Archive"`) -- they have no per-message
awareness of which real account (icloud vs Gmail) a message actually came
from. This was discovered the hard way: after fixing an earlier aerc 0.21.0
bug that made every move/archive/delete fail outright (its notmuch worker
only enables file-organizing support if an account sets a `maildir-store`
parameter, which ours never had -- fixed by upgrading to 0.22.0, which
auto-discovers this instead), archive started "working" but was actually
silently mis-filing every message into a brand-new, bogus top-level
`~/mail/Archive/` folder -- orphaned from both real accounts and invisible
to `mbsync` (not part of any configured channel), so it would never reach
the server's real Archive.

This wasn't caught by inspection -- two real messages actually went through
this path during testing. Both were identified (by `To:` header, both were
to the primary address, an icloud alias), recovered by hand, and verified safe:
the background historical-backfill sync had been holding the sync lock the
whole time, so nothing had reached the server yet. Had that not been true,
the messages would still have been fully recoverable locally (the files
aren't destroyed, just misplaced) -- but would have vanished from the real
server Inbox with no corresponding copy in the server's real Archive until
manually re-uploaded.

**The fix**: since this can't be solved through config (there's no way to
make one static `archive =` value resolve differently per message), `a`/
`A`/`d`/`D` on `unified` are wired to `~/.local/bin/notmuch-unified-file`
via `:pipe -mb` instead of aerc's own archive/move. For each message piped
in, it looks up that message's *actual current* file location via notmuch
(ground truth, regardless of which tab it's being viewed from), infers its
real account from that path, and moves it into that account's own real
Archive/Trash folder -- stripping mbsync's `,U=<n>` UID suffix the same way
aerc's own maildir backend does (so mbsync treats it as a fresh upload
rather than a broken sync target), then pushing a targeted sync so the
change reaches the server promptly. `-b` means it's silent on success and
surfaces a status-bar error if it fails (aerc checks the exit code); either
way, full detail is logged to `~/Library/Logs/notmuch-unified-file.log`.

Verified end-to-end against real mail (`mbsync -V` showing zero remaining
difference between local and server after a real archive), then hardened
and tested against a battery of edge cases in an isolated sandbox (separate
scratch notmuch database, not the real mailbox) before trusting it broadly:
missing Message-ID, re-filing an already-correctly-filed message (a genuine
no-op, not treated as an error), a multi-message bulk/thread operation
spanning both accounts at once, a message vanishing mid-operation (a race
against a concurrent sync -- confirmed to happen for real during testing,
not just theoretical), the same race inside a larger batch (the rest of the
batch still completes), a destination-filename collision (fails safely,
never overwrites), and a message under an unrecognized account path. Each
failure mode logs clearly and exits non-zero without ever losing or
overwriting a message; a single bad message in a bulk operation can't abort
processing of the rest of the batch.

**Perceived speed**: archiving/trashing from `unified` felt noticeably
slower than on the real account tabs -- "Fetching messages..." would sit
for a few seconds before the message disappeared. Two things contribute:
`:pipe` genuinely has to fetch the *entire* message body first (there's no
lighter-weight "just the headers/UID" option for custom keybindings in
aerc, confirmed against the source), and -- the larger, fixable factor --
the script originally ran its post-move `mbsync` push *synchronously*,
which involves a real network connection (fresh TLS+SASL handshake to
iCloud/Gmail each time) that routinely takes 1-3+ seconds -- and aerc's
`:pipe -b` doesn't update its status bar until the whole piped command
exits. Fixed: the sync push is now spawned as a fully detached background
process (`start_new_session=True`, the same pattern aerc's own hooks use)
rather than waited on, so the script itself returns as soon as the local
move + reindex finishes -- confirmed via timing in the same isolated
sandbox: 0.13-0.16s per action (single or multi-account) instead of
several seconds, while the actual sync continues correctly in the true
background afterward.

**But that fix immediately surfaced a second, real bug**: making the
script fast enough exposed a lock-coordination gap that had been there all
along. Four independent scripts each call `notmuch new` on their own
schedule (`mailsync` every ~3 minutes, the new `notmuch-reindex` every 20
seconds, `mailsync-push` on every native archive/trash, and
`notmuch-unified-file` on every unified-tab action) -- but notmuch's Xapian
backend only allows one writer at a time; a second `notmuch new` while one
is already running fails outright rather than queuing, and none of these
scripts checked for that. A silent failure there leaves the *file* moved
but the *index* stale, which is exactly what this looked like: the message
wouldn't disappear from `unified` until switching tabs and back (forcing
aerc to re-run its query against whatever the index happened to look like
by then, possibly many seconds later once some *other* script's next
scheduled reindex finally caught up). This was always a possible collision
-- it just became far more likely to actually manifest once
`notmuch-unified-file` itself got fast, since before, its own multi-second
synchronous sync delay incidentally gave the 20-second reindex timer more
room to avoid overlapping.

**Fix**: `~/.local/bin/notmuch-new-locked` is now the single, shared entry
point for every `notmuch new` call across all four scripts -- a small
wrapper that takes a lock (waiting up to ~10s for its turn, not failing on
contention) before reindexing, so two callers can never collide at the
Xapian level in the first place. Confirmed via a forced-contention test
(one caller holding the lock artificially) that a second caller correctly
waits for its turn and the message still ends up correctly filed and
indexed, rather than silently missing the reindex.

**This still wasn't the actual bug.** After fixing the lock coordination,
the view *still* didn't update until switching tabs and back -- every
time, deterministically, not a rare race. Tracing aerc's own notmuch
worker source found the real cause: when files change *externally* (as
this script does, moving files directly rather than through aerc's own
action dispatch), the only thing that notices is a filesystem watcher on
the notmuch database. That watcher's update logic
(`updateChangedMessages`) only emits per-message updates for messages that
*changed and still match* the currently-active query -- a message that
moved *out* of the query (e.g. archived out of Inbox) is specifically
excluded, since it no longer matches. The other half of that same update
path (`updateDirCounts`) does set a `Refetch` flag when the active query's
directory count changes, but reading its handler on the UI side
(`dirlist.Update`) shows it only re-sorts the already-cached message list --
it does not actually refetch content from the backend, despite the name.
Neither path was ever designed to handle "this message stopped matching",
only "this message changed" -- which is exactly why manually switching
tabs and back fixed it: that goes through a completely different path
(`:cf`'s `dirlist.Open`) that does a real refetch unconditionally.

**Fix**: aerc has a Unix socket IPC interface (confirmed against the
source, `~/Library/Application Support/aerc.sock` on macOS) that accepts
arbitrary `:` commands against the already-running instance -- this is
what lets `aerc mailto:...` open a compose window in an existing session
instead of starting a new one. The script now implements this protocol
directly in Python (a small JSON request over the socket) rather than
shelling out to the `aerc` binary itself, specifically because running
`aerc ":some-command"` falls back to *starting a whole new aerc instance*
if no socket is currently reachable -- a real risk for a background
script that has no reason to ever launch a fresh TUI session. This was the
former pre-patch refresh path; the local FSEvents patch below now lets aerc
notice the reindexed move natively, so the helper no longer makes an IPC
refresh call at all.

### Undoing the last unified file action

`u` in the `unified` message list or viewer runs a durable, one-step local
undo. Each `a`/`A`/`d`/`D` helper action writes an owner-only transaction under
`~/.local/state/aerc/unified-move-undo/` before a file is renamed, records
progress after every rename, and treats a marked/thread batch as one action.
The journal records the exact original path, account, destination path,
Message-ID, and content digest. Thus `u` returns every successfully moved
file in the newest group to its original folder, not merely to Inbox.

An interrupted forward or reverse rename is reconciled from the saved content
digest on the next action. Before undoing, the helper preflights the entire
group and refuses to overwrite an original path, choose between multiple
matching files, or move a message whose content changed. A failed/ambiguous
undo therefore leaves mail untouched and logs the reason instead of guessing.
After a successful undo it uses the existing locked `notmuch new` and targeted
sync path, so the patched watcher updates aerc normally.

The journal currently covers only actions routed through
`notmuch-unified-file`: unified archive and normal Trash moves. It cannot
retroactively undo a native iCloud/Gmail `:move`, a move made by another mail
client or mbsync, or permanent deletion from Trash/Spam/Junk. Its transaction
format is folder-agnostic, so a future journal-aware unified move-to-folder
command can receive the same exact-folder undo behavior without changing the
journal design. The state directory is runtime data and deliberately remains
untracked.

### Fixed: the same archive/trash gap also existed in the message viewer

The fix above only covered the message *list* context (`[messages]`/
`[messages:account=icloud]`/`[messages:account=unified]` in binds.conf) --
the message *viewer* (`[view]`, active while a message is actually open,
not just highlighted in the list) still had the old, generic bindings:

```
[view]
d = :move Trash<Enter>
D = :move Trash<Enter>
A = :archive flat<Enter>
```

This surfaced as two different real errors when deleting a currently-open
message:

- On `icloud`: `could not move message ...: rename .../Inbox/cur/... ~/mail/`
  -- iCloud has no folder literally named "Trash" (it's "Deleted
  Messages"), so aerc's native `:move Trash` resolved to an invalid,
  empty-subfolder target instead.
- On `unified`: `Can only move file to a maildir folder` -- "Trash" on
  `unified` is a virtual notmuch query (`folder:"icloud/Deleted Messages"
  or folder:gmail/Trash`, from notmuchmap.conf), not a single real maildir
  path, so aerc's notmuch worker correctly refused rather than guessing.

**Fix**: added `[view:account=icloud]` (move to `'Deleted Messages'`) and
`[view:account=unified]` (the same `notmuch-unified-file` pipe as the
message list) to binds.conf, mirroring the message-list fixes exactly.
Unlike the message-list versions, these don't do a `:mark -T` thread-wide
capture first -- the viewer is inherently showing one specific message,
matching the pre-existing (unmodified) `A` binding in the generic `[view]`
section, which never did thread-wide marking either. Verified against
real mail for all three cases (icloud `d`, unified `a`, unified `d`) --
confirmed the file lands in the right real folder, the index catches up,
and (for icloud) the push-on-move hook fires correctly.

### Fixed: a second, deeper bug the viewer fix above exposed

Testing the viewer fix above thoroughly (rather than trusting the file
move alone) turned up a real regression: archiving from the viewer moved
the file correctly, but closing the viewer afterward showed the message
still sitting in the list -- silently stale, no visible error. The cause,
found by tracing the source: `:cf` (which `~/.local/bin/aerc-refresh-view`
relies on for its scratch-query refresh trick) requires aerc's
`MESSAGE_LIST` command context, and opening a message creates a genuinely
separate tab (`NewTab(viewer, msg.Envelope.Subject)` in app/msglist.go) --
so acting from *within* the viewer means `:cf` fails outright with
"Unknown command cf", logged but otherwise invisible.

The natural fix attempt -- `:change-tab unified` (`GLOBAL` context, so it
works from the viewer) before the scratch-query trick, then `:change-tab
-` to switch back -- turned out to be fundamentally broken, not just
fiddly, once traced all the way through: `:cf`'s own completion handler
unconditionally calls `acct.Select()`, which *also* pushes onto the tab
history stack (confirmed in `lib/ui/tab.go`: every tab switch, even to
the tab you're already on, pushes the one being left). Two `:cf` calls
means two extra self-referencing pushes on top of the one real entry for
the viewer -- and a history stack's pop-then-push-current is a net-zero-
depth operation by construction, so once the top of the stack is stuck on
self-references to the tab already active, no number of further
`:change-tab -` calls can ever dig past them. Confirmed by literally
tracing the push/pop sequence by hand and reproducing it live: after 1,
2, and 3 additional `:change-tab -` calls, focus stayed stuck on
`unified` every time, silently leaving the user on the wrong tab -- a
*worse* regression than the stale list it was meant to fix.

**The real fix**: `:change-tab "<exact name>"` does a direct name lookup
rather than touching the history stack at all, so it works regardless of
how polluted that stack has become. Since a viewer tab's name is exactly
the message's own Subject (no truncation at the name level, only in the
tab bar's rendering), `notmuch-unified-file` -- which already parses the
piped message -- now passes `--from-viewer` (from binds.conf's
`[view:account=unified]` bindings only) so it can extract the Subject and
pass `--restore-tab "<subject>"` through to `aerc-refresh-view`, which
switches to `unified`, does the scratch-query refresh, then switches back
by name instead of by history. A second, real bug surfaced while testing
this fix itself: firing the IPC calls back-to-back with no delay was a
confirmed, reproducible race (aerc reports each command as successful
before its effect has actually settled, so the next command in the
sequence could be silently ineffective) -- fixed with a small 0.1s pause
between each call, negligible since this all happens in the background.

aerc.conf's `flag-changed`/`tag-modified` hooks have no equivalent fix
available: hooks only expose `AERC_ACCOUNT`/`AERC_FOLDER`/etc., never a
message's Subject or any other stable per-tab identifier, so there's no
reliable name to restore by. Rather than guess and risk stranding the
user on the wrong tab, `aerc-refresh-view` with no `--restore-tab` given
(the hooks' usage) skips the tab round trip entirely and only attempts
the plain folder-level refresh -- which still works correctly when
triggered from the message list (the originally tested and confirmed
scope), and simply no-ops (logged, never disruptive) when triggered from
within the viewer. That specific gap -- a flag toggled from *within* the
viewer not visibly refreshing until the message is closed and reopened or
aerc is restarted -- is accepted as a known limitation, consistent with
the already-documented flags/read-status staleness below.

Verified end-to-end against real mail for both paths: archiving from the
viewer now correctly restores focus to the exact viewer tab (confirmed
via the tab bar's own selected-tab styling, not just assumed), and the
underlying list correctly shows the message gone immediately after
closing the viewer -- no staleness. Flagging from within the viewer
correctly updates the tag instantly (confirmed via notmuch directly) and
never stranded the user on the wrong tab, even though the list itself
doesn't refresh until later.

**Superseded by the local FSEvents patch below**: the viewer bindings no
longer pass `--from-viewer`, and `notmuch-unified-file` no longer switches
tabs or issues a scratch-query refresh. A final isolated integration test
ran the actual current helper from an open viewer against the current
local patched binary: it moved the message, the watcher reindexed the
underlying unified list while the viewer stayed open, and closing the
viewer showed the message gone with no tab restoration, blink, or stale
row.

### Mostly fixed: flags/read-status staleness for an already-cached message

After the fix above shipped, a related but separate issue turned up: an
already-visible message's own *flags* (read/unread, flagged, answered,
forwarded) sometimes don't visibly update after marking it read, flagging
it, etc. -- on `unified` specifically, and regardless of whether the
change came from aerc's own action (`:read`, `:flag`) or an external
process. Investigated thoroughly, including live testing against a real
running instance (tmux + its IPC socket, screen content captured
before/after each step, not just reasoning from source):

- The *first* naive fix attempt (`:cf -` twice, toggling to the
  previously-viewed folder and back) turned out to have a real gap: it
  silently degenerates into a no-op whenever `previous` happens to equal
  the currently-viewed folder (confirmed reproducible: a fresh session's
  very first action, since aerc's own `default = Inbox` auto-open counts
  as the "previous" folder too). Replaced with a more robust version
  (`~/.local/bin/aerc-refresh-view`) that always toggles through a
  guaranteed-different scratch query (`tag:__aerc_refresh_anchor__`, a
  tag that will never exist on any real message) before returning via
  `:cf -` -- this always forces two genuinely-different-named
  navigations no matter what the previous/current folder happened to be.
  The scratch query is hidden from the sidebar via `folders-exclude` in
  accounts.conf.

- That more robust version was, at the time, only confirmed to reliably
  fix *membership* changes (a message leaving the current query, e.g.
  archived out of Inbox -- notmuch-unified-file's actual use case) --
  live testing at the time seemed to show it did **not** reliably fix a
  message's own *flags* once that specific message had already been
  fetched into the current session's view of a folder, and
  `lib/msgstore.go`'s `DirectoryContents`/`DirectoryThreaded` handling
  (reusing an already-cached `MessageInfo` object for any known UID,
  verbatim) seemed to explain why -- membership is unaffected by this (a
  message no longer in the query's result set is simply never copied
  into the new map, cache or not), but this reasoning suggested a
  message's own flags should never be refreshed by this path once
  cached.

- Extensive attempts to force a genuine per-message refresh all
  *appeared* to fail against a real, already-populated session at the
  time: `:cf` to a different folder and back (worked for a *brand new*
  session that had never cached that message, confirmed by restarting
  aerc entirely -- but seemingly not for one that had already viewed it),
  an external `notmuch tag` change plus `notmuch new` (the exact
  combination that makes archive/trash work), and simply waiting 15-20
  seconds with zero interaction for the filesystem watcher to catch up on
  its own (it never appeared to). `:rmdir` (which can discard a
  *dynamic* ad-hoc query's cache) is explicitly unsupported for named
  query-map entries like "Inbox" (`worker/notmuch/worker.go`: `if
  inQueryMap { return types.ErrUnsupported }`), so it couldn't be used as
  a workaround either.

- **Corrected in a later session**, using the isolated sandbox test
  environment (see "Sandboxed testing environment" below) to eliminate
  the confounds that likely explain the "appeared to fail" results above
  (real mail, real time pressure, at least one confirmed instance of
  testing the wrong message row by mistake): a clean, controlled test --
  externally `notmuch tag +flagged`/`notmuch tag -flagged` an
  already-cached, already-viewed message, with zero aerc interaction in
  between -- showed the scratch-query refresh trick (`aerc-refresh-view`)
  *does* correctly update that message's own displayed flag, in both
  directions, every time. The `lib/msgstore.go` reasoning above was
  either incomplete or describes a narrower case than originally assumed;
  either way, the practical, empirically-confirmed result is what matters
  here, and it's better than previously documented.

**Current state after the local FSEvents patch**: the underlying data is
always correct and safe, and the patched watcher receives the Xapian
change for external tag/flag writes as well as moves and new mail. aerc's
native update path refetches the active query without the former 20-second
scratch-query timer; ordinary latency is the watcher batch/debounce delay,
not an unbounded or timer-sized stale window. The old helper remains only
for manual diagnosis on an unpatched binary.

### Historical root cause: aerc's live-refresh mechanism did not work on macOS

This investigation is retained because it identified the right subsystem, but its scratch-query mitigation is superseded by the local watcher patch documented immediately below.

A later investigation (prompted by the same "stale until you do
something" symptom showing up again, this time as a startup race -- see
the aerc-startup section under "Hooks" below) went looking for a more
robust fix than the best-effort mitigations above, and ended up finding
something considerably bigger than expected: **an already-running aerc
session never reflects external changes on its own, at all, ever**
-- not new mail, not moved mail, not tag changes -- regardless of account
backend (`notmuch://` or plain `maildir://`), no matter how long you
wait. This isn't a vague suspicion; it was nailed down precisely using a
fully isolated, disposable test environment specifically built for this
(separate `$HOME`/config/socket/Maildir/notmuch-DB, so real races could
be deliberately reproduced and mail actions tested with zero risk to real
mail or a real running session -- see "Sandboxed testing environment"
below):

- Reproduced the "could not get MessageInfo" error deterministically
  (index a message, then rename its file on disk without reindexing --
  exactly what a concurrent `mbsync` run does) and confirmed it does
  *not* self-heal even after 30 seconds with the index fully caught up.
- Went further and tested the simplest possible case -- a brand new,
  cleanly indexed message, no race at all -- added to an already-open
  session. It never appeared, for as long as tested (30s+), with zero
  corresponding activity in aerc's own trace log the entire time.
- Ruled out every plausible confound before concluding this is a real
  aerc gap rather than a test artifact: tried a genuinely non-symlinked
  path (ruling out `/tmp`'s `/private/tmp` symlink, a known source of
  macOS FSEvents quirks); tested the plain `maildir://` backend (used by
  the `icloud`/`gmail` accounts) independently of notmuch entirely, with
  the same result; tested delivery via `rename()` (matching mbsync's own
  delivery pattern) as well as a plain file create.
- Ruled out a system-level FSEvents problem specifically: installed
  `fswatch` (a well-known, independent tool, unrelated to aerc) and
  confirmed it detects the exact same file events instantly every time.
  So the underlying OS mechanism works fine -- this is specific to aerc's
  own integration of it.
- Traced the actual cause in aerc's own source: `lib/watchers/fsevents.go`
  (the darwin-specific watcher backend) only reacts to
  `ItemCreated`/`ItemRenamed`/`ItemRemoved` FSEvents flags, never plain
  content modification. Whatever write pattern notmuch's Xapian backend
  and/or mbsync's own maildir writes actually produce apparently doesn't
  reliably trigger those specific flags on this codepath, so aerc's
  watcher-driven update path (`handleNotmuchEvent` ->
  `updateChangedMessages`) essentially never fires in practice.
- Confirmed the one thing that *does* reliably work: an explicit `:cf`
  round trip through a scratch query (the same trick
  `~/.local/bin/aerc-refresh-view` already used for the archive/trash and
  flags-staleness cases above) -- and confirmed, in the same sandbox,
  that it preserves whatever message/scroll position was currently
  selected, so it's safe to run proactively/periodically rather than
  only in reaction to a specific known event.

**Former mitigation (removed)**: `notmuch-reindex` used to invoke `aerc-refresh-view` after every 20-second reindex. That bounded the stale view, but the scratch-query `:cf` round trip visibly blinked and could reset the selected row after an archive/trash action. The helper remains available only as a manual diagnostic fallback; no production hook or timer calls it now.

### Fixed: aerc's macOS FSEvents watcher (local patch)

The historical diagnosis above was right that aerc was not receiving usable filesystem notifications, but the exact cause was more specific than missing `ItemModified`: its Darwin watcher set `EventStream.Device` while passing an absolute path. FSEvents interprets paths relative to the device root in that mode and returned only coarse `MustScanSubDirs` events. The watcher also never requested `FileEvents`, so its `ItemCreated`/`ItemRenamed`/`ItemRemoved` checks could not receive per-file flags at all.

`~/.local/src/aerc` is a full clone of upstream `https://git.sr.ht/~rjarry/aerc`, on local branch `local/fsevents-live-refresh` from tag `0.22.0`. It has three focused local commits:

- `629a9a66 watchers: fix macOS FSEvents path monitoring` uses normal path-based watching, adds `fsevents.FileEvents`, and treats modified/created/renamed/removed/coalesced database events as a change notification.
- `1d9fe56f notmuch: replace flags on unsolicited updates` marks unsolicited database updates as `ReplaceFlags`, so a removed flag replaces stale cached state instead of only ever accumulating flags.
- `081f484d messages: add numbered list navigation` makes `{{.Number}}` a stable one-based current-list position instead of the page-relative rendered-row value in upstream `0.22.0`, and adds one-based `:select-line N` for the visible number column and `zg` prompt binding.

The notmuch worker then checks the updated Xapian state, refetches the active query, and lets aerc's normal selection logic choose the adjacent surviving message. No custom move command or synthetic `:cf` is involved.

Verified in a separate disposable Maildir/notmuch database with the watcher patch: externally moved a message, ran `notmuch new`, and issued no IPC refresh at all. After the normal FSEvents batching delay (roughly one second), the message disappeared in place without a blink and aerc selected the next remaining message. A newly indexed message also appeared automatically, and an eight-second idle check produced no refresh loop. The full `go test -tags=notmuch ./...` suite passes; `TestAddMessageUsesListPositionForNumber` covers the number template behavior used by the third commit.

`~/.local/bin/aerc` is a symlink to the built binary in that checkout and precedes Homebrew on `PATH`; Homebrew's stable `opt/aerc` path still supplies shared filters/templates/styles and Homebrew's `notmuch` supplies the linked library. `~/.local/bin/aerc-fsevents-build` rebuilds the checked-out source but deliberately never fetches, rebases, or changes Git history. The local changes are committed separately, so inspect them with `git log --oneline 0.22.0..HEAD` and `git diff 0.22.0..HEAD` in `~/.local/src/aerc`. After a Homebrew aerc upgrade, inspect the upstream tag and local commits there, rebase them as appropriate, then run `aerc-fsevents-build`. The upstream GitHub repository is read-only; if this is later contributed, aerc accepts patches through its SourceHut mailing-list workflow rather than GitHub pull requests.

With this patch active, `notmuch-unified-file` still performs the safety-critical account-aware file move and `notmuch-reindex` still performs frequent lock-guarded indexing, but both rely on aerc's repaired watcher to update the UI. The old `aerc-refresh-view` helper and hidden scratch query remain only for manual diagnosis or a temporary fallback to an unpatched binary.

### Sandboxed testing environment

Built at `/tmp/aerc-sandbox` (plus `~/.aerc-sandbox-test` for one specific
test needing a genuinely non-symlinked path) specifically so live aerc
behavior could be tested thoroughly -- reproducing real races, testing
new mail arrival, checking IPC behavior -- without any risk to real mail
or to a real running aerc session. A real incident earlier in this same
project (accidentally deleting the real session's live IPC socket file
while it was running, confirmed via `lsof` before it caused any lasting
harm) is exactly the class of mistake this exists to prevent going
forward.

How it works: a separate `$HOME` (so aerc's config, its
`~/Library/Application Support/aerc.sock` IPC socket, and its notmuch
database are all fully isolated by construction, no special-casing
needed), a small `env.sh` to source before running any command against
it, a disposable Maildir with a handful of synthetic test messages, and
(for testing scripts that reference their sibling scripts via
`$HOME/.local/bin/...`, like `notmuch-reindex` calling
`notmuch-new-locked`) symlinks back to the real, actual scripts in
`~/.local/bin` -- so the *real*, unmodified production scripts get tested
directly, never a separate copy that could silently drift from what
actually ships. `aerc -C <path>` (an explicit config-file override) lets
the real, tracked `aerc.conf` be tested directly too, merged with a
sandbox-local `[general]` block enabling `log-level = trace` for
deep visibility into what aerc itself is actually doing.

Not itself tracked in `~/.dotfiles` (pure scratch/`/tmp` state, and a
few files under `~/.aerc-sandbox-test`) -- kept around as reusable
infrastructure for future debugging rather than torn down after one use.

### Message threading

`threading-enabled=true` (global, in aerc.conf's `[ui]` section) groups
replies into threads everywhere, including `unified` (notmuch supports
threading natively; icloud/gmail's IMAP backend doesn't, so aerc builds
threads client-side there instead by References/In-Reply-To -- purely a
display grouping either way). Fold/unfold with `za`/`zo`/`zc`/`zM`/`zR`
(already bound, see "Keybindings" above).

Threading doesn't change what `a`/`d` (single message) vs `A`/`D` (whole
thread, via `:mark -T`) act on -- this was deliberately checked before
enabling it. Plain `a`/`d` always act on just the highlighted message,
even when it's the folded root of a multi-message thread (expand it
first with `zo` to act on an individual reply instead); `A`/`D` mark and
act on every message in the thread at once, folded or not. Confirmed this
continues to route correctly through `notmuch-unified-file` on `unified`
by re-running its existing edge-case suite (which already covered
multi-message batches spanning both accounts, matching exactly what `A`/
`D` produce) against the current version.

### Tab order and account column

accounts.conf lists `[unified]` first (aerc opens on whichever account is
listed first), since it's the tab actually used day-to-day.

On `unified` specifically (via aerc.conf's `[ui:account=unified]` context),
the message list also shows which real account (icloud/gmail) each
message belongs to, derived from its actual current file path (`.Filename`
in the column template, not `.Folder` -- for a notmuch virtual folder,
`.Folder` returns the *currently viewed query's name* like "Inbox", not
the message's own real location, which isn't useful here). icloud/gmail's
own tabs don't show this column since it would always just say the one
account they already are.

### Theming: more color, and a more visible selection highlight

Both stylesets (`everforest-dark`/`everforest-light`) got two kinds of
updates, using only real Everforest "medium contrast" palette hex values
(cross-checked against `~/.config/tmux/everforest-{dark,light}.conf`, the
other place this exact palette is already pinned down):

- The selected-row highlight (message list, folder list, completion
  popups, the MIME part switcher) was bumped from Everforest's `bg1`/
  `surface0` tier to `bg3`/`overlay1` -- the original was barely distinct
  from the plain background and hard to see at a glance.
- Answered/forwarded/deleted/marked messages, and folders containing
  unread/recent mail in the sidebar, now each get their own accent color
  (previously only flagged messages and search results had any color of
  their own). Layering order (aerc-stylesets(7)) means a flagged message
  still shows flagged's yellow even if it's also unread/answered/etc.
- The MIME part switcher's currently-selected part (in the message
  viewer, when a message has more than one part) previously had no
  `.selected` style override at all, making it indistinguishable from
  every other part -- it now gets the same highlight treatment as a
  selected message/folder.

### Correction: the "missing Message-ID" mail isn't actually missing one

Earlier investigation concluded that ~11% of mail (all traced to one
sending domain, relayed through Microsoft Exchange/Outlook) had a genuinely
empty `Message-ID:` header, based on aerc logging
`invalid Message-ID header: mail: missing '<' in msg-id` for these messages
and a naive `grep "^Message-ID:"` appearing to confirm it (an empty value
on that line). That was wrong: the header is actually just *folded* across
two lines --

```
Message-ID:
 <XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX@XXXXXXXXXXXXXX.namprd05.prod.outlook.com>
```

-- which is entirely valid per RFC 5322's header-folding rules (a single
leading space on the continuation line, nothing malformed), just missed by
a single-line grep. Python's own `email` module parses it correctly and
recovers the real ID without issue, confirmed directly against several
real affected messages.

aerc's own source (`lib/rfc822/message.go`) already has a fallback for
exactly this case: if its strict parser fails, it logs the error (that's
the log line seen during earlier debugging) but then falls back to
`h.Get("message-id")` trimmed of angle brackets -- which should work fine
here, since the underlying header-folding join happens before that point,
independent of the strict parser. Whether the original "message can't be
opened" symptom is still real, was fixed between versions, or was
misattributed to this in the first place hasn't been re-verified live since
the 0.22.0 upgrade -- worth confirming next time it comes up, but not
currently believed to be a real, unresolved problem. Either way, this
doesn't affect `notmuch-unified-file` above: it extracts Message-IDs via
Python's `email` module, which already handles the folding correctly.

## Viewing HTML email and following links

aerc requires an explicit filter for every mimetype it renders, configured in
`aerc.conf`'s `[filters]` section (without this, opening *any* email --
including plain text -- fails with "No filter configured for this
mimetype"):

```
text/plain=colorize
text/calendar=calendar
message/delivery-status=colorize
message/rfc822=colorize
text/html=! html
```

`colorize` and `html` both ship with aerc itself (Homebrew installs them to
`/opt/homebrew/opt/aerc/libexec/aerc/filters/`); `html` wraps `w3m` (already
installed) with network access deliberately disabled, so opening an HTML
email can't fire tracking-pixel/beacon requests just by being viewed.

Multipart emails show the `text/plain` part by default (aerc's own
`[viewer].alternatives` setting already defaults to preferring it). Cycle to
the `text/html` part with `Ctrl+j`/`Ctrl+k` to see it rendered interactively
in `w3m` instead (scrollable, follows links) -- the leading `!` in the
filter means `w3m` runs directly against the terminal rather than through
aerc's own pager.

**Clicking a link directly in that w3m view will fail** ("Can't load
http://...") -- this is the same network isolation working as intended, not
a bug, and it blocks link clicks along with everything else. To actually
follow a link, use `Ctrl+l` (or `Ctrl+y` to just copy it) in the message
viewer instead: both pop up an `fzf` picker listing every link in the
message, then open the selected one with the real system browser (or copy
it), entirely bypassing w3m's own network-isolated navigation.

## Composing in nvim

No configuration needed -- aerc's `editor` setting (used for composing)
defaults to `$VISUAL`, then `$EDITOR`, then `vi`, and both are already set to
`nvim` in `.zshrc`. It opens in an embedded terminal within aerc itself.

## Hooks: pushing changes immediately

### Keeping the notmuch index fresh during long syncs

The main `mailsync` script's pipeline is `mbsync -a` then `notmuch new` --
the reindex only happens *after* the entire `mbsync -a` call finishes.
That's fine normally (each run is quick), but during a long-running sync --
the historical backfill ran for several hours straight in one single
`mbsync -a` invocation -- it means the notmuch index can go stale for the
*entire duration*: files keep getting renamed (flag syncs, moves between
new/cur, archiving) faster than the index catches up.

Compounding this: the script originally ran under a blanket `set -e`,
meaning if `mbsync -a` hit *any* non-zero exit -- and over a long-lived IMAP
connection it does, from transient socket errors/timeouts alone, confirmed
in `~/Library/Logs/mailsync.err.log` during the backfill -- the script
aborted immediately and skipped `notmuch new` entirely for that cycle,
leaving whatever *did* download successfully unindexed until the next
cycle happened to fully succeed. Fixed: `mbsync -a`'s exit status is now
checked without aborting the script, so `notmuch new` always runs
afterward regardless of whether the sync fully succeeded.

This caused real, confirmed symptoms during the backfill: aerc errors like
`could not get MessageInfo: open .../new/....: no such file or directory`
for messages that had already moved by the time aerc tried to read them,
and an archive/trash attempt from `unified` that appeared to hang at
"Fetching messages..." -- confirmed via trace logging to actually be aerc's
own internal message-fetch (needed before piping to
`notmuch-unified-file`) failing on a file that had moved again in the few
seconds since it was indexed, not an infinite hang (it does resolve, just
confusingly, after a few seconds, with "Failed to fetch all messages").
The underlying archive/trash mechanism itself was confirmed still working
correctly throughout (real successful moves for both modes are visible in
`~/Library/Logs/notmuch-unified-file.log` from that session).

**Fix**: `~/.local/bin/notmuch-reindex` (just `notmuch new`, lock-guarded
the same way as `mailsync`) runs on its own launchd timer
(`com.juanpinto.notmuch-reindex`, every 20 seconds), completely independent
of `mbsync -a`'s own duration or lock. This shrinks the staleness window
from "however long the current mbsync -a run takes" (could be hours during
a large backfill) down to at most ~20 seconds, regardless of how long any
single sync takes. A residual, much smaller race is still structurally
possible in that window -- `notmuch-unified-file` already tolerates this
gracefully (see its own edge-case testing above); aerc's own built-in
message-fetch does not, but a multi-hour staleness window shrunk to seconds
makes that far less likely to actually surface.

**Extended later** to also nudge aerc itself, not just the index: a
separate, considerably bigger investigation (see "Root-caused: aerc's
live-refresh mechanism doesn't work on macOS at all" above) found that
reindexing alone was never enough -- an already-open aerc session was
confirmed to never notice *any* external change on its own, regardless of
how fresh the index was. This same script now also calls
`aerc-refresh-view` (no args) right after its own `notmuch new`, on the
same 20-second cadence, which is the actual mechanism that makes new
mail/moved mail/tag changes visible in an already-open `unified` session
within a bounded time, rather than the reindex alone (which only ever
kept the *data* fresh, never the UI).

### Instant push-on-move

`aerc.conf`'s `[hooks]` section (a real, official aerc feature, confirmed
against the man pages) fires `mail-deleted`/`mail-added` whenever aerc moves
a message -- e.g. every archive or trash action. Both are wired to
`~/.local/bin/mailsync-push`, which runs a *scoped* `mbsync` for just the
affected account (plus `notmuch new`), backgrounded so aerc's UI never
blocks on it. This means an archive/trash action gets pushed to the server
within moments, rather than waiting for the next scheduled `mailsync` run
(every 3 minutes) -- this is what fixes the "message briefly vanishes from
both Inbox and Trash" gap described further down under credentials/known
issues during the initial historical backfill.

Note this scoped push (and `notmuch-unified-file`'s own targeted sync) can
still fail harmlessly with `channel ... is locked` if the long-running
backfill's `mbsync -a` happens to be mid-sync on that same account at that
exact moment -- the local move already succeeded either way (that part
never depends on the network), the push just gets deferred to the next
successful sync rather than lost. Expect this to happen fairly often while
the historical backfill is still running, and rarely to never once it's
fully caught up (each account's real sync channels are only briefly locked
during a normal ~180-second-interval `mailsync` run).

The script scopes differently per account because iCloud's single wildcard
mbsync channel (named `icloud`) can be addressed as `icloud:<folder>`
directly, while Gmail's channels are split per-folder (`gmail-
inbox`, etc.) and aren't individually addressable this way -- so Gmail syncs
the whole account instead, still far faster than a full `mbsync -a`.

### Fixed: lost sent replies from the unified tab (missing copy-to)

Two real replies sent from `unified`, both to an email that had originally
landed in Gmail, vanished completely -- not in the local Maildir, not in
notmuch's index, not in iCloud's or Gmail's Sent folders after a full sync,
and not visible in Mail.app either. Confirmed by grepping the entire
`~/mail` tree for the original message's unique DKIM/ARC fingerprint and
for its Message-ID appearing anywhere as an `In-Reply-To`/`References`
value, and by checking `unified`'s own notmuch thread view for that
message: the thread showed only the original, zero children, and the
newest file in `icloud/Sent Messages` predated the reply by days.

**Root cause**: `unified`'s `outgoing` is hardcoded to `msmtp -a icloud -t`
(see the comment on that account in `accounts.conf`), so any reply sent
from this tab always goes out over iCloud's SMTP -- but `unified` had no
`copy-to` set at all, and per `aerc-accounts(5)`, the default when unset is
"copied to no folders." Since iCloud's SMTP (unlike Gmail's) doesn't
auto-save a server-side Sent copy on plain SMTP submission, nothing
durable was ever written anywhere: not locally (no copy-to to trigger it),
not on iCloud's server (SMTP submission alone doesn't create one there),
and obviously not on Gmail's Sent either since Gmail's SMTP was never
involved. The only surviving trace was the `\Answered`/"R" flag aerc wrote
back onto the original message after `:send` completed -- real evidence
the send itself succeeded, but not a copy of the reply itself.

**Fix**: `unified` now sets `copy-to = icloud/Sent Messages`. Since
`unified` is a notmuch-backed account with `enable-maildir` on (the
default), its folder paths resolve relative to notmuch's own mail root
(`database.mail_root`, confirmed via `notmuch config list` to be
`~/mail`), not to a single account's own IMAP root the way `icloud`/
`gmail`'s folder names do -- so `icloud/Sent Messages` (not bare `Sent
Messages`) is the real, already-synced folder path this needs. Unlike the
archive/trash case above, this has no per-message ambiguity to resolve
(there's no "which real account does this belong to" question for a
brand-new outgoing message, since `unified`'s outgoing is always iCloud),
so a plain static `copy-to` is sufficient here -- no custom script needed.

As a second, independent backstop -- in case this specific path guess is
ever wrong, or any other gap like this surfaces again -- `aerc.conf`'s
`[hooks]` section now also logs a `mail-sent` line
(`~/Library/Logs/aerc-mail-sent.log`) for literally every message aerc
sends, on any account: timestamp, account, from, to, cc, and subject.
aerc doesn't expose the Message-ID, file path, or body to this hook, so it
can't recover a lost message on its own -- but it's enough to
independently confirm a send actually happened and reconstruct who/what/
when to follow up with a recipient by hand, without relying on the
copy-to mechanism working correctly.

**Not yet independently verified against a live send** (this was fixed by
reasoning from `aerc-notmuch(5)`'s documented `enable-maildir` behavior and
notmuch's own configured mail root, not by tracing aerc's source the way
the archive/trash fix above was) -- send a real test message from
`unified` and confirm a new file lands in `icloud/Sent Messages/cur`
before fully trusting this.

## Gmail folder mapping (folders, not labels)

Gmail's IMAP exposes labels as folders, and a message can carry multiple
labels (show up in multiple "folders") at once. To get real folder semantics
instead of label soup, only a curated set of Gmail folders is synced, each
mapped to a plain local name (see `~/.config/isyncrc`):

```
INBOX                  -> Inbox
[Gmail]/All Mail        -> Archive
[Gmail]/Sent Mail       -> Sent
[Gmail]/Drafts          -> Drafts
[Gmail]/Trash           -> Trash
[Gmail]/Spam            -> Spam
```

`[Gmail]/Starred` and `[Gmail]/Important` are deliberately not synced --
they're duplicate label-views of messages already covered above.

iCloud doesn't have this problem (no label/folder duplication), so its
mbsync channel just syncs every folder as-is: `Inbox`, `Archive`,
`Sent Messages`, `Deleted Messages`, `Junk`, `Drafts`.

## Adding the university Exchange account later

Deliberately deferred for now. The backend is structured so this is additive,
not disruptive: a new `IMAPAccount`/`IMAPStore`/`MaildirStore`/`Channel`/
`Group` block in `~/.config/isyncrc`, a new account in
`~/.config/msmtp/config`, and a new section in
`~/.config/aerc/accounts.conf` -- none of it touches the iCloud/Gmail config.

The real difference: Microsoft disabled basic-auth IMAP/SMTP everywhere
(Exchange Online tenants since Oct 2022), so this account will need OAuth2,
not an app password. Worth checking first whether the university tenant's
Conditional Access policies even allow a personal OAuth app registration --
if not, a local gateway like davmail (which handles Exchange's modern auth
and presents plain local IMAP/SMTP) is the fallback option.
