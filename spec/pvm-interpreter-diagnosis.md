# Comparative interpreter diagnosis

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
