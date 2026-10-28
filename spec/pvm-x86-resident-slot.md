# One resident x86 guest register in closed pure regions

## Bounded trial

The accepted connected pure-loop compiler repeatedly loads/stores guest register
array coordinates. This isolated trial selects one guest coordinate from a bounded
cold scan of the same admitted source facts, scoring explicit reads/writes and
breaking ties by lowest index. At least three static accesses justify selection.
Only that coordinate stays in caller-saved R11 across the closed region; all other
sources/destinations retain the original array accesses. One prologue loads R11;
every external/guard exit, including zero-completed-block returns, publishes it.

Gas/quota remain R9/R10 and the five-word scalar context/visit/endpoint model is
unchanged. No callee-saved register, optional ISA, guest memory operation or native
cache capacity is added. Both original sources are consumed before a destination
write; all register aliases and full64/sign/shift/high-product semantics remain.
Only region publication accepts this builder mode, and every active body must
agree on its coordinate. Ordinary entries reject it before allocating/publishing.
No invocation pointer or mutable guest value survives the native call.

## Qualification gate

An independent scalar region oracle now covers all13 cached coordinates across
one/two blocks, overflow-edge guest values, partial/zero/large gas/source quotas and
full64 zero-block endpoint sentinels:18,720 native context cases, plus the unchanged
1,440 original context cases. A portable-evaluator matrix covers every supported
opcode, saturated source/destination shape, all13 cached coordinates and ten
boundary source seeds:27,560 native complete-register/context/return cases.
Actual native coverage, ordinary-builder refusal and existing opcode/source-prefix/
host/memory/ownership/refused controls remain mandatory.

All native compilation/execution/profiling stays on CI. Keep only complete-state
exact-head same-runner useful paired CPU improvement without material regressions;
otherwise restore this runtime delta while retaining meaningful tests/evidence.
Constructors/cold/reused/core/reference lifecycle stay separate in both process
orders. Simulated branch misses do not establish hardware behavior. No timing
claim before qualification; the earlier counter/immediate trials remain rejected.

A read-only scalar selection tag consumes existing region-record padding (the
record remains72 bytes), allowing the maintained production-loop witness to prove
that both one/two-block cold selectors actually cached guest R0. This adds no
hot-path branch and retains no guest value. Two mismatched-coordinate/builder-mode
publication refusals remain explicit negative controls.
