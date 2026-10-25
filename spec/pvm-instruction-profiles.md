# Checked PVM instruction profiles

`make profile-pvm-guests` is an opt-in Linux x86-64 diagnostic. Manual CI
`suite=profile-pvm` selects a separate Ubuntu24.04 runner, installs the exact
Ubuntu Valgrind package `1:3.22.0-0ubuntu3`, and requires `valgrind-3.22.0`.
It never joins ordinary master/full/performance checks or persistent PR labels.
Compiler, protocol, upstream and guest pins remain unchanged.

The maintained source-snapshot guest driver is compiled with ARC, Clang ThinLTO,
release optimization and bounds/assertion contracts. C debug information adds
symbol attribution. A native assertion refusal must succeed before collection.
The pinned interpreted reference prepares the same independently state-checked
inputs as the paired comparison. Each profile executes one Pinky frame under
dynamic and complete-plan pricing, plus sieve100000, indirect calls100000 and memory
fill100000 under complete-plan pricing. Warmed memo profiles add Pinky and memory
fill100000, each with twelve checked warmups followed by one checked collected execution.
All complete CPU/gas/page-state checks remain enabled.

Callgrind collection begins and ends at genuine public `execute_?_*` native
symbols. Missing symbols or zero instruction counts refuse the report; there is
no whole-process fallback. Fixture preparation, full-state comparison and benchmark clock calls
remain outside collection. Invocation entry validation, private caches and final
snapshot publication belong to the public execution call and remain counted. A compiled calibration driver contains selected and
excluded arithmetic: selecting the intended function must collect instructions
without the excluded function; selecting a nonexistent function must collect zero.
Generic process success, a crash or a partial raw profile cannot calibrate it.

Every raw call graph, Valgrind log and self-cost annotation is retained. `Ir`
counts executed native instructions. Conditional/indirect branch counts and
predictor misses are simulation diagnostics. Counts are neither CPU-cycle costs
nor timing predictions; all instrumented clocks are discarded for conclusions.
Paired uninstrumented CI remains the authority for speed claims. The original five cells use one invocation and include cold invocation-owned
caches. The two memo cells retain only the final invocation after twelve warmups.

Source membership, frozen snapshot bytes, compiler command, executable, fixture
and preparation identities accompany successful evidence. Changed bytes, failed
full-state checks, invalid counters or annotation failures retain only partial
JSON and raw diagnostics after retiring old success. CI uploads diagnostics and
the captured generated C subset, never binaries, full snapshots, object files,
compiler executables or dependency checkouts. Artifacts expire after30days.

This diagnostic changes no production semantics or representation. Documented M1
framing completion does not imply full state serialization or whole-block/JAM parity.


## Linux qualification, 2026-10-24

