# Historical block and state retention

Work tracked by [#1731](https://github.com/jacogr/ragnarok/issues/1731).
This is local full-node storage policy. The pinned Gray Paper and protocol recent-history
state, hashes and execution rules are unchanged. Partial light state has no complete-state claim.

## First increment: explicit rolling snapshot policy

The linear `ChainView` retains a positive, caller-selected number of snapshots, including its
head. The default remains eight. Its initial seed counts as one snapshot until evicted; a
checkpoint seed does not imply availability of earlier blocks. An explicitly selected finalized
snapshot is retained independently, even outside the window. Slot gaps do not consume entries.
There is no fork choice: only exact direct children of the selected head are admitted.

The policy belongs to the immutable view. Copies/readers survive advances and policy changes;
shared publication requires matching policies as well as exact history, state owners and finality.
Shrinking selects the newest suffix and preserves explicit finality. Expanding keeps only the
available suffix, growing on future advances; it cannot recover previously evicted snapshots.
Zero and counts that cannot fit a host sequence are refused before allocation.

New durable history contexts use V2 with little-endian E8 capacity, count and finality ordinal.
Finality zero means absent, one through count identifies an in-window owner, and `2^64-1`
means one separately encoded older anchor. Entries retain the existing exact root/head encoding.
Counts are validated against capacity, host allocation bounds and remaining encoded bytes before
allocating count-sized storage. V1 contexts remain readable with their original eight-entry
capacity. Canonical authority checks compare using the stored version; the next normal durable
publication writes V2 atomically through the existing journal publication path. Opening or
compacting V1 alone does not rewrite it. There is no fallback from malformed V2 to V1.

This increment provides configurable **snapshot** retention through the internal API. It does
not add CLI settings or claim archive support. The paged root table still has its independent
64-root ceiling; configured repository/context limits can refuse a larger snapshot window.
Existing durable publication failures continue to leave the canonical owner unchanged. Applying
a changed policy to an existing disk owner needs a later explicit durable policy-publication
operation; changing an immutable memory view alone cannot bypass stored canonical authority.

## Completion checks

- Windows of one, three, the default, and more than eight; exact newest suffix and slot gaps.
- Immutable old readers; retained complete state/root; evicted and in-window finality.
- Shrink/expand without backfill; policy participates in publication authority.
- V2 round trips with nondefault policies, including more than 255 entries; malformed counts,
  capacities, ordinals, extents and truncations refuse without publishing partial owners.
- V1 reopen, exact-version authority, durable successor upgrade and managed maintenance.
- Existing disk, paged, managed and application consumers retain their default behavior.

Local verification on 2026-10-28: checked release/ARC on macOS ARM64 with the pinned Nimony
`358b9bce4dd855453f57a80a0c499b0b2e27d7ee` passed `make unit SUITE=` selections
`local_history_restoration`, `disk_history`, `disk_chain`, `paged_disk_chain`,
`managed_maintenance_plan`, `managed_disk_chain` and `application_chain`. The history suite
reopens 256 entries and an in-window finality ordinal of 256. Certified publication upgrades V1
with and without RPC; managed maintenance preserves V1 bytes and all selected roots. The
application suite's 1,000-cycle ARC check ends at its starting occupied-memory count.
`make format-check`, edited-document local links and `git diff --check` passed. Exact-head
Linux CI remains separate; these results do not establish archive completion or whole-block parity.

## Review stack

The implementation is divided into rolling-policy/format support, exact accepted bytes, historical
indexes/records, durable selection/reclamation, and startup/CLI/query integration. Each layer includes
its supporting tests and documentation. The operator contract is [historical retention](../docs/block-retention.md).
Earlier increment evidence below remains scoped to the tree and interfaces tested at that stage.

## Accepted block bytes

Both supported complete-state chain coordinators retain the original admitted complete block
only after private execution/composition succeeds. Exact sealed-header bytes bind the body to
the selected header/hash and posterior state owner. Body storage is private immutable data;
byte reads copy, and exact view authority compares body availability and cached complete-byte
identity as well as state/profile/history. These helpers perform structural validation; execution
authority continues to come from the original opaque producer, never a detached body/map pair.

Body-bearing single-head records use `RAGNAROK-DISK-HEAD-V2`, adding an E8 body extent before
the exact sealed header and complete block bytes. Header-only V1 records remain byte compatible,
including inside existing V1/V2 history contexts. This allows old seeds/entries to coexist with
new accepted blocks without claiming unavailable old bodies. Enclosing history preflights both
header and body sizes against its existing context ceiling before allocation/publication.
Restore checks all extents, exact block consumption, framing and header equality before exposing
the body together with its complete historical state. Rejected traffic, duplicate attempts,
transport framing and trailing bytes never become accepted-history records.

This body-bearing rolling context is an intermediate durable path. Disk archive indexing must
move old complete records out of the bounded resident view and cannot rely on repeatedly
serializing an ever-growing history context. Current context/repository budgets still apply.

Local checked release/ARC verification on 2026-10-28 passed `disk_application_head`,
`disk_history`, `disk_chain`, `pvm_current_consecutive_disk`, `pvm_current_disk_worker` and
`disk_publication_crash`, plus pinned formatting and whitespace checks. Exact original block
bytes survive current consecutive journal/managed reopen across roster rotation, with and
without RPC; paged worker publication and interrupted ordinary publication remain covered.
These tests use the same pinned Nimony/macOS ARM64 profile recorded above. Linux exact-head
CI and completion of archive retention remain separate.

## Historical index and complete records

Historical retention uses a fixed 160-byte selected cursor and 240-byte ordinal rows, with E8
acceptance ordinals independent of slot gaps and physical repository generations. Each row binds
the complete header hash, exact parent, slot, complete state root, body availability and cached
full-byte body digest. A local hash chain authenticates the retained row suffix against the
selected cursor. Policy shrink raises the first available ordinal; expansion/archive never lowers
it. The first retained row carries its predecessor digest without requiring the pruned payload.
This is local storage authentication, not consensus/finality proof.

The memory backend uses a private immutable compressed binary index over all 256 block-hash bits.
Branch split positions strictly increase, bounding lookup/update depth independently of archive
length. Cached ordinal ranges reclaim expired subtrees; old owners retain their prior complete
states. The protocol rolling view remains separate: enabling history never widens `blockAt` or
`parentOf` or changes report validation. User historical lookup applies its own retained window
plus explicit finality. A memory archive necessarily grows with retained data, but neither a
rolling-view copy nor a lookup copies/scans an archive-sized list.

The disk index stores separate immutable records, ordinal rows and full-hash aliases under a
full-node/chain-bound namespace. Staging synchronizes complete record bytes, then ordinal row,
then hash alias before the successor cursor is eligible for canonical publication. Staging alone
never selects history; orphan future ordinals and stale aliases are unavailable to the previous
cursor. Strict selected-suffix admission scans fixed-size rows with constant working memory;
individual hash/ordinal lookup reads only fixed metadata plus the requested complete record.
Missing/corrupt retained metadata is an explicit failure, not genesis or another state.

Complete records reuse the existing strict full-checkpoint encoding plus the exact single-head
context, bound to the corresponding row. Decode recomputes the complete root and checks exact
body identity before returning any state. There is no archive-wide paged-root table: the existing
64-root ceiling remains a per-artifact bound for the small live validation/finality graph, while
historical complete records have independent identities. Live shared trie nodes retain their
existing root/pin/compaction rules. Initial historical records do not deduplicate state across
blocks, so archive disk usage grows by a complete checkpoint plus block/index metadata per entry.

A checked fixed workload measured before selecting this record layout encoded 65 successive
structural fixture states into 140,140 checkpoint bytes (largest 2,156 bytes), using the same pinned
release/ARC profile. This is sizing evidence for a small fixture, not a production storage-cost
claim: a multi-megabyte complete state repeated per block will consume substantial disk. Reuse
the proven complete-map encoding initially; future deduplication/layout work requires its own
measurements and retained-reader/recovery evidence.

Pruning runs only after confirmed canonical cursor publication. It removes obsolete aliases,
records and rows and synchronizes the directory; an interrupted cleanup can repeat its exact
ordinal inventory. Cleanup failure cannot roll back the selected cursor. A completed historical
read owns immutable state/body data independently of source files and survives later pruning.
Passive checked cursor metadata alone does not pin files for future reads; callers keep the
namespace stable during each synchronous operation, under the database's exclusive writer lease.
These synchronous file APIs belong on startup or the excluded storage worker, never network
callbacks. Canonical publication, startup policy application and CLI wiring follow in the next layer.

Local checked release/ARC verification passed `historical_index`, `historical_records`,
`local_history_restoration`, `application_chain` and `disk_chain`. The historical index's
1,000-cycle release witness returned to its starting occupied-memory count (88,960 bytes),
as did the existing application lifecycle. Cursor/policy privacy fixtures reject with their
exact private member diagnostics and successful frontend controls. Registration inventory,
pinned formatting and whitespace checks remain part of this layer's publication evidence.

## Durable selection, policy changes and bounded live roots

Indexed disk histories use a versioned wrapper around the fixed cursor and the small live restart
context. Both real opaque update coordinators stage the complete record and both indexes before
ordinary canonical publication. Only a confirmed receipt installs the cached selection and permits
pruning; staging, rejected/stale attempts and uncertain core writes do not grant historical availability.
The existing exclusive native worker owns this IO. It carries one immutable append source, never an
archive-length list. A failed cleanup remains an explicit diagnostic without revoking a confirmed block.

The configured disk live view keeps at most `min(N, 8)` complete states (eight in archive mode),
plus explicit finality when outside that suffix. The historical index carries the remaining requested
states. Eight is a local header-input bound, not a protocol requirement for eight complete states:
a separate immutable cache retains at most eight linked headers without state/body owners. V3 restart
contexts persist only the older headers absent from the complete-state suffix. Strict V1/V2 authority
and restoration remain supported; the next publication writes V3. GP recent-history state is unchanged.

Startup policy application stages the available seed records, then publishes the exact new cursor,
window and finality roots as a context-only generation. The canonical owner changes only after
confirmed IO. Reapplying the same policy consumes no generation. Shrink raises the first available
ordinal; archive/expansion preserves that floor. Old inline seeds can have complete states without
complete bodies, and never gain fabricated bytes. The paged predecessor/pinned-reader contract also
applies to these policy publications: busy retirement cannot silently discard a live reader.

Physical cleanup has a separate checksummed, chain-bound `CLEANUP` watermark. Deletions and the
directory are synced before acknowledging progress. Interrupted cleanup resumes from the previous
acknowledgement and skips already absent files. This watermark never selects availability; the core
cursor alone does. Completed historical reads own their body and complete state independently of
pruning/compaction, while passive metadata capabilities require the caller to keep files stable during IO.

Journal-to-managed migration streams the selected rows and complete records, one at a time, into an
exclusively created sibling namespace before publishing the destination core. Existing catalogs are
refused. The destination acknowledges its absent excluded prefix without scanning arbitrary missing
ordinals. Failed staging leaves unselected forensic files and never mutates the source selection.
Managed compaction touches only the bounded live trie/finality roots; historical records survive it.
The initial record layout has a 16 MiB complete-record ceiling independent of archive length and
retains full checkpoints per entry, so disk growth can be substantial. A larger state may be refused
explicitly; no incomplete checkpoint or silent historical gap is accepted.

Local checked release/ARC verification for durable selection passed `disk_retention`,
`historical_records`, `disk_history`, `local_history_restoration`, `application_chain`,
`application_local_ancestors`, `application_ancestor_inputs`, `disk_chain`,
`managed_maintenance_plan` and `pvm_current_disk_worker`. The dedicated storage witness migrates
261 complete entries, compacts, reopens and reads the old exact body/root; it also checks all three
layouts, retained readers, finality, no-backfill transitions and a child process exiting between
staging and selection. Cleanup interruption is exercised partway through the obsolete prefix,
then retried through a durable no-work acknowledgement. The current worker exercises indexed
journal/paged publication, replay and joined shutdown. These remain scoped macOS ARM64 results;
full CI and final CLI integration are distinct acceptance evidence.

## Startup controls and historical queries

Full Services applies an explicit validated policy before RPC and worker startup, preserving the
exact complete-state policy and current owner. Memory selects an immutable historical index and a
small live full-state window. Disk atomically configures the fixed persisted cursor; absence of an
override preserves an existing indexed policy. Legacy/default inline databases keep their eight-entry
behavior until explicitly configured. Light mode rejects full-history selectors.

The `history` command opens only an existing explicitly configured full disk database. It selects an
exact header hash or local positive ordinal, returns exact body/header hex and complete state/root
identity, and optionally exports the existing complete checkpoint format. Old missing bodies are
explicitly null. It never starts listeners, imports trust, migrates, changes retention or creates a
missing database. The Services library shares these exact reads; leased graph access returns Busy
before touching canonical aliases. Disk IO remains startup/offline/excluded-owner work rather than
synchronous network callback work. Archived disk lookup is intentionally separate from the current
bounded public RPC surface.

Final integration verification on the pinned checked release/ARC macOS ARM64 profile passed
`retention_options` and `retention_services`, plus existing `app_options`, `app_cli`,
`disk_storage_options`, `light_runtime_options`, `managed_services_startup`,
`managed_services_migration`, `paged_services_startup` and `disk_services_boundaries`.
The genuine signed execution fixture produces identical roots and exact complete block bytes
under default/archive/one-block/300-block policies across all full backends. Offline output is
checked byte-for-byte using independent hex formatting, and exported checkpoints are decoded
against the exact selected header/root. Stored policies survive restart without flags; missing
bodies, pruned ordinals, graph-lease refusal and missing-database refusal remain explicit.

The production `make` build and executable history-help/conflicting-selector/missing-data checks
passed. The Options privacy fixture requires the exact private-field diagnostic with a successful
frontend control; Services copy rejection requires the actual ARC lowering diagnostic. Inventory,
pinned formatting and whitespace checks passed. The CLI lifecycle's 1,000-cycle ARC witness
returned to its starting occupied-memory count. Exact-head Linux smoke remains independently
reported for each published stack layer; these scoped local checks do not claim the full CI matrix.
