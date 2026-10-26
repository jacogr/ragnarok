# Comparative interpreter diagnosis

Current CI: historical experiment workflow choices described below were retired in favor of
regular PVM/DOOM interpreted monitoring. Make diagnostics and historical measured evidence
remain unchanged; see [the current monitoring contract](pvm-ci-performance.md).

This bounded investigation starts at merged master
`98165f471684c217a6d959c1c021fd34d568ef54`, after the six accepted PVM layers.
It changes no interpreter, compiler flags, dependency pins, fixture or maintained driver.
The goal is an evidence-backed cost breakdown and one proposed experiment, without
implementing that experiment or pursuing a PR count.

`make diagnose-pvm-interpreters` provisions the established checked ARC/Clang ThinLTO
native driver and the pinned release Rust reference. The manual `profile-pvm` suite's
`pvm_diagnosis` checkbox selects this investigation on one Linux CI runner. It defaults
false; existing profiling and ordinary jobs retain their behavior.

The bounded cases are one initialized Pinky frame, memory fill at 100000 and indirect
calls at 100000. The original preparer supplies the same input and complete expected
CPU/gas/register/page states. Assertions are tested in both executables. Uninstrumented
thirteen-sample observations run in both process orders, preserving cold sample zero,
all warmed observations and native gas-plan/memo preparation records. Binary hashes,
source membership, original source/fixture bytes and generated snapshot identities are
checked around collection. No fixture is compiled or altered.

Callgrind 3.22.0 selected/absent/repeated/complete-return calibration is reused. Native
execution selects its existing `execute` symbols. The reference selects the existing
non-inlined `InterpretedInstance::run_impl` symbols with demangling disabled, verified
against each executable's native symbol table. Both include their execution descendants;
the reference's small public `RawInstance::run` wrapper lies outside that scope. No
upstream patch, private runtime hook or whole-process fallback is used. Raw native
positions, all numbered return dumps and ELF disassembly are retained.

Pinky reference initialization is one separately retained interpreter invocation before
the thirteen checked frames; its costs must not be labeled as frame execution. Every
return part requires matching complete header/footer counters and one selected incoming
entry. The termination dump must be empty. Planned execution collects one frame; memo
and reference retain frame zero and frame twelve. Memo reuses its gas memo between
executions. The reference driver creates a fresh public instance for each execution,
so process warming does not imply retained per-instance decoded handlers. These are
the maintained benchmark contracts, not identical internal cache policies.

Function instruction shares exclude inclusive call-edge costs and reconcile exactly
to each raw instruction total. They are not CPU-time shares. `execute` includes inlined
operations, and reference handlers may also include inlined memory/arithmetic work;
function names alone cannot assign all work to dispatch. Simulated branch counts are
diagnostic rather than hardware measurements. Instrumented clocks are discarded.

Local validation covers inclusive-cost double counting, missing selected entries,
fourteen-return initializer framing and partial warmup/header/footer refusals. Linux
CI must establish real scope/return counts, checked outcomes and native evidence before
any comparative result is claimed. The final diagnosis will document residual scope
differences and distinguish a proposed experiment from an established speedup.

## CI evidence

