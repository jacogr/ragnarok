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
