# Bounded reads from a held managed journal

This local storage API bounds encoded-log buffering independently of proof-image reconstruction.
It prepares the [light journal owner](storage-light-journal-cache.md) for strict frame-by-frame
reopen without changing an existing format, root expectation or integration boundary. The
[matched churn evidence](storage-light-journal-churn.md) distinguishes input buffering from
larger successor-image costs; this layer makes no replay speed or RSS reduction claim.

`attachManagedJournal(journal, directory, epoch, limit)` retains one regular no-follow append
inode and its existing directory lease without allocating or reading the entire log. It bounds
the held extent by the explicit byte limit and native addressability, checks selected-name/held
inode and size before and after synchronization, then adopts the descriptor only after both
file and directory barriers succeed. The caller still authenticates the journal format and
selected root. Attachment alone grants no proof or durable-head authority. Failed attachment
adopts no journal lease and permits explicit close/reopen retry. The existing whole-buffer
`openManagedJournal` contract is unchanged.

`readManagedJournalRange(journal, directory, epoch, offset, output)` synchronously fills at most
the caller-owned writable window from the exact held inode. Offset bounds precede narrowing,
seeking or selected-file IO. The successful scalar count is the lesser of window length and
remaining held extent. Bytes beyond that count remain unchanged. Empty windows and exact EOF
are supported. Genuine short reads advance within the owned span; EINTR retries the same span.
Reaching the known end requires actual EOF as well as metadata agreement. Name/inode/extent
are checked before and after every window. No full-log buffer or predecessor chain is retained.

An invalid offset or unrelated directory refuses without poisoning the live journal. Read,
probe-close, selected-name/inode or extent uncertainty poisons fresh size, append and range
observations until explicit close and fresh attachment. A failed read exposes no successful
count; its caller buffer is unspecified and must be discarded. No IO failure is silently
converted into a short successful frame. The directory remains busy until its journal owner
closes. Later append still uses O_APPEND even when a window seek left the descriptor in the
middle of the file. Existing explicit retirement and move-only ownership hooks apply.

## Scoped evidence

`make unit SUITE=storage_held_journal_ranges` checks exact/over-limit attachment without payload
reads, both real attachment-barrier refusals and fresh retry, bounded random windows across the
4096-byte native read boundary, empty windows, exact EOF and unchanged caller suffixes. It
forces seven-byte reads and a real EINTR, proves caller mutation cannot alias the inode, and
checks append placement after a middle-window read. Maximum offsets refuse before IO.

Real post-stat shrink/growth, equal-byte inode replacement, read refusal and selected-probe
close refusal each require a typed error and poisoned fresh observations. One thousand scoped
window reads return occupied ARC bytes to baseline (12,560 before/after in the local checked
release run). The existing managed publication suite also passes with its original whole-buffer
API. Formatting, registration inventory and diff checks accompany the implementation. Local
evidence is macOS arm64 with the pinned compiler/providers; exact-head Linux CI is separate.
