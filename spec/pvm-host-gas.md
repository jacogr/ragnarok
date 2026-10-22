# Host gas accounting and the gas host function

## Current unreleased gas contract

Gray Paper commit `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` adopts
unsigned saturating host subtraction. Machine gas remains in[0,2^64); insufficient
credit produces OutOfGas with gas0. Compatibility `GasDeficit` fields are reserved
zero, and nonzero incoming fields are rejected. No negative balance is published.
Host Halt responses are rejected; guest Halt remains a distinct execution exit.
Wide prices/reservations use exact limbs to decide affordability without narrowing.
Costs exceeding the unsigned credit domain produce OutOfGas rather than a local
representation error. Gas-used accounting charges the consumed credit only.

The gas host writes r7 only when funded. The unknown-call dispatcher still writes
WHAT on underfunding because its register update is defined separately. Known
unsupported hosts remain typed local gates. Current witnesses and coordinated
verification are recorded in [the pin upgrade](graypaper-unreleased-upgrade.md).

## Historical release contract and evidence

The following records the superseded release representation; it is not a second
production gas mode.


## Normative scope

This increment implements `Omega_G` (`gas`, identifier 0) and the unknown-call
fallback of the Is-Authorized, Refine and Accumulate dispatchers in GP 0.8.0.
The source is `vendor/graypaper/text/pvm_invocations.tex`, **General Functions** and
its invocation dispatcher equations, with costs from `text/definitions.tex`:
`CgasG = 48`, `Cgasunknown = 1000`. The pinned Gray Paper commit is
`07f041dabd073f9018b418e9ee72e79dd2185401`.

`gasHostResponse` deducts 48 and, if affordable, writes the remaining gas to r7.
Underfunding produces OutOfGas, retains the exact negative balance and leaves all
registers and memory unchanged, as required by the general-functions preamble.
`unknownHostResponse` deducts 1000 and assigns WHAT (`2^64 - 2`) to r7 even when
underfunded: the invocation dispatch equations explicitly define the modified
register file in both outcomes. Other registers and memory remain unchanged.

Both are pure response builders over supplied nonnegative gas, copied registers and
an immutable memory owner. They neither dispatch identifiers nor mutate context.
Callers must distinguish genuinely unknown identifiers from known but unimplemented
host functions; the latter must not silently use the unknown fallback. Applying a
response validates its memory owner through the existing host boundary.

## Exact terminal balances

`MachineInfo` and `HostResponse` now carry a nominal `GasDeficit` alongside
`MachineGas`. The mathematical balance is gas credit minus the deficit. Its canonical
representation has at most one nonzero component:

- Nonnegative balances use the existing full uint64 `gas` field and zero `gasDeficit`.
- Negative terminal balances use zero `gas` and a positive `gasDeficit` of at most
  `2^63`, matching the negative endpoint of `signedgas` in overview equation
  `gasregentry`. Zero has no negative encoding.

This preserves the full existing unsigned input domain without narrowing through
int64, and retains negative host results without wrapping or losing debt through
clamping. Consumers inspecting terminal gas must read both components. Gas-used
aggregation and invocation policy remain separate work and require checked arithmetic.
The overview defines a narrower positive ceiling for `signedgas` than for input
`gas`. This adapter retains the established full uint64 nonnegative input contract
and exact arithmetic rather than silently narrowing it. Reconciliation of those
formal positive domains remains a specification gate for unrestricted conformance.
The [PR533 adoption note](pvm-gas-domain-clarification.md) now records the already-merged
upstream unsigned-domain/clamped-OutOfGas clarification. Its broader changes are
not adopted by our unchanged 0.8.0 pin; existing deficit witnesses remain intentional.

The fixed host charges compare before subtracting, so both positive and negative
magnitudes are computed without overflow or underflow.

Executable machine capture rejects any deficit. Terminal capture rejects simultaneous
credit/debt and deficits above the signed negative bound with `InvalidGasState`.
`applyHostResponse` accepts negative gas only for OutOfGas; the resulting terminal
snapshot preserves the causing PC, charged flag and posterior registers/memory.
Guest stepping/execution reject attempts to resume negative terminal snapshots as
`InvalidMachine`, including zero-budget execution and replaced Host handles.
Replacing a Halt handle with such a snapshot cannot fabricate successful output.

Guest block affordability semantics are unchanged: an insufficient block charge
returns its original nonnegative snapshot. This increment implements host subtraction,
not a different instruction charging rule or a complete signed arithmetic subsystem.

## Verification and remaining work

Native tests exhaust every underfunded input for the 48- and 1000-gas charges, plus
exact and one-over boundaries, all register values, memory permissions/bytes, full
uint64 funded inputs and independent source ownership. End-to-end dispatch checks
nonzero OutOfGas PCs, continuation through a prepaid suffix and combined block/host
charging exactly once. Invalid balance encodings, debt resumption and forged Halt
output are rejected. Fresh 1,000-cycle ARC evidence covers funded and underfunded
invocation lifetimes. Compiler guards separate credit, raw integers and deficit;
isolated runtime probes reject forbidden success extraction.

Host memory access and signed terminal host results now provide the prerequisites
for a concrete memory-consuming host operation. The next bounded chunk is a specified
`fetch` selector family with checked size-based charging. Other host functions,
complete invocation contexts and gas-used accounting remain open.
