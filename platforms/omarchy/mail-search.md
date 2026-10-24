# Search in aerc

How search and filter actually work across the three accounts/tabs configured in [mail.md](mail.md) (`icloud`, `gmail`, `unified`), since the behavior genuinely differs between them. Written on the Mac (`~/mail/SEARCH.md`, recovered from session logs); nothing here is platform-specific.

## `:search` vs `:filter` -- two different actions

Both take the exact same syntax; they just do different things with the
result:

- **`:search`** (bound to `/`) -- jumps through matches in place. Doesn't
  hide anything. Use `n`/`N` to go to the next/previous match.
- **`:filter`** (bound to `\`) -- actually narrows the visible message list
  down to only the matches, until cleared with `Esc`.

Everything below applies equally to both.

## Backend differences: this is the part that actually matters

Search behavior depends entirely on which tab you're in:

- **`icloud` / `gmail`** (Maildir-backed): aerc does its own
  built-in matching directly against the message files -- case-insensitive
  substring search on the subject line by default, or body/full text with a
  flag (see below). There is no index; it's a direct scan of whatever's in
  the current folder. Not notmuch, not cross-account.
- **`unified`** (notmuch-backed): real, indexed, full-text search using
  notmuch's own query language (`notmuch-search-terms(7)`). This is the only
  tab where search is genuinely fast and cross-account.

## Folder/query scope

Search and filter always apply **on top of whatever you're currently
viewing** -- they narrow further, they don't broaden.

- On `icloud`/`gmail`, that means literally just the current
  Maildir folder (e.g. searching while in Inbox only searches Inbox, not
  Archive too).
- On `unified`, your search terms get ANDed onto the active notmuch query
  for whatever virtual folder you're in. Several virtual folders are
  defined in `~/.config/aerc/notmuchmap.conf`:

  ```
  Inbox=folder:icloud/Inbox or folder:gmail/Inbox
  Flagged=tag:flagged
  Sent=folder:"icloud/Sent Messages" or folder:gmail/Sent
  Drafts=folder:icloud/Drafts or folder:gmail/Drafts
  Archive=folder:icloud/Archive or folder:gmail/Archive
  Trash=folder:"icloud/Deleted Messages" or folder:gmail/Trash
  Spam=folder:icloud/Junk or folder:gmail/Spam
  All=path:**
  ```

  Each is scoped to exactly what its query says -- e.g. searching while
  sitting in `Inbox` only searches both accounts' Inboxes, not the rest of
  your mail. `Flagged` is the one entry that intentionally ignores folder
  location entirely (a message can be flagged in any folder), since
  "flagged" is a cross-folder tag, not a location.

**To search your entire indexed mail history, across both accounts**, jump
to the `All` virtual folder (or, equivalently, broaden manually with):

```
:cf path:**
```

(`path:**` is a notmuch query meaning "everything under the mail root").
Then search/filter from there. This is the actual "search everything I've
ever received" move -- searching from the default `Inbox` view will not
reach anything outside of Inbox.

More virtual folders can be added to `notmuchmap.conf` any time as
`<name>=<notmuch query>` lines if there's a broader view worth having as a
permanent tab, e.g.:

```
All=path:**
Archive=folder:icloud/Archive or folder:gmail/Archive
```

## Search/filter options (same for both `:search` and `:filter`)

| Flag                  | Meaning                                                                                                         |
| --------------------- | --------------------------------------------------------------------------------------------------------------- |
| (plain words)         | Case-insensitive subject search (default)                                                                       |
| `-b`                  | Search message bodies instead of just the subject                                                               |
| `-a`                  | Search entire message text (headers + body)                                                                     |
| `-f <addr>`           | From a specific address                                                                                         |
| `-t <addr>`           | To a specific address                                                                                           |
| `-c <addr>`           | Cc'ed to a specific address                                                                                     |
| `-r`                  | Read messages only                                                                                              |
| `-u`                  | Unread messages only                                                                                            |
| `-x <flag>`           | Only messages *with* a flag (`seen`, `answered`, `forwarded`, `flagged`, `draft`)                               |
| `-X <flag>`           | Only messages *without* a flag                                                                                  |
| `-H <header>:<value>` | Match an arbitrary header                                                                                       |
| `-d <since[..until]>` | Date range -- understands `today`, `yesterday`, `last week`, `Mon..Fri`, `2w3d`, `2024-01-01..2024-06-01`, etc. |
| `-v`                  | Invert -- exclude matches instead of including them                                                             |
| `-e`                  | Use a provider's native search extension (e.g. Gmail's `X-GM-EXT-1`) -- **not applicable here**, see below      |

### Why `-e` (Gmail's native search) doesn't apply to this setup

`-e` only works when aerc is talking *directly* to an IMAP server (see
`aerc-imap(5)`). Our `gmail` account reads from a local
Maildir instead -- `mbsync` owns the actual IMAP connection, aerc never
talks to Gmail's server directly -- so this extension has nothing to attach
to. The `unified`/notmuch tab is the real equivalent for us, and arguably
better anyway: it searches both accounts at once, not just Gmail, and does
so via a real local index rather than a live server round-trip.

## On `unified`, you can skip the flags entirely

Since `unified` is notmuch-backed, raw notmuch query syntax works directly,
without needing any of the flags above:

```
:search tag:unread
:search from:alice and date:2024-01-01..2024-06-01
:filter attachment:pdf
:search subject:invoice or subject:receipt
```

See `notmuch-search-terms(7)` for the full query language (boolean
`and`/`or`/`not`, `tag:`, `from:`, `to:`, `subject:`, `attachment:`,
`date:`, `folder:`, `path:`, and more).

## Practical examples

```
/ -d 1w                       search: messages from the last week, current folder
\ -u -f alice                 filter: unread messages from alice, current folder
:cf path:** then / project    search literally everything, cross-account, for "project"
\ -a invoice                  filter: "invoice" anywhere in the message (not just subject)
:search -d today..tomorrow    messages from today only
```
