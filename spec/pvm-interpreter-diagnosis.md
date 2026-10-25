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
