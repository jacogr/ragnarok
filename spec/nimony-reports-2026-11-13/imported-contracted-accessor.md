# Calling an imported accessor with `requires` crashes nimsem with `could not find symbol`

Submitted by the maintainer as [Nimony #2994](https://github.com/nim-lang/nimony/issues/2994).

Nimony 0.6.3 on macOS 27.0.1 (26A434), ARM64. Reproduced with the official November 13 nightly (`5e6c57df81246da6044d7ebc2151d5ae593a3ca6`) using `nimony check`.

`nimsem` crashes when checking a comparison between two calls to an imported accessor with a field precondition. The caller checks that both cursors are initialized before the comparison.

## Reproduction

Save both files in the same empty directory.

`model.nim`

```nim
type
  Ordinal* = distinct uint64
  Cursor* = object
    ready: bool
    last: uint64
func `==`*(a, b: Ordinal): bool = uint64(a) == uint64(b)
func initialized*(c: Cursor): bool = c.ready
func lastOrdinal*(cursor: Cursor): Ordinal {.requires: cursor.ready.} =
  Ordinal(cursor.last)
```

`small.nim`

```nim
import ./model
type Selection = object
  cursor: Cursor
func reselect(before: Selection; cursor: Cursor): bool =
  if not before.cursor.initialized or not cursor.initialized:
    return false
  before.cursor.lastOrdinal != cursor.lastOrdinal
```

```sh
nimony check --opt:none --mm:arc --nimcache:nimcache small.nim
```

## Actual

Exit status 1 during semantic checking.

```text
No stack traceback available
[Bug] could not find symbol: cursor`b.0
nifmake: command failed (exit code 1): <nimony>/bin/nimsem --mm:arc --define:nimNativeAlloc --nimcache:nimcache --stdcache:<nimony>/stdcache/bin/hvhh2q --optionkey:694035061A45B4EF801DE61A81805621F8CF6633 m --isMain nimcache/sma7jy6su.p.nif
FAILURE: <nimony>/bin/nifmake -j run --progress:0:100 nimcache/sma7jy6su.build.nif
```

## Expected

Semantic checking succeeds, as it does with the November 9 nightly.

## Controls

| Official nightly or test variant | Result |
| --- | --- |
| November 9 `fd9742bf1`, two files | Pass |
| November 10 `0305d6c6d`, two files | Same crash |
| November 11 `fd785558e`, two files | Same crash |
| November 12 `4ba90a781`, two files | Same crash |
| November 13 `5e6c57df8`, two files | Same crash |
| November 13, both declarations and caller in one file | Pass |
| November 13, `runtimeContracts` in `small.nim` | Same crash |

The original reproducer from #2643 compiles on the November 13 nightly. The example above still crashes on that same compiler. Current source master and the changes in #2989 were not tested.

## November 14 retest

The unchanged two-file reproducer and single-file control both pass semantic checking with the
official November 14 archive `8102b8e3c46bde87b733ecd82e2249cb562e3a8f`. It contains the
[contract repair](https://github.com/nim-lang/nimony/pull/2989) and
[upstream regression test](https://github.com/nim-lang/nimony/pull/3002).
No storage accessor or contract was changed to bypass this failure. See the
[upgrade qualification](../nimony-nightly-2026-11-14.md) for affected consumer checks.
