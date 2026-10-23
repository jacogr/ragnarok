# A second mutable pointee call loses a guarded local pointer non-null proof

## Nim Version

```text
0.6.3 [macosx; arm64]
```

Nimony official October 23, 2026 archive, commit `4724f66c2e01b17810c844f26575b2317995fda2`; Darwin 27.0.0 arm64.

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
nifmake: command failed (exit code 1): /Users/<user>/Projects/jacogr/ragnarok-misc/build/toolchain/nightly-4724f66c2e01b17810c844f26575b2317995fda2/nimony/bin/nimsem --mm:arc --cc:clang --d:release --nimcache:cache --define:nimNativeAlloc --define:nimNativeIo m --isMain cache/repn6ksyd1.p.nif
FAILURE: /Users/<user>/Projects/jacogr/ragnarok-misc/build/toolchain/nightly-4724f66c2e01b17810c844f26575b2317995fda2/nimony/bin/nifmake --rerun -j run --progress:0:100 cache/repn6ksyd1.build.nif
```

## Expected Output

Accept both calls: the nil guard establishes a present pointer, and touch changes an integer pointee without assigning the local pointer. The pinned nil-safety guide documents guarded nullable dereferences and not-nil ptr types. Contract: https://github.com/nim-lang/nimony/blob/4724f66c2e01b17810c844f26575b2317995fda2/doc/lenientnils.md

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

Five runs from independent empty directories outside the project reproduced the intended failure (5/5). Deleting any one nonblank source line stops that intended failure; deleting the callback guard instead causes an earlier unsafe-dereference error. The workaround's compilation and executable both returned zero.

The same minimized source also fails on official October 22 commit `8cb7a690ae48363eb3ce65564aafb921ca5d23f3`. No older-version bisect was performed. GitHub master matched the October 23 archive commit when checked; an independent build from master and other compiler implementations were not checked. The official macOS archive checksum and NIGHTLY.txt identity were verified before execution.

Related but different triggers: https://github.com/nim-lang/nimony/issues/1984 (or/custom pragma) and https://github.com/nim-lang/nimony/pull/2110 (field-path mutation tracking).

The user-home and transient working-directory prefixes in Current Output are redacted as `/Users/<user>` and `/tmp/<reproducer>`; all other output is copied from the final observed run. This is a draft for maintainer review, not a submitted issue. No root cause is asserted.
