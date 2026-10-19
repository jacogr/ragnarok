# Accumulation machine initialization

Scope: initialize an immutable PVM machine from a PreparedAccumulationInvocation.
Source: Gray Paper 0.8.0, revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
`pvm_invocations.tex` accinvocation (Psi_A's Psi_M call), and `pvm.tex` Standard
Program Initialization (conditions, memlayout, registers).

initializeAccumulationMachine uses the bootstrap's exact service code, compact
E(slot, service, input count) arguments and declared service gas. The caller cannot
substitute code, arguments, entry or gas. Accumulation always starts at PC 5 with
block charging false. Standard register values, page layout, permissions and zero
padding come from the existing initializer. The result retains its exact bootstrap
beside the immutable CPU; either child survives release of the wrapper.

The complete code byte cap is checked against prepared metadata before extracting
an independent code copy. Embedded-program, jump and page limits apply through the
standard initializer before memory materialization. Argument extraction is already
bounded to at most 19 bytes by the bootstrap. Temporary code/page copies remain
bounded by the same explicit local policies; no mutable storage is exported.

Default bootstrap/owner access, malformed envelopes, malformed programs or invalid
entry 5, and local limits produce typed failures without a partial machine. Earlier
bootstrap preparation enforces service code availability/size. Ready empty code is
still an invalid executable envelope. These are machine-preparation verdicts, not
Psi_M/Psi_A panic normalization, charged gas or a completed state transition.

Completion tests use authored JAM envelopes and real service/account/bootstrap
construction. They check fixed PC, exact gas and arguments, all initial registers,
memory permissions, child lifetime, code/argument mutation isolation, short/exact
policies, malformed code and entry, halt/panic/out-of-gas execution of extracted
machines, and repeated ARC release. Guard probes protect private owners/results and
failed/default extraction. Existing initializer tests retain full envelope/layout
boundary coverage. No upstream code or vectors are copied.

This adapter accepts the pure bootstrap and does not create a block certificate.
It preserves uint64 service gas without narrowing; the documented positive gas-domain
gate remains unchanged. Accumulation host dispatch, mutable implications/checkpoints,
execution-result normalization and atomic state publication remain open. The
[fetch assembly adapter](pvm-accumulation-fetch.md) now derives entropy and inputs
from this same machine's bootstrap with explicit configured parameters. Complete
accumulation host dispatch and normalized outcomes remain later work.
