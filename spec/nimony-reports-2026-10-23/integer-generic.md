# SomeInteger-constrained formatting is rejected at the dollar call

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
proc number[T: SomeInteger](value: T): string = $value
```

The generic body rejects `$value` even though SomeInteger covers integer types with scalar formatting overloads.

## Current Output

Exit code: 1.

```text
repro.nim(1, 49) Error: Type mismatch at [position]
$(value)
[1] expected: uint64 but got: T (declared in ../../../../../../../Users/<user>/Projects/jacogr/ragnarok-misc/build/toolchain/nightly-4724f66c2e01b17810c844f26575b2317995fda2/nimony/lib/std/system/formatint.nim(97, 1))
[1] expected: int64 but got: T (declared in ../../../../../../../Users/<user>/Projects/jacogr/ragnarok-misc/build/toolchain/nightly-4724f66c2e01b17810c844f26575b2317995fda2/nimony/lib/std/system/formatint.nim(101, 1))
[1] expected: int32 but got: T (declared in ../../../../../../../Users/<user>/Projects/jacogr/ragnarok-misc/build/toolchain/nightly-4724f66c2e01b17810c844f26575b2317995fda2/nimony/lib/std/system/formatint.nim(105, 1))
[1] expected: bool but got: T (declared in ../../../../../../../Users/<user>/Projects/jacogr/ragnarok-misc/build/toolchain/nightly-4724f66c2e01b17810c844f26575b2317995fda2/nimony/lib/std/system.nim(88, 1))
[1] T does not match constraint T (declared in ../../../../../../../Users/<user>/Projects/jacogr/ragnarok-misc/build/toolchain/nightly-4724f66c2e01b17810c844f26575b2317995fda2/nimony/lib/std/system.nim(91, 1))
[1] expected: string but got: T (declared in ../../../../../../../Users/<user>/Projects/jacogr/ragnarok-misc/build/toolchain/nightly-4724f66c2e01b17810c844f26575b2317995fda2/nimony/lib/std/system/stringimpl.nim(1063, 1))
[1] expected: float64 but got: T (declared in ../../../../../../../Users/<user>/Projects/jacogr/ragnarok-misc/build/toolchain/nightly-4724f66c2e01b17810c844f26575b2317995fda2/nimony/lib/std/system/formatfloat.nim(1587, 1))
[1] expected: float32 but got: T (declared in ../../../../../../../Users/<user>/Projects/jacogr/ragnarok-misc/build/toolchain/nightly-4724f66c2e01b17810c844f26575b2317995fda2/nimony/lib/std/system/formatfloat.nim(1592, 1))
nifmake: command failed (exit code 1): /Users/<user>/Projects/jacogr/ragnarok-misc/build/toolchain/nightly-4724f66c2e01b17810c844f26575b2317995fda2/nimony/bin/nimsem --mm:arc --cc:clang --d:release --nimcache:cache --define:nimNativeAlloc --define:nimNativeIo m --isMain cache/repn6ksyd1.p.nif
FAILURE: /Users/<user>/Projects/jacogr/ragnarok-misc/build/toolchain/nightly-4724f66c2e01b17810c844f26575b2317995fda2/nimony/bin/nifmake --rerun -j run --progress:0:100 cache/repn6ksyd1.build.nif
```

## Expected Output

Accept this constrained declaration. The pinned basic_types.nim defines SomeInteger as all signed/unsigned integer types; formatint.nim exports scalar integer dollar overloads. Contract: https://github.com/nim-lang/nimony/blob/4724f66c2e01b17810c844f26575b2317995fda2/lib/std/system/basic_types.nim#L52

## Known Workarounds

This alternative compiled and ran successfully with the same ARC/Clang checked-release profile:

```nim
import std/assertions
proc number(value: uint64): string = $value
assert number(7'u64) == "7"
```

## Additional Information

Five runs from independent empty directories outside the project reproduced the intended failure (5/5). Deleting any one nonblank source line stops that intended failure. The workaround's compilation and executable both returned zero.

The same minimized source also fails on official October 22 commit `8cb7a690ae48363eb3ce65564aafb921ca5d23f3`. No older-version bisect was performed. GitHub master matched the October 23 archive commit when checked; an independent build from master and other compiler implementations were not checked. The official macOS archive checksum and NIGHTLY.txt identity were verified before execution.

Related but different triggers: https://github.com/nim-lang/nimony/issues/1026 (SomeFloat equality) and https://github.com/nim-lang/nimony/issues/1974 (top-level phased when checking).

The user-home and transient working-directory prefixes in Current Output are redacted as `/Users/<user>` and `/tmp/<reproducer>`; all other output is copied from the final observed run. This is a draft for maintainer review, not a submitted issue. No root cause is asserted.
