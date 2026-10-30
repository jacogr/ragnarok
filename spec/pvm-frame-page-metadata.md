# Execution-frame page metadata

## Scope and ownership

This layer follows owned page-image transfer under the unchanged Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and pinned memory-order decisions. It changes invocation
memory representation, not gas, attempts, source PCs, guest permissions, dependency pins or native
execution ABIs.

A frame retains compact `PageDescription` entries and its immutable source `Memory`. It no longer
retains a second full baseline page-image array. `memoryLayout` copies sorted physical indices and
permissions without extracting bytes. `copyMemoryPage` takes a nominal position in the supplied
owner's sorted map and copies exactly one page into caller-owned storage, returning its actual
mapping description. Invalid/default owners, positions and output lengths fail before modifying
output. This privileged snapshot observer includes retained inaccessible bytes, like `pageImage`;
it does not grant guest access or return mutable backing storage.

Frame admission still checks the complete page count before layout allocation. The builder groups
adjacent equal-permission descriptions and copies immutable page chunks directly into its private
resident buffers. Reset reads those bytes from the accepted source root. Native memory descriptors
continue to borrow only those resident buffers for the call; code caches retain no invocation
memory. Mapping/permission replacement retains the existing checked fallback admission.

Publication materializes baseline bytes only for dirty pages, compares current bytes and uses the
same checked immutable replacement API. Repeated observations keep their immutable snapshots.
Successful host resume makes the accepted posterior the next immutable baseline; a duplicate
changed-page image array and full-payload refresh are no longer needed. Rejected host replies
leave the stopped frame and original baseline intact.

## Independent byte witnesses

`checkFlatSource` now takes caller-owned baseline images captured before execution. Existing unit
and native witness callers provide their independent input images (or an explicit empty map),
including the accepted posterior after host remapping. It still compares every source byte and
permission. Diagnostic witnesses are not retained in release execution frames. Complete reference
CPU/RAM, source immutability, retained-snapshot, fault/retry and ordered-host checks remain separate.

## Verification and measurement

The memory chunk suite covers copied layout, low/inaccessible/high pages, exact positional output,
source/copy isolation and unchanged output on invalid owner/position/length, plus its existing1000
ARC lifetimes. Entry, all-opcode, accounting, memory-pair, publication, sparse, resource and ARM
region-refusal suites cover the changed constructor/reset/publication paths. Existing native and
forced-refusal witnesses cover cached execution and memory replacement.

Local source tests are in progress. ARM entry/lifecycle and DOOM init/tick comparisons against
parent `263fc330a73da61541db451a2c6500325beac965` are required before adoption, using matched
checked ARC/Clang/ThinLTO and independent complete-state/event controls. Report raw CPU and
our-time/PolkaVM-interpreted ratios. No speed or live-memory reduction is claimed before the
matched measurements. Broad CI is reserved for the final integration boundary after local and
focused qualification.
