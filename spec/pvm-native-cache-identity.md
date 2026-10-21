# Source-sensitive native cache boundary

## Observed failure and scope

The PVM host-price optimization changed a private helper's arity. The pinned Nimony
0.6.3 `5b51edfedb4d0dbd9028d9e57ac61d69dffe9410` setup retained generated generic calls
from unchanged consumers, yielding old four-argument calls against a new five-argument
declaration. The host-failure suite and benchmark both failed compilation; identical
source passes in fresh project-owned caches. No compiler source or metadata was edited.

A smaller standalone checked ARC/Clang LTO control confirms this source-change boundary.
Its unchanged `main.nim` imports `library.nim` and prints `apply(true)`. Version 1:

```nim
proc helper(value: int): int = value
proc apply*[T](unused: T): int = helper(7)
```

After the successful output `7`, edit only the imported file:

```nim
proc helper(value, extra: int): int = value + extra
proc apply*[T](unused: T): int = helper(7, 5)
```

With the old persistent cache, Clang reports **too few arguments to function call,
expected 2, have 1**, with the retained call `helper_0_lib04sjp81(IL64(7))` and the new
two-argument declaration. Original control sources, exact build commands, compiler
status and logs are retained in `build/pvm-native-cache-repro/`. This narrows the
observed incremental failure; it does not establish the responsible compiler pass
or a compiler-wide cache diagnosis. No upstream report is posted here.

## Project-owned cache policy

Both `NativeChecks` modes and Hastur serial/directory profiles now include a shared
source-content epoch. It discovers runtime Nim sources under `src/`, shared test
sources under `tests/support/`, adjacent compiler inputs and optional root config files.
Nim/include/script/config suffixes are covered. Source contents, names, additions and
deletions affect the key; generated logs do not. Stable trees retain profile reuse
across mains, existing compiler/group/flag/native-ABI isolation, checked flags, private
worker caches and locks. The epoch only chooses project cache directories; it never
rewrites compiler artifacts or substitutes a failed build with an earlier executable.

This deliberately conservative boundary may rebuild unrelated local consumers after
a runtime source edit and leaves older cache epochs under ignored `build/` until normal
cleanup. Clean CI already starts cold. It supplements existing compiler dependency
tracking, native-library/header hashing and runtime provenance; it is not an exhaustive
import resolver or proof that every possible generated/foreign dependency is covered.
No runtime semantics, fixture bytes, source pins or native optimization flags change.

Completion requires stable-tree reuse and source-edit invalidation in both native
builder modes and Hastur profiles, real two-version checked rebuilds with expected
outputs `7` then `12`, and selected native/benchmark verification. Keep failure statuses,
ARC evidence and CI/report freshness checks intact.

## Bounded digest reuse

The Python reference/tooling job in CI run `39631349594` exhausted its 300-second budget.
Local per-test timing identified repeated whole-tree hashing in native command planning as the
largest cost: the linked-profile and unit-entrypoint checks alone spent roughly 73 seconds
rereading the same runtime/support sources, including large PVM fixtures.

Discovery still enumerates source families on every request. A bounded process-local cache reuses
only individual file digests whose device, inode, size, nanosecond mtime and nanosecond ctime are
unchanged. Restored-mtime same-size edits, atomic replacements, additions, deletions and newly
created optional configuration files retain epoch invalidation. Optional absence is never cached.
The epoch schema and content-derived output stay identical to the original full-read algorithm;
no digest metadata is persisted or used as a replacement for runtime provenance.

The optimized planner reproduces the previous content epoch exactly for codec/state/native
source groups. Repeated local planning samples fall from 0.112/0.176/0.122 seconds to
0.015/0.045/0.063 seconds respectively. The full Python check passes 629 tests (four skipped)
in 145.1 seconds locally; the measured baseline took 168.7 seconds before the additional
regression. These are local observations, not Linux CI timing guarantees. Real checked full-LTO
private/shared rebuilds still print `7`, `12`, `12`, with source-edit rotation and unchanged reuse.

## Provision sparse vector blobs before discovery

The Linux retry still reached the five-minute deadline in
`SpecificationTests.test_published_report_sources`. That check verifies every pinned vector blob;
individual `git show` calls in a fresh partial clone can each trigger a separate lazy fetch.
Python discovery does not compile native binaries, so disabling native LTO cannot reduce this cost.

`make check-python` now requests batched blob provisioning during source setup; other groups
retain their focused source setup. The provisioner resolves the existing `spec/pins.json` vector blob paths against the immutable
pinned tree, checks local object availability with lazy fetching disabled and fetches missing blob
identities in one batch. This is dependency provisioning before discovery's deadline. It retains
the sparse working tree, source revision, independent SHA-256 verification and unchanged test
workloads/deadline. Complete or warm clones require no fetch. Missing pinned paths and failed
fetches remain errors. The batch uses the same fetch options as
[Git's promisor fetch implementation](https://github.com/git/git/blob/master/promisor-remote.c),
including disabled negotiation for explicit object wants.

A fresh upstream partial clone fetched the selected pinned blobs in 29.0 seconds locally; all
317 SHA-256 values then verified in 11.7 seconds. Local partial-clone regression tests verify one
cold fetch, offline warm reuse, absent unrelated objects, no working-tree materialization and
missing-path rejection. These timings describe the local network and host, not a Linux guarantee.

## Observed local verification

All 53 source-identity, native profile, Hastur planning/locking and unit orchestration
safeguards pass. The actual checked two-version reproducer prints `7`, then `12`,
then unchanged `12` in both private and shared builder modes. Its source edit selects
a different cache; the unchanged repeat reuses exactly the second cache. Selected
`pvm_host_execution` passes through source-keyed Hastur with stable 1000-cycle ARC
evidence, and `make bench-pvm` passes all five validated interpreted workloads.
No manual cache replacement is needed with the new keys. The PVM runtime/fixtures
match the independently passing preceding layer; its exact-head Linux fixture run
39595533184 covers all fourteen pairs at `bb3ec585`, not this tooling layer's head.
