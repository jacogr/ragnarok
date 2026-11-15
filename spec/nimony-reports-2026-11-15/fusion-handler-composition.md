# Suspected handler-value lowering failure during fusion composition

This is another project-bound observation under **NIM-010**, not a confirmed common root cause
or an upstream-ready report. The actual composition candidate did not produce an executable,
so it has no runtime correctness or performance result. No production PVM behavior, compiler
source, build policy or pin is changed by this report.

The pristine November 14 macOS ARM64 archive identifies
`8102b8e3c46bde87b733ecd82e2249cb562e3a8f` in `nimony/NIGHTLY.txt`.
The executable reports `0.6.3 [macosx; arm64]`. These runs used Apple Clang 21.0.0
(`clang-2100.4.1.1`, target `arm64-apple-darwin27.0.0`), checked ARC and ThinLTO.
The [portable receipt](fusion-handler-composition.json) records the compiler executable hash,
both source hashes, patch hash and five observed diagnostics.

## Project input and reproduction

The [complete experimental patch](fusion-handler-composition.patch) applies to Ragnarök
`ee575358c01b00a20aa480d8f9e383851d983097`. The PVM and compiler pin at that commit are identical
to the trial's original parent `2474fdb7f02bc4639f94541f758e326614c19862`.
Applying the patch with `git apply --unidiff-zero` is for reproducing this compiler failure,
not an implementation proposal. The zero-context patch is tied to the exact base and source hashes.
`git apply --unidiff-zero --check` passes against that exact base.

The experiment permits an existing checked adjacent-block header during fusion binding, recognizes
existing combined arithmetic/branch workers, and saves each temporary header's exact predecessor
for quota-aware restoration. The existing original-source, operands, terminal, pricing and target
checks remain in the patch. Its new noncapturing procedure-value bindings include:

```nim
if branch == 83:
  let cold: FlatHandler = flatRegisterBranchCold[131, 83]
  let warm: FlatHandler = flatFusedRegisterBranch[131, 83]
  combinedBranch = worker == cold or worker == warm
```

The owning definitions are present in the base's `src/pvm/internal/handler_stream.nim`.
The patch contains the full source changes; the base commit supplies their dependencies.
Five independent empty directories received identical source copies, each with a fresh private
compiler cache. The executed `NativeChecks.build` command, with absolute local paths replaced
by `<compiler>`, `<source>`, `<cache>` and `<binary>`, was:

```sh
<compiler> c --mm:arc --cc:clang -d:release --opt:speed --boundchecks:on \
  --passC:-flto=thin --passL:-flto=thin \
  -d:pvmArm64Jit -d:pvmArm64JitOwnerReceipt \
  --passC:-I<source>/native/pvm_jit --passC:-I<source>/tests/performance \
  --nimcache:<cache> --out:<binary> <source>/tests/performance/pvm_sieve.nim
```

Each full build exits 1 in `shoggoth opt --cpu:arm64`, after semantic checking, with this assertion
(the first repetition's final diagnostic is quoted verbatim):

```text
assertions.nim(38)       raiseAssert
Error: unhandled exception: Symbol not found in NIF module: `iir.1000.hanm5t9bb1 [AssertionDefect]
```

All five runs have the same assertion and `iir.1000` prefix; the module suffix differs with each
source directory. The JSON receipt preserves every observed suffix and exit status. The preceding
initial candidate also fails in the same optimizer with `iir.1000.hanuuxgnp`.

The initial emitted C NIF places undeclared `iir.1000` and `iir.1001` references in the two typed
locals inside the `branch == 83` arm of `bindFlatFusion`. This locates an artifact associated with
the failure; it does not establish which pass introduced it or prove a shared cause with earlier
NIM-010 observations.

## Controls, scope and retained evidence

The exact unmodified parent builds both the Pinky and DOOM performance drivers successfully
with the same compiler executable, flags and canonical source path. No candidate timings were
started, and those successful builds are compilation controls, not new workload measurements.
Earlier read-only diagnostics identified source-binding refusals and copied handler identities;
their successful public-call checks do not qualify this uncompiled implementation.

The first scratch variant used `default(array[..., FlatHandler])` and received an ordinary
non-null initialization diagnostic. That invalid initialization was corrected to explicitly
nullable private storage with checked restoration before the five optimizer repetitions. It is
separate from the subsequent compiler assertion.

Raw command manifests, full outputs and generated files remain under ignored
`build/compiler-issues/conditional-handler-composition/` in the experiment checkout; each run's
`output/` retains its full build log and fresh compiler cache. Initial source/build receipts are
under `build/composition/` and `build/windows/composition-*-build.log`.

## Contract review and remaining gates

The pinned [procedure-type contract](https://github.com/nim-lang/nimony/blob/8102b8e3c46bde87b733ecd82e2249cb562e3a8f/doc/language.md#proc-type)
describes noncapturing procedure values and matching calling conventions. The inspected closure,
template, untyped-generic and feature sections do not identify a required opt-in for these
explicitly instantiated noncapturing handlers. That is preliminary contract support, not a
completed standalone classification. A `v2` control and a failing stdlib-only reduction remain
unperformed. An internal assertion still merits tracking even if later reduction finds an
unsupported source construct.

November 15 public Nimony searches for `"Symbol not found"` found issue
[#2961](https://github.com/nim-lang/nimony/issues/2961), concerning stale modules after a stdlib
contract edit, and PRs #2274, #2287 and #1747. No duplicate was confirmed. These fresh source
copies contain no compiler/stdlib edit. Upstream master was observed at
`d2e842d6d8eb8e79c0ad610004f5bbb6ddf3eeca` but was **not built or tested**.

Next: reduce while retaining the optimizer assertion, run the applicable language-feature
controls, check a pristine current upstream build, and investigate the relationship to the
[earlier NIM-010 observations](../nimony-reports-2026-11-14/conditional-handler-value.md).
No upstream issue or comment has been submitted, and no workaround is adopted by this report.
