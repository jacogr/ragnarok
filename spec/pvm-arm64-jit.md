# Local ARM64 JIT experiment

## Scope and authority

Draft tracking work based on merged interpreter master
`ac4ba21c1486b24ad8ec8967de3208bf7cb470b1`. GP 0.8.0 and the existing PVM feature contracts
remain authoritative; pinned PolkaVM is a cross-check. This is an optional local experiment,
not a default engine, supported backend, CI requirement or completed compiler.
The October 26 Nimony pin, checked release, ARC and Clang ThinLTO remain unchanged.

## First executable increment

Compile bounded straight-line register operations from genuine sealed handler-stream facts.
Retain block charging, exact source-attempt reservation, budget barriers, source ownership,
checked memory, branches, exceptions, publication and ordered host transitions in the existing
engine. Native fragments receive only the invocation's thirteen-register file for the duration
of a call, never guest addresses, source buffers, callbacks or retained mutable machine state.
Unsupported operations return to the same checked interpreter. Partial source reservations must
use its exact existing barrier path; no native fragment may cross a block header or exit.

Start with simple modular arithmetic/bitwise operations and explicit alias/overflow witnesses.
Executable storage has bounded capacity, explicit ownership and instruction-cache publication.
Only project-generated instruction words may be published. OS refusal leaves execution interpreted.
Apple Silicon requires MAP_JIT and write/execute protection; host policy refusal is a local
availability result. Hardened application entitlement/distribution support is outside this slice.

## Completion evidence required

- Native arithmetic matches the independent register evaluator for aliases and boundary patterns.
- Full CPU/gas/page/permission/source results and ordered host events match the checked engine.
- Exact attempt boundaries, out-of-gas, memory faults, dynamic control and host reentry remain checked.
- Executable storage survives reuse and releases on ownership destruction; admission refusal is tested.
- Record compiler, input and source/image identity. Separate code publication/compilation, cold and
  repeated execution; compare both process orders on one ARM64 host without competing builds.
- Record compiled operation/fragment counts: a passing run with no native execution is not JIT evidence.

No measured performance claim yet. The initial draft preserves the plan and subsequent commits;
remaining implementation, correctness and measurement work must stay visible here.

## Platform reference

Executable publication follows Apple's [JIT guidance](https://developer.apple.com/documentation/apple-silicon/porting-just-in-time-compilers-to-apple-silicon),
including instruction-cache invalidation. Generated arithmetic remains project-owned and reviewed
against the existing GP register semantics, without translating upstream implementation code.
