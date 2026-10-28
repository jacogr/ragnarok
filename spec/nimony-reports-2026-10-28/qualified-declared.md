# Qualified declared() crashes with an unconsumed NIF child assertion

## Nim Version

```text
0.6.3 [macosx; arm64]

```

Official October 26, 2026 archive, commit
`358b9bce4dd855453f57a80a0c499b0b2e27d7ee`. `uname -srmp`:
`Darwin 27.0.0 arm64 arm`.

## Description

In an empty directory, save this one-line file as `repro.nim`:

```nim
discard declared(system.missingSymbol)
```

Run:

```sh
nimony c --mm:arc --cc:clang --nimcache:cache --out:repro repro.nim
```

A qualified operand to `declared` triggers an internal compiler assertion.

## Current Output

Exit code: 1.

```text
assertions.nim(38)       raiseAssert
Error: unhandled exception: nifcore.nim(1281, 3) `c.rem == 0` into: body did not consume all 6 children (left 6) [AssertionDefect]
nifmake: command failed (exit code 1): /Users/<user>/Projects/<project>/build/toolchain/nightly-358b9bce4dd855453f57a80a0c499b0b2e27d7ee/nimony/bin/nimsem --mm:arc --cc:clang --nimcache:cache --define:nimNativeAlloc --define:nimNativeIo m --isMain cache/repn6ksyd1.p.nif
FAILURE: /Users/<user>/Projects/<project>/build/toolchain/nightly-358b9bce4dd855453f57a80a0c499b0b2e27d7ee/nimony/bin/nifmake --rerun -j run --progress:0:50 cache/repn6ksyd1.build.nif
```

## Expected Output

Resolve the probe to a Boolean, or report an ordinary source diagnostic if the qualified form
is unsupported. The pinned `lib/std/system.nim:64` declares
`func declared*(x: untyped): bool {.magic: Declared.}`. That declaration alone does not establish
support for every qualified operand; either outcome should be handled without an internal
assertion. The equivalent unqualified missing-name probe compiles successfully.

## Known Workarounds

This standalone alternative compiles with exit code zero under the same command:

```nim
discard declared(missingSymbol)
```

In the original PVM guard, unqualified lookup is used only for the availability check; the value
reference inside the branch stays module-qualified. This is a context-specific source alternative,
not a claim that qualified and unqualified lookup always resolve identically.

## Additional Information

The final one-line reproducer failed with the same assertion in five independent empty directories
outside the project. Removing its only line compiles with exit zero. The unqualified control
also compiles with exit zero. No project imports or configuration are required. These are
compilation checks; control executables were not run. Earlier probes with an aliased
`std/assertions` import also reproduced the same assertion for existing and absent names.

Searches of open/closed upstream issues and PRs for qualified declared, declared crash and the
assertion text found no exact trigger match on October 28, 2026.
[Issue #2612](https://github.com/nim-lang/nimony/issues/2612) has the same assertion family but
reports 115 children in a different program; it does not establish that this trigger is already
covered. Refresh duplicate triage before submission. No root cause is asserted.

Newest nightly/current master, other compiler versions, Linux runtime and a regression bisect:
not checked. Retest the next nightly before deciding to submit. This is a local draft for
maintainer review, not a filed issue. Private project paths in the final observed output are
redacted as `/Users/<user>/Projects/<project>`; other output is unchanged.
