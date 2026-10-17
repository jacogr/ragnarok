# Owned codec snapshots on Nimony

Target: Gray Paper v0.8.0 and the pinned codec definitions in [codec](codec.md),
[bounded containers](bounded-containers.md), [composites](composite.md) and
[work digests](work-digest.md). This compiler port changes no wire encodings or protocol pins.
Implementation: `src/codec/owned.nim`. Scope: Bytes, Optional, Work, Preimages and Digest.

## Retention and extraction

`decodeOwned*` validates the complete selected prefix and deep-copies only those consumed bytes.
Preimage record allocation remains bounded by policy, minimum wire extent and checked host size.
Private acyclic ARC storage contains its schema, wire bytes, copied record spans and fixed values.
No retained pointer addresses the caller's original input. That input may be mutated or released
after the call; unrelated trailing bytes do not enter the snapshot.

`OwnedFrame` copies retain the same immutable backing storage. Overwriting or dropping one handle
cannot invalidate another. Default handles have an explicitly nullable reference and yield typed
`InvalidOwner` errors. Accessors retain one stable local reference before testing nil so Nimony
can prove subsequent reads; no unchecked-null compatibility feature or compiler assumptions apply.
Last-owner ARC release frees its owned sequences and record storage.

`ownedInfo` and schema-specific queries return copied scalar metadata. `ownedService` returns a
nominal service ID; payload lengths and copies are selected by an index checked against that owner.
`copyOwnedBlob` accepts the owner, index and destination, with **no second source buffer**. Safe
callers cannot access mutable wire bytes or detach coordinates for use against a different pool.
`encodeOwned` re-emits the exact validated prefix. Insufficient destinations, missing owners,
wrong schemas and invalid indices return typed failure before changing any destination byte.

## Result and metadata safety

`OwnedResult[T]` has private status and payload alternatives. `error` is read-only; `value` has
Nimony's success precondition. Default results remain `OwnershipError.Uninitialized` and cannot
expose a default owner, metadata object, service, integer or Boolean as decoded data.
`OwnedOptionalInfo` exposes read-only presence and guards its length on presence. `OwnedWorkInfo`
exposes a read-only work tag and guards length on Success. All six work errors remain successful
frame values with no readable payload length. Empty present/success payloads remain valid zeros.

Sibling adapters use `ownedFailure[T]` (reason other than None) or `ownedSuccess[T]` (explicit
completed value). Work metadata builders require a nonnegative successful length or a non-Success
payload-free tag. These builders report a sibling operation; they do not independently validate
arbitrary handles. Owner APIs always check the actual private backing reference, including when a
caller explicitly wraps a default handle in a generic success result.

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
