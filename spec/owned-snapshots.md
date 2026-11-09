# Owned codec snapshots on Nimony

Target: Gray Paper v0.8.0 and the pinned codec definitions in [codec](codec.md),
[bounded containers](bounded-containers.md), [composites](composite.md) and
[work digests](work-digest.md). This compiler port changes no wire encodings or protocol pins.
Implementation: `src/codec/owned.nim`. Scope: Bytes, Optional, Work, Preimages and Digest.

The [snapshot module](../src/codec/owned.nim) owns prefix retention, owner-bound
extraction, guarded payload access and atomic output. Its sibling constructors
report a caller operation. Owner accessors still validate the actual backing handle.

## Verification

The checked ARC/Clang LTO runtime verifier is `tools/test_runtime.py`. It includes the existing
10,000-case five-schema fuzz suite and shared successful-prefix/payload comparisons. Focused tests
cover caller-input mutation, escaped stack inputs, retained copies, handle replacement, detached
output mutation, two same-sized distinct owners, default-owner errors, schema/index failures,
short-output atomicity, exact preimage service IDs and complete digest metadata.

A release workload warms up 100 calls, then runs 1,000 varying-payload retain/copy/drop cycles
across all five schemas. It checks equal live occupancy using public `getOccupiedMem()` before
and after isolated scopes; results retain the exact counts. This tests that workload's ARC release,
not RSS behavior or general leak freedom. It uses no private allocator/refcount hooks.

The increment adds 27 exact runtime contract rejections and 14 member/API-specific compilation
rejections. Runtime cases cover eight generic result payload types on default/actual failures,
absent optional lengths, all six work-error lengths and invalid explicit constructors. Compilation
checks reject raw result/metadata fields, retagging, raw success construction, public-property
assignment, backing-store access and a second source pool argument.

The subsequent [report port](work-report.md#nimony-port-verification) applies the same immutable
retention and guarded generic result contracts to `OwnedReport`. It adds the independent full
report corpus and its own 1,000-cycle retain/replace/drop workload, with live occupancy unchanged
at 192 bytes on the trial Mac. Linux confirmation and higher-level migration remain separate work.
