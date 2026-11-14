# Suspected stale direct field read after ARM JIT call in a width loop

## Nim Version

The pinned compiler's `nimony -v` output on this host:

```text
0.6.3 [macosx; arm64]

```

The installed archive is pinned to `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4` by
[`spec/toolchain.json`](../toolchain.json). `uname -srmp` returned
`Darwin 27.0.0 arm64 arm`. The retained binary was compiled before this report;
a fresh build of the tracked candidate has not been checked.

## Description

The [project-bound candidate](counter-field-cse.nim) exercises the original
raw and full-context ARM call routes over widths, aliases and regions. In its
first accepted width case, it reads `jit.operations` before and after each
call and also reads the same field through a `noinline` observer. The direct
raw-field read reports the old value while the observer reports the increment.
The candidate imports Ragnarök modules; a standalone standard-library-only
reduction and a fresh exact build command remain pending.

For this draft, the retained executable was run from the repository root with:

```sh
build/pvm-stage-zero-master/build/counter-bridge-width-observed
```

The private build manifest records `--mm:arc --cc:clang -d:release
-d:pvmArm64Jit` against the pinned compiler. The generated C and source
correspond to the retained executable; this run alone does not prove an
upstream compiler defect.

## Current Output

The command above exited with code 1. Its stdout bytes, represented with
Python string escapes to preserve the trailing space, were:

```text
'COUNTER_OBSERVATION,0,0,1,0,1,1\n[Assertion Failure] \n'
```

In the retained generated C at
`build/pvm-stage-zero-master/build/counter-bridge-width-observed-cache/c/pvm697ola1/pvm697ola1.c`,
line 2196 reads `operations_0` before both native calls, and line 2246 uses
that saved value for the later direct-field observation. Lines 2247–2248
call the `noinline` observer, which reads 1. This establishes the observed
stale expression in generated C; it does not identify which compiler pass
caused it.

## Expected Output

For the first accepted case, both calls return successfully and each owner
increments its `operations` field once in `callArmMemoryCore`. The direct and
observer readings should therefore agree:

```text
COUNTER_OBSERVATION,0,1,1,0,1,1
```

The source implementation is in
[`arm64_jit.nim`](../../src/pvm/internal/arm64_jit.nim), in the
`callArmMemoryCore` operation update. A language-contract check for cross-call
field visibility is still pending; this is a suspected compiler issue.

## Known Workarounds

The supported native witness reads this test-only counter through
`observedOperations(jit: ArmJit): uint64 {.noinline.}`. Its accepted and
refused raw/full cases pass with that observer, including the 378 width
cases. No production counter workaround or compiler change is used.

## Additional Information

The original direct-field width-loop source and paired observed variant are
preserved under ignored `build/pvm-stage-zero-master/tests/performance/`;
their generated C and process logs remain under that workspace's `build/`.
The tracked candidate here retains the observed variant unchanged apart from
its opening comment. A smaller standard-library-only counter control in the
same private area printed the expected increment, so the width-loop context
still matters; no specific root cause is asserted.

Pending: reduce to a standalone line-minimal file; run it from five clean
directories; confirm the expected language contract; test the current
upstream compiler and Linux; search open and closed upstream issues/PRs;
establish whether this behavior is a regression. No upstream issue or comment
has been submitted. Retest the unchanged candidate and supported native
witness before retiring the scoped observer.

## November 14 fresh fragment-loop observation

Full upgrade CI on `5f20ea10705d2245025df41dec8be89e207d388c` fails the ARM native
qualification witness on Linux ARM64. The same unchanged checked ARC/Clang ThinLTO witness
fails locally with official compiler `8102b8e3c46bde87b733ecd82e2249cb562e3a8f`, macOS ARM64;
with the pristine November 9 compiler `fd9742bf1`, it passes all 31 macro backend cases and
13,524 macro frame cases. The failure is after the printed bounded-continuation receipts,
not in the earlier successfully printed guarded-load cases.

In `armMacroBackendControls`, this genuine arena-fill loop should stop at the physical ledger's
8,192-fragment ceiling:

```nim
while capped.fragments < 8192:
  var words: seq[uint32] = @[0xd503201f'u32]
  assert publishArmEntry(capped, offset, offset+1, 1, words, true)
  inc offset
```

The new compiler's generated C captures the field before the loop and tests that same local
on every iteration, despite `publishArmEntry` incrementing the owner's field after each
successful arena append. Diagnostic strings added only in a scratch copy identify the eventual
failure as the next publication's capacity refusal. A bounded-count variant also reuses a stale
field snapshot in its final assertion. Generated-C excerpts (names shortened for readability):

```c
uint64_t snapshot = capped->fragments;
if (snapshot < 8192) {
  while (true) {
    bool accepted = publishArmEntry(capped, /* ... */);
    /* original publication assertion and offset increment */
    if (!(snapshot < 8192)) break;
  }
}
```

Reuse the fixture's existing `observedFragments(...){.noinline.}` at the loop condition and final
fragment assertion. This keeps the live physical ledger, every successful publication assertion,
the exact final count, macro refusal and unchanged-child checks. No production code, arena limit,
runtime check or compiler is changed. The existing observer also serves the separate capacity
fixture; it is moved earlier so this caller can use it.

The relation to the original November 3 observation is a shared direct-field visibility symptom,
not a proven identical compiler-pass cause. A fresh import-only small arena loop and small
stdlib-only reference/sequence mutation controls pass; the larger caller context remains material.
Standalone failing reduction, five independent minimal runs, contract/duplicate review and testing
source-built current upstream remain pending. This is project-bound evidence, not a ready upstream
draft. Raw old/new commands, exact generated C and diagnostics remain under ignored
`build/upstream-watch/nimony/2026-11-14/ci-repair/`.
