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

## Remaining implementation layers

1. Persist exact accepted block bodies and posterior state identity in canonical publication;
   preserve explicit unavailability for old header-only seeds and databases.
2. Add versioned disk historical indexes and scalable retained-root metadata, with bounded
   lookup/cache memory independently of archive length. A larger rolling view is not an archive.
3. Integrate retention selection, pruning, shared-node reclamation, pinned readers and recovery;
   record policy transitions and oldest available history durably.
4. Add CLI `--retain-blocks N`, `--archive` and `-1` alias, explicit conflict handling and
   historical block/state queries. Archive preserves future accepted history after a pruned
   database switches policy; restoring older history requires explicit backfill/replay.

Each implementation layer includes its own failure tests and operator documentation. Archive
completion requires the full acceptance criteria in the issue, not just a larger metadata count.