[CI40108049548](https://github.com/jacogr/ragnarok/actions/runs/40108049548)
passes selected-scope and absent-scope calibration, the checked native assertion
refusal, all three full-state guest profiles, annotations and frozen identity
checks. This measures tool/runtime head `1f836706` above the qualified register
expansion; publication adds only this contract evidence. The exact command,
source/compiler/input/binary identities and raw call graphs remain in the CI
artifact and `build/pvm12/ci-40108049548/`.

| Guest | Pricing | Native instructions |
| --- | --- | ---: |
| Pinky one frame | Dynamic | 7,450,778,277 |
| Pinky one frame | Complete plan | 7,071,091,949 |
| Sieve100000 | Complete plan | 212,964,058 |

The planned Pinky self-cost annotation attributes64.69% to the inlined execution
body,11.78% to writer scalar loads,7.86% to scalar instruction dispatch,7.84%
to writer stores and2.62% to memory-owner destruction. These identify the next
investigation; instruction percentages are not CPU-time percentages. The parser
accepts Callgrind's omitted trailing zero costs only with matching header/footer
totals. Actual Linux ThinLTO retains public execution symbols while inlining the
private loop, so collection deliberately uses the public execution boundary.

Local verification passes52 focused Python checks, workflow YAML parsing,
verification inventory and the compiled C calibration positive process. Linux
CI supplies the real instrumented calibration and native full-state evidence.


## Generated source attribution, 2026-10-24

The same opt-in diagnostic retains the guest compiler's generated C at its exact
recorded repository-relative paths under `generated-source/`. A separate manifest
records every captured file's byte length and SHA-256. Original and copied bytes
must remain identical through all profile runs. Empty captures, escaping symlinks,
missing files or later byte changes refuse a completed report.

Each selected uncompressed `execute_*` function must map to a captured file.
The profiler retains its existing function summary, then requests source annotation
for those execution files from inside the captured source root. Relative DWARF
paths therefore resolve against the retained copy, without relying on the original
compiler cache. Success requires a real annotated-source section for every selected
file; a function summary alone is insufficient. The per-profile JSON records the
selected files and source-annotation log. These logs attribute inlined native work
to generated C lines, not directly to Nim statements or CPU time.

After downloading the artifact, the generated source tree and raw Callgrind file
can reproduce attribution independently of the CI workspace: run annotation from
`generated-source/`, supplying the absolute profile filename and the recorded
`source_files` as positional source arguments. Existing collection scope, native
assertion controls, input/reference checks, toolchain flags and discarded-clock
policy remain unchanged. This improves attribution and makes no runtime speed claim.


[CI40125948163](https://github.com/jacogr/ragnarok/actions/runs/40125948163)
qualifies tool head `2666c5f1` above the fallthrough-class runtime in PR1535. The
selected/absent-scope and assertion controls, three complete-state profiles,
source-file bindings and captured-root annotations pass. All24 downloaded C files
match their recorded byte lengths and SHA-256. The three source logs contain real
user-annotated execution sections; their sizes are222,384/169,531/167,025 bytes.

The profiled runtime counts are6,165,875,878 instructions for dynamic Pinky,
5,646,231,310 for planned Pinky, and186,299,926 for planned sieve100000. This tool
change leaves production code and guest collection commands unchanged. Nine focused
Python guards cover source copying/stability, path exclusion, exact file binding,
real source sections and stale-manifest retirement; workflow syntax and inventory
checks pass. Publication adds only this evidence record to the measured tool.

## Long call/return and memory coverage, 2026-10-25

The fixed profile matrix also includes planned indirect calls100000 and planned
memory fill100000, using the same maintained preparer and independently checked
input/expected-state owners as paired/reference timing. These short long-loop
profiles expose their larger remaining interpreted-reference gaps without expanding
the native collection scope, changing compiler flags or treating instrumented
clocks as timings. The previous three profiles remain unchanged; all five require
scope/assertion controls, complete CPU/gas/page-state checks, captured generated C,
checksums and real source annotations. This extends the existing profiler review
unit; it introduces no guest runtime or benchmark timing change.


[CI40133617980](https://github.com/jacogr/ragnarok/actions/runs/40133617980)
qualifies all five profiles on the terminal-predicate stack. Scope-selected,
scope-absent and native assertion controls pass, all five complete CPU/gas/page-
state checks pass, and all24 captured generated C files match their lengths and
SHA-256. Every profile has a real user-annotated execution section. The guest
binary is byte-identical to CI40131669246 and its original three counter sets
match exactly, confirming this coverage extension changes no guest runtime.

Planned indirect calls100000 execute430,868,974 native instructions: writer loads
25.37%, memoryMutation16.11% and writer stores12.63%. Planned memory fill100000
executes199,920,934: execute62.34%, writer stores14.63%, memoryMutation9.91% and
writer loads6.26%. These are scoped diagnostic counts, with instrumented clocks
discarded. The larger call/return reference gap therefore includes substantial
scalar-memory work; it must not be attributed solely to jump dispatch.


## Native instruction attribution, 2026-10-25

Generated source-line zero is unassigned debug information, not the final C line
or proof of a particular operation. A substantial planned Pinky execute self-cost
has this attribution, so the opt-in profiler retains an additional instruction-
granularity planned Pinky invocation and textual x86-64 ELF disassembly. The raw
Callgrind positions use its documented `--dump-instr=yes` mode; source attribution
for the existing five profiles remains unchanged. See the
[Callgrind manual](https://valgrind.org/docs/manual/cl-manual.html).

The additional invocation uses the same guest binary, input/reference files,
selected execution scope, one-sample setting and full-state driver checks. Its
instruction total must exactly match the ordinary planned Pinky profile. Required
instruction/line position columns, selected function identity, real native opcode
rows, ELF architecture, binary/disassembly hashes and native assertion/scope controls
prevent generic or unrelated output from certifying attribution. The retained raw
positions, symbol log and disassembly support address inspection; no source line
is guessed for unassigned costs and no instrumented clock becomes a timing.
Only text and raw profiles are archived, with no binary or dependency checkout.

Python guards cover missing/duplicate positions, wrong scope/counts/architecture,
failed or empty disassembly, and stale-code-artifact retirement. Linux CI must
qualify the added machine trace and every existing state/source profile before
this evidence is considered complete. This extends the existing profiler review
unit without changing guest source, build flags, pins, preparation or M1 scope;
full-JAM parity remains open.


[CI40140452445](https://github.com/jacogr/ragnarok/actions/runs/40140452445)
qualifies the native-attribution extension on the decoded-destination stack. All
five complete-state profiles, source sections and24 captured C hashes pass, as
do scope-selected/absent and native assertion controls. The guest binary is
byte-identical to CI40135301299; all five Ir totals match exactly. Minimal's
simulated conditional-miss count differs by one, with other event counts unchanged;
no timing inference is drawn from that variation.

The extra planned Pinky invocation passes full-state checks and records exactly
5,185,810,826 instructions, matching its ordinary profile. It contains native
instruction/line positions and a selected execution symbol; the retained GNU
objdump text contains x86-64 ELF execution instructions. The disassembly SHA-256
is`a2d47d17331930a3869329c1fd2b1b10d1732942a1dae2dd51baa297d0db84de`.
Both traces bind to guest binary SHA-256
`50e782cf8535289a9f6233398716c2d9c585b2b6af4b3a0a10b3e3d51645e806`.
These are diagnostic counters and native text, not new performance timings.


## Warmed memo collection, 2026-10-25

The seven-cell matrix keeps the original five guest commands unchanged and adds
Pinky and memory fill100000 under memo pricing. Each memo cell executes thirteen times
through the existing maintained driver; all complete states must pass. Callgrind
`--zero-before` receives each exact native execution symbol discovered by `nm`,
while collection retains its existing wildcard scope. Entry reset means the final dump
retains only the thirteenth invocation. Public execution validation and publication
remain inside scope; fixture preparation and full-state checks remain outside.
See the [Callgrind manual](https://valgrind.org/docs/manual/cl-manual.html).

The compiled calibration now checks single, repeated and reset execution. Two
identical selected calls must collect exactly twice the single-call instructions;
entry reset must retain exactly the single-call total. Every run still requires
successful classified process output, a complete positive profile and the selected
function without excluded work. Missing reset support, partial counters or any
ratio mismatch refuse a completed report. Every raw guest call graph must independently contain exactly one incoming selected
execution call; retaining thirteen calls refuses the report even if calibration passes.
Each guest cell records its warmup, observed entry and collected-execution counts; memo output parsing requires all thirteen full-state results.

This extends the existing diagnostic owner without changing interpreter source,
guest driver, toolchain flags or timing workloads. Linux qualification must pass
all five controls, seven state/source profiles and the existing native trace.
Instrumented clocks remain discarded, and instruction changes alone are not speed
claims. Comparing the original five counts and guest binary identity against the
previous profile checks that this collection change leaves their work unchanged.


The first Linux extension run40162051126 preserved the exact guest binary and all
five original Ir totals, but its wildcard reset retained thirteen memo entries.
Those memo aggregates are refused as final-only evidence. Calibration now combines
wildcard collection with exact-name reset, and actual guest entry counts independently
require one. This observed failure is a regression guard; no memo per-invocation
counts or speed claims are derived from that run.
