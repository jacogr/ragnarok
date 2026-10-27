# Sequence slicing fails inside the standard library noSideEffect body

Submitted as [nim-lang/nimony#2782](https://github.com/nim-lang/nimony/issues/2782), fixed by [#2789](https://github.com/nim-lang/nimony/pull/2789). The October 26 archive `358b9bce4` passes the original reproducer; this file preserves the original October 23 report evidence.

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
let data = @[1]
discard data[0..0]
```

Slicing a one-element integer sequence fails while instantiating the standard slice implementation.

## Current Output

Exit code: 1.

```text
../../../../../../../Users/<user>/Projects/<project>/build/toolchain/nightly-4724f66c2e01b17810c844f26575b2317995fda2/nimony/lib/std/system.nim(645, 12) Error: cannot mutate rawData(result)[i] through a ref/ptr in a `.noSideEffect` context
nifmake: command failed (exit code 1): /Users/<user>/Projects/<project>/build/toolchain/nightly-4724f66c2e01b17810c844f26575b2317995fda2/nimony/bin/nimsem --mm:arc --cc:clang --d:release --nimcache:cache --define:nimNativeAlloc --define:nimNativeIo m --isMain cache/repn6ksyd1.p.nif
FAILURE: /Users/<user>/Projects/<project>/build/toolchain/nightly-4724f66c2e01b17810c844f26575b2317995fda2/nimony/bin/nifmake --rerun -j run --progress:0:100 cache/repn6ksyd1.build.nif
```

## Expected Output

Compile successfully and discard a fresh one-element sequence containing 1. The pinned [] doc comment specifies a fresh seq with copies of the inclusive range. Contract: https://github.com/nim-lang/nimony/blob/4724f66c2e01b17810c844f26575b2317995fda2/lib/std/system.nim#L636

## Known Workarounds

This alternative compiled and ran successfully with the same ARC/Clang checked-release profile:

```nim
import std/assertions
let data = @[1]
var prefix = newSeq[int](1)
prefix[0] = data[0]
assert prefix == @[1]
```

## Additional Information

Five runs from independent empty directories outside the project reproduced the intended failure (5/5). Deleting any one nonblank source line stops that intended failure. The workaround's compilation and executable both returned zero.

The same minimized source also fails on official October 22 commit `8cb7a690ae48363eb3ce65564aafb921ca5d23f3`. No older-version bisect was performed. GitHub master matched the October 23 archive commit when checked; an independent build from master and other compiler implementations were not checked. The official macOS archive checksum and NIGHTLY.txt identity were verified before execution.

No exact duplicate found in searches for slice and noSideEffect slice.

The user-home and transient working-directory prefixes in Current Output are redacted as `/Users/<user>/Projects/<project>` and `/tmp/<reproducer>`; all other output is copied from the final observed run. This preserves the original draft subsequently submitted as #2782. No root cause is asserted.
