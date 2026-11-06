# Omitted variant default argument is rejected although explicit default compiles

## Nim Version

Pinned Nimony archive commit `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`, tested on macOS-27.0.1-arm64-arm-64bit-Mach-O.
The complete `nimony --version` output from this run is:

```text
0.6.3 [macosx; arm64]

```

## Description

Run `nimony check --nimcache:cache main.nim` on this standalone file:

```nim
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Omitted variant defaults must select the same false branch as an explicit default value.
type Value = object
  case present: bool
  of true: payload: int
  else: discard
proc take(value = default(Value)) = discard
take()
```

Omitting the argument rejects the inactive variant field even though explicitly passing
`default(Value)` compiles.

## Current Output

The final independent empty-directory run exited1. Only the private toolchain path is redacted
as `<nimony>`; other diagnostic text is unchanged:

```text
main.nim(9, 26) Error: a case selecting discriminator 'present' with value 'false' appears in the object construction, but the field(s) 'payload' are in conflict with this value.
nifmake: command failed (exit code 1): <nimony>/bin/nimsem --nimcache:cache --define:nimNativeAlloc --define:nimNativeIo m --isMain cache/mai3r4ykk.p.nif
FAILURE: <nimony>/bin/nifmake --rerun -j run --progress:0:100 cache/mai3r4ykk.build.nif
```

## Expected Output

Compiler exit0, as with `proc take(value: Value) = discard; take(default(Value))`.
The pinned `lib/std/system/defaults.nim` defines `default(bool)` as `false`; the false branch
has no payload. A local default and an explicit default argument both compile in the same archive.

## Known Workarounds

A tested domain factory also compiles:

```nim
func empty(): Value = default(Value)
proc take(value = empty()) = discard
take()
```

The application keeps the complex chain context explicit in the full capture overload. Its
computation-only overload obtains an empty view from the existing owning factory.

## Additional Information

Observed facts: the final tracked reproducer failed in5/5 independent empty working directories.
The six non-comment code lines were deletion-tested: removing any one changes/removes the original
failure diagnostic. Local, explicit-argument and factory controls all passed. The original managed
work suite reproduced the same error in a fresh compiler cache.

Official tracker searches covered `default/variant`, `object construction/default` and
`default/parameter/variant`. No exact duplicate was identified in the returned results.
[#2234](https://github.com/nim-lang/nimony/issues/2234) concerns a nested-case compiler assertion,
and [#2218](https://github.com/nim-lang/nimony/pull/2218) changes union construction; neither is
claimed as this omitted-argument trigger. Current upstream/devel and other compiler archives
were not checked. No compiler source, dependency or pin was changed; no issue was filed.

Full commands, outputs, controls and deletion results are retained locally under
`build/compiler-issues/work-recovery-default-view/`. Root cause has not been established.
