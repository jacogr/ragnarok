# Suspected conditional generic handler-value lowering failure

Status: project-bound observation, not ready for upstream submission. The full build failed in
`shoggoth`; two small standard-library-only controls compile. A standalone failing reduction,
five fresh-directory repetitions and current upstream testing remain pending.

The observed compiler is the pristine official macOS ARM64 nightly
`fd9742bf1939a1b754144506e89a8acb0e7b747a` (November 9 archive), tested November 14, 2026.
The archive's `NIGHTLY.txt` records that exact revision and `platform: macos_arm64`.
No compiler, standard-library or dependency source was modified.

## Observed project shape

During indirect-dispatch development, `bindFlatFusion` selected the existing non-closure
handler instantiation through a conditional proc-value expression:

```nim
let expected = if fact.opcode == 50: flatDynamic[50, false] else: flatDynamic[180, false]
if worker != expected or args != payload.args: return false
```

The generic routine has this signature, with its existing checked-dispatch body:

```nim
proc flatDynamic[Code: static[int]; Single: static[bool]](
    f: var FlatFrame, off: uint32): uint32
```

`FlatHandler` is `proc(f: var FlatFrame, off: uint32): uint32 {.nimcall, raises: [].}`.
Semantic checking accepted the source. The checked ARC/Clang ThinLTO native build failed during
optimization with exit code 1:

```text
assertions.nim(38)       raiseAssert
Error: unhandled exception: Symbol not found in NIF module: `iir.1001.hanpyzcax1 [AssertionDefect]
```

The emitted C NIF assigns that undeclared generated symbol to the true branch's temporary;
the false branch refers to a concrete `flatDynamic` instantiation. This is an observed artifact,
not a diagnosis of the responsible pass or a proof that the source shape is valid in all contexts.

The original invocation was the ordinary `NativeChecks.build` profile:

```sh
NIMONY c --mm:arc --cc:clang -d:release --opt:speed --boundchecks:on \
  --passC:-flto=thin --passL:-flto=thin \
  -d:pvmArm64Jit -d:pvmSharedAsyncWitness -d:pvmPaidMixedLoopWitness \
  --passC:-I<checkout>/native/pvm_jit --passC:-I<checkout>/tests/performance \
  --nimcache:<private-cache> --out:<private-output> \
  <checkout>/tests/unit/codec/test_pvm_shared_async_arm.nim
```

`NIMONY`, `<checkout>` and the output/cache names above replace local absolute paths. The
retained failed log is `build/horizon/dispatch-shared-build.log`, with its source hashes in
`dispatch-shared-sources.json` and generated C NIF in the same private compiler cache. The failure
predates later fixture additions, so restoring the snippet in the current tree is a proposed
retest, not a claimed exact reproducer.

## Controls and supported implementation

A one-file control selects `genericHandler[50, false]` or `genericHandler[180, false]` from an
`if` expression and calls it through the resulting proc type. A second control first instantiates
both through a `case` factory, then compares the selected proc value with the conditional result.
Both compile and execute successfully with the same pinned checked ARC/Clang ThinLTO profile.
Their retained files/logs are `build/horizon/generic-callback-probe.*` and
`build/horizon/generic-callback-repeat.*`. They are passing controls, not failing reproducers.

The maintained implementation compares `worker` directly with `payload.handler`, which the
existing immutable-source decoder already constructs for this exact original opcode. It also
checks the complete original arguments. This avoids redundant handler selection while retaining
the source proof; it introduces no compiler patch, unsafe cast or weaker runtime validation.
The full shared-runtime suite passes with that implementation.

## Contract and duplicate checks

The pinned [proc-type contract](https://github.com/nim-lang/nimony/blob/fd9742bf1939a1b754144506e89a8acb0e7b747a/doc/language.md#proc-type)
describes ordinary proc values as proc pointers and distinguishes them from explicitly annotated
closures. These handlers capture no environment. That supports the intended shape but does not
settle the unreduced full-project failure. A broader generic/conditional lowering contract review
and a `v2` feature-control retest have not been completed.

The November 14 official `nim-lang/nimony` issue searches for `"Symbol not found"` and
`shoggoth generic proc` found no confirmed duplicate. [Issue #2961](https://github.com/nim-lang/nimony/issues/2961)
reports a stale C module after removing a standard-library `requires` clause; this observation
does not involve that edit, and equivalence has not been established. No issue was filed and
upstream master was not tested. Preserve this record until the full-project failure can be
reduced and classified.


## November 15 pinned-build observation

The pristine official `8102b8e3c46bde87b733ecd82e2249cb562e3a8f` macOS ARM64 archive
also accepted semantic checking of a register-dispatch test that selected `flatRegisterPair[149]`
or `flatRegister[149]` through a conditional procedure-value expression, then failed its checked
ARC/Clang ThinLTO native build with the same undeclared `iir.1001` symbol in `shoggoth`.
The retained build is `build/windows/dispatch-final-arm-build.log` and its private compiler cache;
`build/compiler-issues/recursive-handler-seq/failed-probe.nim` retains the test shape. This is a
second project-bound observation, not a standalone reproducer or an upstream diagnosis.

Two reduced recursive procedure-container controls compiled with this archive. The supported
witness uses the existing `flatHandler` and `flatRegisterPairHandler` factories, checks their
results, and exercises those ordinary dispatch procedure values. Full native ARM shared tests
pass with that construction, including invalid offsets, missing continuations and valid offsets
above the optional native image coordinate ceiling. No compiler source or pin was changed.
Five fresh failing reductions, current upstream testing and a confirmed root cause remain pending.

The [November 15 composition-trial follow-up](../nimony-reports-2026-11-15/fusion-handler-composition.md)
adds a portable project patch and five independent fresh-cache failures on `8102b8e3`, with
matching successful parent builds. It is not a standalone reduction and does not establish that
the observations have the same root cause. The composition implementation remains unshipped.
