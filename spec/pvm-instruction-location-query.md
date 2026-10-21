# Validate instruction locations without decoding operands

## Scope and completion checks

Pinned Gray Paper 0.8.0, immutable program storage and both decode profiles remain
unchanged. Profiling after execution-loop decode reuse still places `instruction`
first. Executable snapshot capture and block-boundary queries decode all operands
only to decide whether a location is a marked in-range instruction.

Add `instructionOpcode(program, address): ProgramResult[byte]` as a guarded scalar
lookup. It must reject absent owners, out-of-range addresses before narrowing and
unmarked operand bytes. Every marked opcode in a captured immutable owner was
already validated by decoding, so no operand reconstruction is needed to return
its byte. Unlike `instructionByte`, this query has no infinite zero suffix and
never accepts an unmarked location. It exports neither program bytes nor a mutable
instruction. The existing complete decoder remains unchanged.

Use the lookup only for location validation in executable snapshot capture and
block-boundary queries. Preserve every error class, raw/JAM interpretation, gas
and ownership check. Verify all opcode bytes, marker positions across bitmap-byte
boundaries, unmarked terminator-valued operands, code end/default/maximal PCs and
input mutation isolation; run focused program/machine/execution consumers and all
reference pairs. Measure fixed-input matched checked binaries before retaining the
optimization. No weaker checks or compiled comparison is in scope.

## Observed evidence

The focused program suite checks every admitted opcode byte and complete-decoder
agreement across explicit marked/unmarked positions spanning five mask bytes,
including terminator-valued operands, code end, UINT64_MAX, both decode profiles
and mutation of the original source bytes. The default owner retains InvalidOwner;
invalid positions retain InvalidInstruction. The raw byte API still accepts operand
locations and the infinite zero suffix.

Selected program/machine/step/execution/host-failure suites pass, with stable
1,000-cycle ARC evidence where declared. All fifteen public interpreted reference
/native pairs, the normal interpreted benchmark, inventory and pinned formatting
pass. No opcode, gas, memory, profile, snapshot-publication or specification pin changes.

Matched fixed-input Apple M1 Max/macOS checked ARC/Clang LTO binaries retain
100 measured samples per workload/variant, three process warmups and reversed
process order halfway through ten pairs. Medians are microseconds:

| Workload | Before | After | Before / after |
| --- | ---: | ---: | ---: |
| Arithmetic, 10,000 iterations | 1,884.83 | 1,455.19 | 1.30× |
| Aligned memory, 1,000 iterations | 520.58 | 469.31 | 1.11× |
| Crossing memory, 1,000 iterations | 674.44 | 633.02 | 1.07× |
| Aligned host/memory, 1,000 iterations | 747.06 | 665.79 | 1.12× |
| Crossing host/memory, 1,000 iterations | 912.10 | 829.56 | 1.10× |

Raw samples, binary and affected program/machine source hashes and load observations
are retained locally under `build/pvm-instruction-location-profile/`. Measurements
have no affinity/frequency isolation; local medians are not exact-head Linux or
whole-client results. Compiled comparisons and full upstream fuzzing remain separate.
