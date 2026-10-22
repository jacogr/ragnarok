# Native storage process-crash qualification

Fresh baseline: merged `7655b78f`, after storage stack #664 and the coordinated PVM/state stacks.
Current Gray Paper is unreleased `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, based on VERSION
0.8.0; the published 0.8.0 vectors remain a separately identified historical corpus. This storage
qualification changes no protocol domains, file formats, state/proof APIs or checkpoint trust.

## Witness and scope

A test-only observer forwards real SDK operations. A child arms observation after setup, writes a
fixed-size receipt only after the selected successful syscall, then stops with SIGSTOP. The parent
checks its exact owned child, exact operation/ordinal and stopped status, sends SIGKILL and requires
its signal reap. Normal exit is a distinct baseline receipt. Missing/unreached hooks, malformed
receipts, unrelated stops, unexpected exits and monotonic deadline expiry cannot pass a crash case.
Child storage owners never execute normal close or ARC retirement after the witnessed boundary.

The supervisor owns one child and pipe, rejects replacement while active, uses nonblocking receipt
reads and bounded monotonic waits, and has explicit failure-path kill/reap. No production hook,
compiler/runtime patch or child process is added to the application. The existing native runner
owns compilation, profiles, logs and suite discovery.

Process death leaves the host kernel and page cache alive. These tests qualify restart after
process interruption; they do not certify filesystem/device durability or hardware power loss.
Strict recovery still needs independently selected exact generation/root authority. Context stays
opaque; an existing migration destination is never overwritten. M1/state-serialization scope stays
unchanged. State #6 owns typed proof readers and selected-root integration; no overlap is planned.

## Initial supervisor verification

`make unit SUITE=storage_crash_supervisor` verifies real one-byte writes, two distinct successful
stop ordinals, explicit three-write normal completion, and refusal without an owned child.

## Supervisor negative controls

`storage_crash_controls` repeats normal-but-unarmed completion, unmarked SIGSTOP, raw early exit,
a20ms monotonic timeout and explicit cancellation. Invalid operation/ordinal/deadline and nested
fork/start requests cannot replace an owned child. Every completed case refuses a second finish;
normal completion has count0 and cannot be confused with a successful crash witness.

## Complete legacy append before return

`storage_legacy_append_crash` counts the actual append write in a normally completing control,
then stops and kills the writer after the real complete write but before its caller receives
success. The parent checks the exact independently encoded frame, strict generation2 reopen,
complete authored leaves and its original retained generation1 view. No failed child receipt is
counted as a confirmed publication; the surviving parent must independently reopen visible bytes.

## Managed publication append crashes

`storage_managed_append_crash` independently counts 1 successful observed boundaries and kills after each.
After a successful journal append but before its caller receives success, strict restart selects
the complete successor. Exact encoded bytes, authored leaves and the retained old reader are checked;
managed snapshot/epoch selection remains unchanged and no implicit fallback layout is introduced.

## Legacy torn append process death

`storage_legacy_partial_crash` kills after actual eight-byte writes at the beginning, middle, penultimate
and final frame extent. Exact visible prefix bytes are independently checked. Incomplete tails
fail strict startup; wrong generation/root repair tokens preserve every byte and expose no owner.
The exact independent prefix token permits truncation and a complete resumed successor. A final
complete frame refuses the old repair token and cannot be rolled back. Held readers remain valid.

## Managed torn append process death

`storage_managed_partial_crash` kills after actual eight-byte writes at the beginning, middle, penultimate
and final frame extent. Exact visible prefix bytes are independently checked. Incomplete tails
fail strict startup; wrong generation/root repair tokens preserve every byte and expose no owner.
The exact independent prefix token permits truncation and a complete resumed successor. A final
complete frame refuses the old repair token and cannot be rolled back. Held readers remain valid.

## Legacy publication barrier crashes

`storage_legacy_barrier_crash` independently counts 3 successful observed boundaries and kills after each.
Pre-append barriers retain the exact prior frame; the final completed sync leaves the exact complete
successor visible. Strict restart admits only the independently checked generation/root and complete
authored leaves, while retained parent readers remain unchanged.

## Managed publication barrier crashes

`storage_managed_barrier_crash` independently counts 3 successful observed boundaries and kills after each.
Pre-append barriers retain the exact prior frame; the final completed sync leaves the exact complete
successor visible. Strict restart admits only the independently checked generation/root and complete
authored leaves, while retained parent readers remain unchanged.

## Legacy contextual publication crashes

`storage_legacy_context_crash` exercises complete writes, every publication barrier and genuine torn/final
extents with opaque FullStateV1 context. Old and new context bytes must stay bound to the exact
selected generation/root. Independent repair retains the old prefix context before a complete
resumed successor; a complete successor rejects rollback. Detached parent context remains valid.
No storage interpretation of application context or checkpoint-import authority is introduced.

## Managed contextual publication crashes

`storage_managed_context_crash` exercises complete writes, every publication barrier and genuine torn/final
extents with opaque FullStateV1 context. Old and new context bytes must stay bound to the exact
selected generation/root. Independent repair retains the old prefix context before a complete
resumed successor; a complete successor rejects rollback. Detached parent context remains valid.
No storage interpretation of application context or checkpoint-import authority is introduced.

## Legacy multi-publication crash prefixes

`storage_legacy_sequence_crash` kills a writer at every write and durability barrier across four successive
publications. Exact concatenated frame bytes, selected generation/root and every earlier authored
historical map are checked after strict restart. Earlier complete frames never disappear, and
parent-held readers stay valid. Visible-but-unreturned bytes are admitted only by independent
strict restart; no killed child is retroactively counted as a confirmed application adoption.

## Managed multi-publication crash prefixes

`storage_managed_sequence_crash` kills a writer at every write and durability barrier across four successive
publications. Exact concatenated frame bytes, selected generation/root and every earlier authored
historical map are checked after strict restart. Earlier complete frames never disappear, and
parent-held readers stay valid. Visible-but-unreturned bytes are admitted only by independent
strict restart; no killed child is retroactively counted as a confirmed application adoption.

## Managed replacement staged-write crashes

`storage_compaction_write_crash` kills after each actual snapshot, empty journal and CURRENT.next
write. CURRENT remains byte-identical and strict restart selects the original complete generation2
epoch. Old selected files and every remaining forensic staging byte stay unchanged by restart.
Only explicit bounded staging cleanup permits replacement retry; selected/future epochs cannot be
retired through the earlier-epoch API. Held generation1 maps outlive final native retirement.

## Managed barriers process crashes

`storage_compaction_barrier_crash` verifies every real replacement barrier, one strict selected epoch and retained readers.
Strict restart validates the selected manifest and complete authored map, preserves every remaining
forensic byte, and never chooses staging by filename. Explicit bounded cleanup/replacement retry
finishes independently of the killed caller; selected/future epoch retirement remains forbidden.

## Managed manifest process crashes

`storage_manifest_crash` verifies actual manifest rename, strict new epoch and explicit old-epoch cleanup.
Strict restart validates the selected manifest and complete authored map, preserves every remaining
forensic byte, and never chooses staging by filename. Explicit bounded cleanup/replacement retry
finishes independently of the killed caller; selected/future epoch retirement remains forbidden.

## Managed retirement process crashes

`storage_retirement_crash` verifies both actual retired-file unlinks, confirmed new epoch and idempotent cleanup.
Strict restart validates the selected manifest and complete authored map, preserves every remaining
forensic byte, and never chooses staging by filename. Explicit bounded cleanup/replacement retry
finishes independently of the killed caller; selected/future epoch retirement remains forbidden.

## Every partial staged replacement write

`storage_staged_partial_crash` independently encodes expected snapshot, journal header and manifest,
then kills after every actual eight-byte write across all three files. Each existing file must be
the exact expected byte prefix; later names must remain absent until their first real progress.
CURRENT remains old, strict startup preserves staging, and explicit bounded cleanup permits a
complete retry. The bounded completed control checks the full independently encoded selected files.

## Historical-root/context replacement crashes

`storage_history_compaction_crash` retains both independently selected complete historical/current
roots and opaque FullStateV1 head context through every write, sync, rename and retirement boundary.
Strict restart and explicit cleanup/retry preserve both complete authored maps and exact context.
Detached old context/readers remain valid. The current-only control instead excludes the obsolete
physical root after replacement; retained parent readers do not imply physical retention authority.

## storage_legacy_bootstrap_crash

Real creator process death verifies complete visible identity, absent-only retry and independent strict ownership.
Strict restart never selects by a staging filename or recreates an existing target. Every known
forensic name/byte remains unchanged by refused recreation and strict admission. A legacy empty
identity grants only generation0 repository metadata, not an authenticated complete JAM state;
subsequent explicit publication is independently checked against the authored complete mapping.

## storage_managed_bootstrap_write_crash

Real creator process death verifies three real staged writes, no implicit CURRENT selection and exact forensic files.
Strict restart never selects by a staging filename or recreates an existing target. Every known
forensic name/byte remains unchanged by refused recreation and strict admission. A legacy empty
identity grants only generation0 repository metadata, not an authenticated complete JAM state;
subsequent explicit publication is independently checked against the authored complete mapping.

## storage_managed_bootstrap_barrier_crash

Real creator process death verifies every actual creation barrier, strict selected admission and preserved forensic files.
Strict restart never selects by a staging filename or recreates an existing target. Every known
forensic name/byte remains unchanged by refused recreation and strict admission. A legacy empty
identity grants only generation0 repository metadata, not an authenticated complete JAM state;
subsequent explicit publication is independently checked against the authored complete mapping.

## storage_managed_bootstrap_manifest_crash

Real creator process death verifies actual CURRENT replacement, complete seeded map and absent-only retry.
Strict restart never selects by a staging filename or recreates an existing target. Every known
forensic name/byte remains unchanged by refused recreation and strict admission. A legacy empty
identity grants only generation0 repository metadata, not an authenticated complete JAM state;
subsequent explicit publication is independently checked against the authored complete mapping.

## storage_legacy_repair_crash

The child receives an independently exact generation/root token for a genuine torn append.
Actual truncation/barrier process death leaves either the exact torn tail or the confirmed complete
prefix visible. Strict startup admits only a complete prefix; a mismatched token preserves every
byte and grants no owner. The same independent exact token can finish confirmation and publication
can resume. No killed recovery process returns a live owner or grants checkpoint-import trust.

## storage_managed_repair_crash

The child receives an independently exact generation/root token for a genuine torn append.
Actual truncation/barrier process death leaves either the exact torn tail or the confirmed complete
prefix visible. Strict startup admits only a complete prefix; a mismatched token preserves every
byte and grants no owner. The same independent exact token can finish confirmation and publication
can resume. No killed recovery process returns a live owner or grants checkpoint-import trust.

## storage_repair_barrier_crash

The child receives an independently exact generation/root token for a genuine torn append.
Actual truncation/barrier process death leaves either the exact torn tail or the confirmed complete
prefix visible. Strict startup admits only a complete prefix; a mismatched token preserves every
byte and grants no owner. The same independent exact token can finish confirmation and publication
can resume. No killed recovery process returns a live owner or grants checkpoint-import trust.

## Source-preserving migration process crashes

`storage_migration_crash` kills at every destination write, barrier and CURRENT rename. The parent
retains its original legacy lease across fork; child death releases only the child's inherited
reference, not the parent's lease. Source bytes, both complete authored roots and opaque context
remain exact and readable. Existing targets reject recreation; strict admission follows only a
complete visible CURRENT and preserves all forensic names/bytes. No import trust is inferred.

## storage_staging_cleanup_crash

Every actual bounded unlink/directory-sync boundary is killed independently. The exact removed
prefix and remaining forensic bytes are checked before and after strict restart. CURRENT, selected
files, complete authored maps and farther epoch files stay byte-identical. Explicit idempotent
cleanup finishes only its requested staging/retired names; selected/future retirement is refused.

## storage_retired_cleanup_crash

Every actual bounded unlink/directory-sync boundary is killed independently. The exact removed
prefix and remaining forensic bytes are checked before and after strict restart. CURRENT, selected
files, complete authored maps and farther epoch files stay byte-identical. Explicit idempotent
cleanup finishes only its requested staging/retired names; selected/future retirement is refused.

## Real cross-process lease exclusion and release

`storage_process_lease_crash` parks a child immediately after actual nonblocking flock acquisition,
while the parent owns no inherited file descriptor. A fresh competing owner must return Busy while
the exact witnessed child is stopped. Only explicit finish verifies SIGKILL/reap and permits strict
reopen; a stopped receipt is distinct from a killed receipt. Duplicate wait/invalid deadline/nested
fork controls preserve ownership. Both layouts also have normally completing lease controls, exact
journal bytes, complete authored maps and retained parent readers after native retirement.

## Qualification handoff

The [operator guide](../docs/storage-process-crashes.md) distinguishes process-death evidence from
hardware power-loss certification. Final qualification freezes all sources and reruns every new
native crash matrix, representative ordinary IO controls, authenticated TLS/startup consumers,
checked production build/selftests and Perf Storage source/raw/Markdown verification. Per-layer
local logs and final exact-head/parent evidence remain under ignored build/. No new M1 or complete
protocol state-serialization claim is made. Future light/proof integration stays coordinated with
state #6; there are no production storage format or state-interface changes in this tranche.
