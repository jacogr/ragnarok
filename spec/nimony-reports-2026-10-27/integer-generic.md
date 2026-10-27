# SomeInteger-constrained formatting is rejected at the dollar call

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
proc number[T: SomeInteger](value: T): string = $value
```

The generic body rejects `$value` although the constraint covers the scalar integer formatting overloads.

## Current Output

Exit code: 1.

```text
repro.nim(1, 49) Error: Type mismatch at [position]
$(value)
[1] expected: uint64 but got: T (declared in ../../../Users/<user>/Projects/<project>/build/toolchain/nightly-358b9bce4dd855453f57a80a0c499b0b2e27d7ee/nimony/lib/std/system/formatint.nim(97, 1))
[1] expected: int64 but got: T (declared in ../../../Users/<user>/Projects/<project>/build/toolchain/nightly-358b9bce4dd855453f57a80a0c499b0b2e27d7ee/nimony/lib/std/system/formatint.nim(101, 1))
[1] expected: int32 but got: T (declared in ../../../Users/<user>/Projects/<project>/build/toolchain/nightly-358b9bce4dd855453f57a80a0c499b0b2e27d7ee/nimony/lib/std/system/formatint.nim(105, 1))
[1] expected: bool but got: T (declared in ../../../Users/<user>/Projects/<project>/build/toolchain/nightly-358b9bce4dd855453f57a80a0c499b0b2e27d7ee/nimony/lib/std/system.nim(88, 1))
[1] T does not match constraint T (declared in ../../../Users/<user>/Projects/<project>/build/toolchain/nightly-358b9bce4dd855453f57a80a0c499b0b2e27d7ee/nimony/lib/std/system.nim(91, 1))
[1] expected: string but got: T (declared in ../../../Users/<user>/Projects/<project>/build/toolchain/nightly-358b9bce4dd855453f57a80a0c499b0b2e27d7ee/nimony/lib/std/system/stringimpl.nim(1063, 1))
[1] expected: float64 but got: T (declared in ../../../Users/<user>/Projects/<project>/build/toolchain/nightly-358b9bce4dd855453f57a80a0c499b0b2e27d7ee/nimony/lib/std/system/formatfloat.nim(1587, 1))
[1] expected: float32 but got: T (declared in ../../../Users/<user>/Projects/<project>/build/toolchain/nightly-358b9bce4dd855453f57a80a0c499b0b2e27d7ee/nimony/lib/std/system/formatfloat.nim(1592, 1))
nifmake: command failed (exit code 1): /Users/<user>/Projects/<project>/build/toolchain/nightly-358b9bce4dd855453f57a80a0c499b0b2e27d7ee/nimony/bin/nimsem --mm:arc --cc:clang --d:release --nimcache:cache --define:nimNativeAlloc --define:nimNativeIo m --isMain cache/repn6ksyd1.p.nif
FAILURE: /Users/<user>/Projects/<project>/build/toolchain/nightly-358b9bce4dd855453f57a80a0c499b0b2e27d7ee/nimony/bin/nifmake --rerun -j run --progress:0:100 cache/repn6ksyd1.build.nif
```

## Expected Output

Accept this constrained declaration. The pinned basic_types.nim defines SomeInteger as all signed/unsigned integer types; formatint.nim exports scalar integer dollar overloads. Contract: https://github.com/nim-lang/nimony/blob/358b9bce4dd855453f57a80a0c499b0b2e27d7ee/lib/std/system/basic_types.nim#L52

## Known Workarounds

This alternative compiled and ran successfully with the same ARC/Clang checked-release profile:

```nim
import std/assertions
proc number(value: uint64): string = $value
assert number(7'u64) == "7"
```

## Additional Information

Five runs from independent empty directories outside the project reproduced the intended failure (5/5). Deleting any one nonblank source line stops that intended failure. The workaround's compilation and executable both returned zero. The official macOS archive checksum and embedded commit/date/platform were verified before execution.

The October 23 draft records the earlier failure on `4724f66c2e01b17810c844f26575b2317995fda2`; this refresh tests the October 26 official archive. A separate build of current master, Linux runtime, other compiler implementations and a regression bisect were not checked.

Related but different triggers: https://github.com/nim-lang/nimony/issues/1026 (SomeFloat equality), https://github.com/nim-lang/nimony/issues/1974 (phased when checking), and https://github.com/nim-lang/nimony/issues/1905 (generic default parameters).

Private project and transient directory paths in Current Output are redacted as `/Users/<user>/Projects/<project>` and `/tmp/<reproducer>`; all other output is copied from the final observed run. This is a draft for maintainer submission; no issue was posted from this task. No root cause is asserted.
