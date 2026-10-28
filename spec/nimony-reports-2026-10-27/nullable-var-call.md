# A second mutable pointee call loses a guarded local pointer non-null proof

Filed by the maintainer as [nim-lang/nimony#2809](https://github.com/nim-lang/nimony/issues/2809) on October 27, 2026.

## Upstream resolution and local retest

Fixed upstream by [#2811](https://github.com/nim-lang/nimony/pull/2811), followed by [#2813](https://github.com/nim-lang/nimony/pull/2813). The official October 28 archive `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4` compiles and executes the inferred-pointer reproducer and explicitly typed control, including nil input. The guarded block/session and ancestor callback annotations are removed with a native regression and affected consumer checks; see the [upgrade audit](../nimony-nightly-2026-10-28.md). Original failing output follows as historical evidence.

## Nim Version

```text
0.6.3 [macosx; arm64]
```

Official October 26, 2026 Nimony archive, commit `358b9bce4dd855453f57a80a0c499b0b2e27d7ee`; Darwin 27.0.0 arm64.

## Description

From an empty working directory, save this as `repro.nim` and run:

```sh
nimony check --mm:arc --cc:clang -d:release --boundchecks:on --nimcache:cache repro.nim
```

```nim
proc touch(value: var int) = inc value
proc receive(input: nil ptr int) =
  if input == nil: return
  let receiver = input
  touch(receiver[])
  touch(receiver[])
```

The first call after the nil guard succeeds; the second identical call rejects the immutable local pointer.

## Current Output

Exit code: 1.

```text
repro.nim(6, 9) Error: cannot prove expression is not nil: receiver [pass --verbose for the Final IR]
nifmake: command failed (exit code 1): /Users/<user>/Projects/<project>/build/toolchain/nightly-358b9bce4dd855453f57a80a0c499b0b2e27d7ee/nimony/bin/nimsem --mm:arc --cc:clang --d:release --nimcache:cache --define:nimNativeAlloc --define:nimNativeIo m --isMain cache/repn6ksyd1.p.nif
FAILURE: /Users/<user>/Projects/<project>/build/toolchain/nightly-358b9bce4dd855453f57a80a0c499b0b2e27d7ee/nimony/bin/nifmake --rerun -j run --progress:0:100 cache/repn6ksyd1.build.nif
```

## Expected Output

Accept both calls: the nil guard establishes a present pointer, and touch changes an integer pointee without assigning the local pointer. The pinned nil-safety guide documents guarded nullable dereferences and not-nil ptr types. Contract: https://github.com/nim-lang/nimony/blob/358b9bce4dd855453f57a80a0c499b0b2e27d7ee/doc/lenientnils.md

## Known Workarounds

This alternative compiled and ran successfully with the same ARC/Clang checked-release profile:

```nim
import std/assertions
proc touch(value: var int) = inc value
proc receive(input: nil ptr int) =
  if input == nil: return
  let receiver: ptr int = input
  touch(receiver[])
  touch(receiver[])
var value = 1
receive(addr value)
assert value == 3
```

## Additional Information

Five runs from independent empty directories outside the project reproduced the intended failure (5/5). Deleting any one nonblank source line stops that intended failure. The workaround's compilation and executable both returned zero. The official macOS archive checksum and embedded commit/date/platform were verified before execution.

The October 23 draft records the earlier failure on `4724f66c2e01b17810c844f26575b2317995fda2`; this refresh tests the October 26 official archive. A separate build of current master, Linux runtime, other compiler implementations and a regression bisect were not checked.

Related but different triggers: https://github.com/nim-lang/nimony/issues/2110 (compound-field nil refinement) and https://github.com/nim-lang/nimony/issues/1984 (different nilability/pragma trigger).

Private project and transient directory paths in Current Output are redacted as `/Users/<user>/Projects/<project>` and `/tmp/<reproducer>`; all other output is copied from the final observed run. The maintainer submitted the issue linked above; no issue was posted by the agent. No root cause is asserted.