[CI40167704027](https://github.com/jacogr/ragnarok/actions/runs/40167704027)
passed at diagnostic commit `342a8e4ac25e7989dfe0e9b7ff1647cf2ea4d4d4` on an
AMD EPYC 9V74. Production source, maintained drivers and pins equal the merged baseline.
The six calibration/assertion controls passed. All 82 complete function-return parts,
including the separately retained reference initializer, have matching counters and
empty termination dumps. The fifteen selected profile records each contain one selected
invocation. Offline review independently rechecks their raw hashes, incoming calls and
exact reconciliation of function self costs to complete instruction totals.

The `pvm-instructions-1` artifact retains the raw parts, native disassembly, symbol tables,
source/image identities, all sample logs and the structured `results.json`. The native
image SHA-256 is `960ebf6c876667e389a2d8a953ef260f2cc34dc122058f77081cd630608d5cad`;
the reference is `a0c159c9c12b3e250d96a9e6fdcc28d5375bde056dc8c6999c31dab283aa0c04`.
The same images supply uninstrumented timing and instrumented execution evidence.

The following CPU times are the twelve warmed-sample medians in each of the two
opposite process orders. Sample zero remains in the artifact. These are observations
on this runner, not changes relative to an older job or a portable ratio.

| Guest | Planned CPU ms, orders 0 / 1 | Memo CPU ms, orders 0 / 1 | Reference CPU ms, orders 0 / 1 | Planned/reference |
| --- | ---: | ---: | ---: | ---: |
| Pinky | 315.064 / 323.185 | 327.588 / 337.280 | 104.156 / 105.286 | 3.02 / 3.07 |
| Memory fill | 9.562 / 9.486 | 10.349 / 10.528 | 3.861 / 3.847 | 2.48 / 2.47 |
| Indirect calls | 20.499 / 20.516 | 20.433 / 20.430 | 6.235 / 6.300 | 3.29 / 3.26 |

All eighteen uninstrumented processes pass thirteen complete checked executions. The
instrumented processes additionally pass 81 checked frame/loop executions. Neither
reference preparation nor Pinky initialization is included in the following counts.

| Guest | Planned instructions | Warm memo instructions | Warm reference instructions | Planned/reference |
| --- | ---: | ---: | ---: | ---: |
| Pinky | 5,048,924,258 | 5,447,339,034 | 986,588,321 | 5.12 |
| Memory fill | 194,622,517 | 203,041,933 | 39,524,323 | 4.92 |
| Indirect calls | 421,594,943 | 433,101,429 | 80,067,520 | 5.27 |

Reference cold/warm totals differ by less than 0.01% in all cases. Memo's warmed Pinky
instruction excess over planned is 7.89%; `cachedSecondaryCharge` alone costs
262,368,385 instructions (4.82% of memo). That is a real secondary issue, but removing
it would address only a small part of the much larger reference gap. Memo indirect
calls are slightly faster despite executing more instructions, another reason not to
treat counters as timing predictions.

Preparation remains separate: Pinky planned gas preparation costs 2.345–2.363 ms CPU,
against approximately 315–323 ms execution. Memo initialization is 0.006–0.012 ms and
prices 801 of 1567 source blocks; its remaining lazy work is inside the cold execution.
These records describe gas-policy preparation, not complete program/instance setup.
Reference module and instance preparation is outside its execution clocks but is not
separately timed by the maintained driver; no complete setup-cost comparison is claimed.

## Cost breakdown and interpretation

| Guest | Native executor self | Native load/store helpers | Native memory mutation | Reference loop self | Reference memory-handler self |
| --- | ---: | ---: | ---: | ---: | ---: |
| Pinky | 56.39% | 26.43% | 11.01% | 25.36% | 27.10% |
| Memory fill | 64.09% | 21.46% | 10.18% | 26.57% | 24.80% |
| Indirect calls | 40.25% | 38.84% | 16.46% | 19.23% | 42.22% |

These are native instruction shares, not elapsed-time percentages. The native executor
includes inlined arithmetic, gas, cache, admission and exit work; calling all of it
dispatch would be incorrect. Reference handlers include their own inlined work, so
the groups are useful boundaries, not perfectly equivalent source-level operations.

Two differences stand out:

* The native named memory paths execute 1,890,539,745 Pinky instructions, against
  267,346,564 in reference memory handlers: about seven times the instruction work.
  Sparse immutable chunks, scalar permission preflight and staged copy-on-write have
  different obligations from the reference's contiguous `StandardMemory` regions.
  Their cost cannot all be labeled redundant or removed by weakening semantics.
* The reference's existing decoded handler stream does substantially less general
  per-instruction work. Pinky reference executes 36,570,083 indirect branches against
  20,635,999 planned native branches, while still running much faster. Its conditional
  branch count is 111,495,209 against 977,209,865. The simulated indirect misprediction
  counts are also higher in the reference. This does not measure actual CPU prediction,
  but it contradicts a simple explanation that fewer indirect branches are the main
  missing optimization. No hardware-counter or IPC claim is made.

Cold instruction decoding, chunk cloning and allocation do not dominate these profiles.
For example native planned Pinky `decodeInstructionMiss` self is 0.11%; memory fill's
`cloneWriterChunk` self is 0.01%. Self shares exclude descendant work; these figures
must not be read as inclusive allocation/preparation budgets. Earlier rejected page
directory/MRU/private-chunk experiments therefore remain rejected rather than being
revived solely because memory paths are expensive.

The conclusion is a broad execution-work gap, not a missing small predicate change.
The historical 2.24x timing ratio came from another runner/build context; this fresh
same-run comparison establishes approximately 3x Pinky on this runner, not a regression
between those jobs. Small experiments cannot credibly promise to close the whole gap.

## One proposed experiment: specialize checked byte memory access

Prototype one compile-time-width byte load/store path through the existing scalar
memory helpers. Keep the sparse snapshot representation, ownership, permissions,
protected-prefix/final-address rules, fault ordering, complete preflight and atomic
publication. Keep other widths on the existing generic path. Do not change fixtures,
gas, compiler checks, flags or pins, or introduce a decoded IR/JIT.

The hypothesis is specific: a byte access should not carry a runtime width parameter,
width-membership test, page/chunk-crossing decision and generic scalar assembly through
each layer when its opcode already fixes the width. The retained native `load_1`
assembly confirms a runtime width test (`cmp $0x8,%dl` and `bt` against `0x116`) and
general span logic. The reference monomorphizes memory operations by scalar type.
The existing compiler did not specialize this large generic helper across its caller.
Constant-width specialization may let it erase irrelevant work without relaxing a check.

Memory fill provides a bounded initial witness: the reference byte load/store handlers
cost approximately 9.80 million instructions; native load/store helpers cost 41.76
million, plus 19.81 million in memory mutation. This identifies a real region to inspect,
without assuming all of the difference is recoverable. This differs from dropped #1561
(opcode classification only) and rejected decoded-width metadata (still a runtime width).

Before timing, require generated code to demonstrate removal of dynamic-width and
impossible cross-span work on the byte path, while preserving the boundary/fault/COW
tests. Then use the existing canonical paired CI comparison with identical-image
controls and both process orders. The acceptance gate is at least 10% lower memory-fill
CPU time and a repeatable Pinky gain above the control variation, with no reproducible
regression above 2% on indirect calls or the existing host/cross-page controls. Repeat
once if warranted; stop if the code-generation premise or timing gate fails. No sequence
of follow-up variants is authorized by this diagnosis.

Even success would address one contributor, not establish parity with the reference.
This experiment is proposed only; no runtime prototype or new performance claim has
been implemented as part of the investigation.

## Byte specialization experiment: rejected

The maintainer authorized the single proposed experiment with the existing gates and
an explicit stop on failure. Prototype `11f79d97` is preserved on
`codex/pvm-byte-scalar-access`, against baseline `496b987a`. It specializes the complete
checked byte scalar path behind existing load/store APIs without changing public types,
opcode classification, wider-access semantics, pins or flags. Sparse snapshot ownership,
permission/final-address checks, preflight and first-write chunk cloning remain intact.

Eleven affected local native suites pass, including scalar-writer epochs, memory access
and final-address references, mixed-program execution, host reentry and declared ARC
cycles. A new byte boundary witness covers final-page absence/inaccessibility/read-only/
writable states, cyclic addresses and preserved earlier writes. Checked local ThinLTO
code generation confirms constant-byte preflight, byte payload access and retained
chunk cloning, without the generic width-membership mask in the byte load. This is
code-generation evidence, not a timing claim.

[CI40169755533](https://github.com/jacogr/ragnarok/actions/runs/40169755533)
ran on EPYC 9V74. The baseline/candidate comparison completed all 54 cells and 2808
full-state invocations. Its subsequent identical-source control refused success because
all three same-source image pairs differed in SHA-256. It stopped before control
timings, the reference comparison and post-timing disassembly. This refusal was
preserved; no source-only control or relaxed identity check was substituted.

The completed paired observations were:

| Planned workload | Candidate CPU change, order 0 | Order 1 | Agreed gate |
| --- | ---: | ---: | --- |
| Long memory fill | -6.71% | -7.70% | At least 10% improvement in both orders |
| Pinky | +2.47% | -5.79% | Repeatable gain beyond valid identical-image variation |
| Long indirect calls | +8.68% | +8.22% | No reproducible regression above 2% |

Negative denotes lower observed candidate CPU time. These percentages are provisional:
the failed image control prevents a qualified timing claim. Even the observations fall
short of the primary memory-fill target, Pinky has opposite directions, and indirect
calls show a substantial regression. Dynamic indirect calls similarly change
+8.72/+8.74%; memo changes +7.98/+5.89%. All raw cells remain in the artifact.

**Rejected; experiment stopped.** No qualification rerun, alternative implementation,
optimization PR or merge was made. The prototype and raw evidence remain available,
and the active checkout returned to the diagnostic branch with the unchanged merged
runtime. The new same-source build-identity refusal is recorded as an unresolved
measurement issue, not repaired or used to restart optimization within this experiment.

## Deeper memory and execution attribution

The subsequent authorized investigation resolves that measurement issue and profiles
both engines without changing the runtime or reviving the byte experiment.
[CI40171834535](https://github.com/jacogr/ragnarok/actions/runs/40171834535)
passes at `8f1974e6bbbdf7407a67975114843f885f7ae8ee`. Runtime sources, maintained
drivers and pins still equal the merged baseline. The source profiles add native
Clang `-g`; their native instruction totals are **exactly equal** to the earlier
normal-image totals for all three guests. This validates instruction-count continuity,
not binary equality between diagnostic and normal images or equivalent timing.

`make attribute-pvm-execution` first runs the build-identity stress diagnostic, then
the full identical-source guest/synthetic comparison, then the deep profiles. Select
`pvm_deep_attribution` on the opt-in `profile-pvm` workflow. All instrumented clocks
are discarded. The successful chain retains:

* All three old-path stress pairs have unequal whole-image hashes but equal generated
  C and `.text` hashes. Fresh canonical cache/object/output paths, cleared before
  each build, produce three byte-identical whole-image pairs. Linux ThinLTO promoted
  symbol suffixes/string tables and GNU build IDs explain the metadata mismatch.
  Executable permissions and separate role logs survive staging retirement. The
  whole-image SHA guard remains strict.
* The complete same-image comparison passes all54 cells and2808 full-state
  invocations, both process orders, and every native assertion control. All three
  whole-image pairs match. This is a control qualification, not a speedup claim.
* Six selected execution profiles pass the calibrated scope/return controls and
  full-state checks. The Pinky reference initializer is retained separately.
  Every selected part has one incoming execution entry, matching header/footer
  totals and an empty termination dump. Exclusive costs reconcile exactly; inclusive
  call-edge costs are recorded separately.
* Artifacts retain raw instruction/source positions, native disassembly, generated
  C and pinned reference Rust sources with hashes. Offline replay independently
  verifies all six raw hashes/parser outputs, all captured source hashes and the
  complete comparison summary. Local focused qualification passes24 comparison,
  15 scope/profile and2 deep-parser guards, inventory/YAML checks and an actual
  retained-image assertion-refusal control.

### Memory operations: repeated access work dominates copying

Call-edge counts establish the **same guest memory-operation counts** in both
engines. The native boundary is `memoryMutation`, including scalar load/store and
all descendants; the reference boundary includes all executed raw scalar memory
handlers, including immediate stores and their descendants. Neither contains
whole-process setup. Both include register/address/result work belonging to their
memory handlers; these are comparable operations, not identical internal APIs.

| Guest | Memory operations, each engine | Native inclusive instructions | Reference inclusive instructions | Instructions per operation, native / reference |
| --- | ---: | ---: | ---: | ---: |
| Pinky | 8,066,877 | 1,890,787,923 | 267,346,564 | 234.39 / 33.14 |
| Memory fill | 300,101 | 61,749,123 | 9,927,666 | 205.76 / 33.08 |
| Indirect calls | 1,000,015 | 233,107,178 | 33,809,576 | 233.10 / 33.81 |

The native/reference memory-path difference accounts for40.0% of the complete
Pinky instruction gap,33.4% for memory fill and58.4% for indirect calls. These are
instruction differences, **not attributable CPU-time percentages** or promised
speedups. Even eliminating this difference leaves substantial execution work.

Pinky issues4,934,271 scalar loads and3,132,603 scalar stores. Their inclusive
costs average162.69 and169.85 instructions respectively. The enclosing
`memoryMutation` has555,941,885 exclusive instructions, approximately68.92 per
memory operation, already more than the reference's entire33.14-instruction
average. Representation changes alone therefore cannot remove all of the handler
overhead. Generated C exposes decoded-result guards, opcode/width classification,
register/address selection, result propagation and PC advancement in that wrapper.

| Guest | `cloneWriterChunk` calls | Inclusive instructions, including allocation/copy descendants | Share of complete native instructions |
| --- | ---: | ---: | ---: |
| Pinky | 729 | 242,868 | 0.00481% |
| Memory fill | 200 | 66,635 | 0.03424% |
| Indirect calls | 2 | 814 | 0.00019% |

The existing writer already retains private chunks across repeated stores and seals
them only at publication boundaries. It does not copy an immutable memory image
for every instruction. Making these first-write clones cheaper cannot explain or
close the measured gap. Conversely every successful access still traverses the
generic scalar machinery: owner/width/range checks, two bounded recent-slot hints
or binary search, page presence/permissions, span construction, recent-slot updates,
active-writer selection, chunk selection and tagged-result handling. Stores also
check dirty chunks, even when no cloning is needed.

Generated-C source positions identify583,753,519 Pinky instructions (11.56% of
all native work) in `scalarSpan`, `scalarSlot`, `lowerBound`, `rememberScalarSpan`
and `prepareWriterSpan` combined. Corresponding shares are8.80% for fill and
15.94% for indirect calls. These are exclusive costs attributed to those source
declarations after inlining, rather than extra costs added to the inclusive table.
The payload-source declarations `pageScalar`/`setPageScalar` receive1.71%,0.72%
and3.04%; these declarations also contain width/chunk logic and are not a precise
count of machine load/store instructions.

Source attribution has an explicit limit:26.03% of Pinky's work has no mapped
generated-C declaration, almost entirely DWARF line zero. Every line-zero instruction
address resolves in the retained native disassembly. Of its1,314,062,050
instructions,751,369,394 are `mov`,110,874,407 `lea` and100,840,744 `jmp`.
Line zero is not silently assigned to the nearest source line, copying, bounds
checks or dispatch. The runtime-symbol attribution still includes these costs
completely, so the inclusive memory comparison and cloning result do not depend
on a guessed source mapping.

The reference's pinned `StandardMemory::load_impl`/`store_impl` select a contiguous
resident region, check the typed access range and access the selected slice.
Our execution reaches payloads through sorted sparse page owners and eight512-byte
chunk owners per page. The implementations have different snapshot, sparse-memory
and fault-order obligations; copying the reference model wholesale would not
establish JAM correctness. The actionable difference is the amount of metadata
and general result handling between each decoded memory operation and its bytes.

### Execution work beyond memory

Pinky executes32,055,270 decoded instructions. Generated-C attribution separates
389,036,857 instructions in `cachedInstruction` (7.71% of total native work) from
the5,421,429 runtime self instructions in actual `decodeInstructionMiss` (0.11%).
Cache-hit lookup is expensive even when decoding is rare; more decoded caching
is not automatically the solution. The hit path probes status/address and computes
the cached-entry location before evaluating the instruction.

`evaluateInstruction` source receives1,405,895,606 instructions (27.85%), including
208,253,136 at the register-category branch,160,276,350 at an outcome branch,
119,775,747 at the opcode switch, and64,110,540 each at gas-deficit and decoded
status guards. Those line costs include compiler instructions attributed to each
line, not just the branch itself, and the group contains useful guest arithmetic.
The category-byte lookup itself receives64,110,540 (1.27% of all native work);
replacing that lookup alone cannot plausibly close the gap.

Disassembly also exposes per-instruction decoded-field movement and stack traffic
that line tables do not name. For example `0x1c239..0x1c24a` contains five executed
instructions loading/storing decoded fields; each executes32,055,270 times.
Together these account for160,276,350 instructions,3.17% of the total. They are
already included in the line-zero budget, not added to it. This is observed
machine work, not a claim that these values can all be removed.

### Cache evidence and next bounded direction

The fixed cache simulation uses32-KiB8-way L1 instruction/data caches and an8-MiB
16-way last level, all64-byte lines. Pinky native/reference data-read events are
1,270,607,798 /413,414,588, and data writes480,842,253 /86,862,109. Simulated
L1 data read misses are49,534,205 /5,490,692; last-level data read misses are
19 /0. Thus this simulation points to extra instructions, metadata traffic and
L1 locality costs; it does not demonstrate DRAM bandwidth pressure. Cachegrind
does not model real CPU prefetch, TLBs or out-of-order execution. These are
diagnostic counters, not hardware measurements or timing predictions.

The proposed next experiment is an **execution-owned resolved memory view**,
separate from immutable snapshot storage. Keep the sparse address space and
public snapshot contract, but investigate lazily materialized contiguous private
page buffers with cached resolved page/permission information. Ordinary successful
accesses should reach checked bytes through that view; mapping changes, host exits
and publication must invalidate or seal it explicitly. Preserve protected-prefix,
overflow, cross-page fault precedence, atomic stores and all ownership checks.
This is a change to working representation and access boundaries, rather than
another hint-slot tweak or byte helper. First measure conversion/publication cost
as well as hot access work; sparse or snapshot-heavy cases may lose.

No runtime implementation or performance claim accompanies this diagnosis. A future
prototype needs unchanged full-state fixtures, the existing ownership/fault-order
suites, deterministic counters and paired CI timings across the full matrix.
The previous byte experiment remains rejected. Memory is the first supported
architectural target; execution admission/cache/outcome work remains a separate
large target after that measurement.


### Follow-up execution-owned view: rejected

The authorized [memory-view experiment](pvm-execution-memory-view.md#ci-outcome-rejected)
passes full-state and image controls but misses the planned fill/Pinky gates and
regresses crossing memory by roughly24–35%. It is rejected and stopped, with its
prototype preserved separately and the active runtime restored. These results do
not qualify the proposed view as a solution to the interpreter gap.

### Memory wrapper instruction breakdown and proposed experiment

The next bounded investigation isolates `memoryMutation`'s exclusive cost, with
no runtime change. It reuses the checked Linux x86-64 deep-profile artifacts from
[CI40171834535](https://github.com/jacogr/ragnarok/actions/runs/40171834535)
at `8f1974e6`, rather than comparing new timings. The runtime is the original
merged baseline, not the rejected contiguous-page prototype. The later prototype
profile confirms that this wrapper remained effectively unchanged. Local analysis
of retained counters and disassembly is permitted; all future timing runs remain
on CI.

Join each exclusive Callgrind instruction address to the same image's retained
`native-assembly.log`, including DWARF line-zero addresses. Exclude the cost row
following each `calls=` edge, which is inclusive descendant work, while retaining
the wrapper's own call instruction. Verify the raw SHA and replay the existing
attribution parser before grouping. Every address in `memoryMutation_0_stekif2of1`
resolves inside that symbol, and the grouped costs exactly match its existing
function self total. This is executed native instruction cost per guest memory
instruction, averaged over the observed opcode mix; it is neither a static
instruction count nor a timing estimate.

| Wrapper work | Pinky exclusive instructions | Instructions/access |
| --- | ---: | ---: |
| Opcode classification, width and mode selection | 184,677,954 | 22.893364 |
| Frame setup/teardown and saved state | 137,136,909 | 17.000000 |
| Memory dispatch, call setup/call and result/fault checks | 65,865,929 | 8.164985 |
| Decoded payload and register-slot extraction | 48,401,262 | 6.000000 |
| PC advance and successful result | 48,401,262 | 6.000000 |
| Signed-load extension and its branch | 19,980,102 | 2.476808 |
| Successful-decode guard | 16,133,754 | 2.000000 |
| Register/immediate source reads | 14,276,543 | 1.769773 |
| Effective-address calculation | 11,199,483 | 1.388329 |
| Load destination write and success join | 9,868,542 | 1.223341 |
| Cold writer activation, immutable stores and fault paths | 145 | 0.000018 |
| **Total over8,066,877 accesses** | **555,941,885** | **68.916619** |

The boundaries are semantic groups in this exact disassembly, not guessed costs
from generated-C line labels. Frame/saved state covers `0x18380..0x1838d`,
`0x18397..0x1839c` and `0x1851a..0x18528`; the success guard is
`0x1838e..0x18396`, and payload/slot extraction is `0x1839d..0x183b5`.
Classification/width/mode covers `0x183b6..0x18432` and
`0x184aa..0x184da`, excluding source reads at `0x18403`/`0x18409`/
`0x184ce` and address addition at `0x18430`. The remaining source read is
`0x184a5`. Dispatch/status covers `0x18433..0x1846e` and
`0x184e0..0x18506`; signed extension covers `0x1846f..0x1849d`,
and the destination/join `0x1849e..0x184a4`. The address group also includes
`0x184db`/`0x184dd`; PC/success is `0x18507..0x18519`.
All remaining executed wrapper addresses, from `0x18529` onward, are cold paths.
These ranges partition the wrapper's executed addresses without double counting.

The same partition reconciles the fill wrapper's19,806,946 instructions over
300,101 accesses (66.000933/access) and the indirect-call wrapper's69,401,119
over1,000,015 accesses (69.400078/access). Classification/width/mode costs
20.667172 and23.599961/access respectively; frame/saved state is exactly17
in both. The Pinky mix is4,934,271 loads and3,132,606 stores, including the
three initial immutable stores before writer activation.

The largest supported avoidable work is repeated interpretation of an already
known opcode. Load membership uses an eight-instruction bitset sequence at
`0x183b6..0x183d2` on every access. Loads then select the opcode family in four
instructions and compute the width exponent through six instructions implementing
signed division by two (`0x183e4..0x183f1`), despite the admitted index being
nonnegative. Those six instructions alone contribute29,605,626 instructions,
3.670023/access across the mixed workload. Further branches select absolute or
indirect addressing and store families; shifts rebuild the width at runtime.
These observations identify redundant decoding work, not23 instructions that can
all disappear: the replacement must still select width, signedness and operands.

Two tempting alternatives are outside the proposed experiment. The compiler
already sinks the source-register read into the store path, so moving the
unconditional `stored` initializer in Nim would not remove a load-path read.
Conversely the emitted immediate-Y read at `0x18409` still runs for all stores,
although ordinary register stores overwrite it; this costs0.381444/access on
Pinky's3,077,060 register stores. That is real but small. The17-instruction frame
budget is also real, but inlining is a separate hypothesis with caller-size and
register-pressure costs; it is not counted as a guaranteed saving here.

**One proposed experiment: a compile-time opcode descriptor for memory operands.**
Use one immutable256-entry `uint16` table, indexed by the byte opcode after the
existing successful-decode and execution-category admission. Each entry encodes
the byte width, load/signed flags, address-base choice and immediate/register store
source. Decode those fields in the existing private wrapper instead of testing
opcode sets/ranges and recomputing widths. This is fixed opcode metadata, not a
new per-program decoded cache or intermediate representation. Keep the public API,
result guard, register-slot ownership, actual address arithmetic, signed extension,
PC update, writer selection and every lower-level memory check unchanged. No
unchecked indexing, assumptions, compiler/check switches or changes to the memory
representation belong in the experiment.

Before measuring, verify all256 descriptor entries against an independent explicit
expected mapping, with exact coverage of all30 admitted memory opcodes and an
invalid descriptor elsewhere. Exercise every width and signed/unsigned load,
absolute/indirect forms, immediate/register stores, saturated register coordinates,
protected/final/cross-page addresses, fault precedence and failure atomicity.
Reuse existing full-state and ownership fixtures rather than duplicating their
implementation. Inspect the final checked ThinLTO assembly to establish that the
bitset and signed-division sequences were actually removed.

The proposed counter gate is at least eight fewer wrapper instructions/access on
Pinky, with lower total execution instructions on all three diagnostic guests.
Eight/access would remove64,535,016 instructions, only1.28% of Pinky's complete
baseline work; even the entire22.89 classification budget is just3.66% of that
work before replacement costs. This cannot close the baseline7.1-times memory-path gap by
itself. Do not infer a timing gain from that ceiling or stack this change onto the
rejected memory view. Only after checked parity, strict image controls and the
counter gate pass should the maintained full paired CI matrix run in both process
orders, with its identical-image control. Qualification requires a repeatable Pinky
timing improvement exceeding that control's variation and no reproducible
regression above2% on fill, indirect calls or host/cross-page controls. Otherwise
stop and report the result. No implementation or new performance claim accompanies
this proposal.

### Follow-up opcode descriptor: rejected

The authorized [opcode-descriptor experiment](pvm-memory-descriptors.md) passes its
counter gate: wrapper68.9166→53.2096 instructions/access on Pinky, with total
native work down2.51% and every other function's exclusive count unchanged.
Nevertheless paired CI fails timing qualification: planned Pinky is2.867% and
0.450% slower, and dynamic crossing controls regress roughly2.9–4.3% in both
orders beyond their small same-image variation. It is rejected and stopped,
with no runtime PR or descriptor follow-up variant. The active runtime remains
the original baseline. The separately requested call-frame experiment must start
from that baseline, without combining the rejected table to rescue its gates.
