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

All listed local source suites and the complete existing ARM native/forced-refusal witnesses
passed with pinned checked ARC/Clang/ThinLTO. The memory chunk lifetime check returns192 managed
bytes before and after1000 owners. These are local results, not Linux CI qualification.

A matched four-process memory matrix against parent
`263fc330a73da61541db451a2c6500325beac965` uses the same frozen driver, six scenarios,
1/64/1024/4096 mapped pages, both process orders and3 warmup plus10 retained samples per case
(312 rows per process). Independent source/posterior byte witnesses are sealed outside all
clocks for both roles. At1024–4096 pages, entry CPU falls42–49% and complete call/retirement
CPU falls45–52%. At4096 pages the live managed frame allocation falls from34,758,656 to
17,494,016 bytes. This allocation delta excludes the already-owned immutable input and external
diagnostic witnesses; it is not process RSS or executable-mapping accounting. Single-page
results are mixed at microsecond resolution and establish no small-frame speed improvement.

The unchanged public DOOM driver also passes complete CPU/RAM, ordered events, source ownership,
backend-policy and positive native-coverage checks, plus two assertion-negative controls.
Each role runs in both orders with3 warmup and10 retained samples. Local median CPU milliseconds:

| Phase | Parent JIT, forward/reverse | Page metadata JIT, forward/reverse | PolkaVM interpreted, forward/reverse | Our JIT / PolkaVM interpreted |
| --- | --- | --- | --- | --- |
| DOOM init |179.788 /179.637 |176.365 /176.306 |671.416 /671.215 |0.263 /0.263 |
| DOOM tick |28.358 /28.212 |27.332 /27.237 |43.867 /44.214 |0.623 /0.616 |

This is about1.9% lower init CPU and3.5–3.6% lower tick CPU against the immediate parent.
The explicit interpreter role records323.375 /322.846 ms init (ratios0.482 /0.481) and
37.431 /37.433 ms tick (ratios0.853 /0.847); no paired interpreter speed claim is made.
Prepared input, expected-state, events, ROM and reference hashes match the previous fully
passed local DOOM cohort. A later setup invocation's sandbox-blocked `sysctl` marker is not
used as a passed setup receipt.

Private reproducibility receipts and full raw controls are under
`build/pvm-page-metadata/{measure,doom}`, with complete native witness receipts in
`build/pvm-page-metadata/qualification.json`. Candidate production source is frozen at
`411213a23223c5568b4d38047cca592b0dadc689`; subsequent evidence prose is source-equivalent.
Focused Linux ARM comparison remains required. Broad CI is reserved for the final integration
boundary after local and focused qualification.
