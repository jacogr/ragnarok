# Capture applied state for chain readers

## Authority and scope

Use GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401` and vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. This adapter changes no protocol equations.
It connects complete immutable state snapshots to the existing structural chain owner.
Execution/finalization remains PVM-owned; state composition/application remains state-owned.

## Contract and completion tests

The [snapshot adapter](../src/chain/genesis.nim) owns capture, retention, and structural
validation. [The provider](../src/chain/provider.nim) owns admission into the selected view.

Test genuinely signed applied accumulation successors, raw-adapter parity of roots, block
identities, every key/value and metadata, detached header input and exact retained map identity.
Verify inherited writable policies, historical views, defaults, malformed/missing/trailing
chapters, invalid ordinal extents, broad source policies, header backend failure, and 1,000
ARC capture/refusal cycles. Run the existing RPC and store consumers. Add strict default-owner
and failed-key extraction probes and nominal coordinate rejection.

## Remaining work

Capture is structural, accepts a caller-supplied header and complete map, and establishes no
signature/execution validity, chain linkage or finality. The caller must privately stage state
application, capture its admitted header, and pass the successful child to the existing chain
provider before replacing live state/view handles. That atomic caller integration is the next
bounded state layer. Persistence and full JAM/STF parity remain open. M1 framing is complete;
full state serialization remains open.

## Observed local verification

`make unit SUITE=chain_state_snapshot` passes on pinned Nimony/ARC with checked
contracts, Clang and LTO. Signed empty, combined incoming/available/lookup/provide,
dispute, ticket and epoch-crossing successors retain exact applied-state identity.
Raw-adapter roots, block hashes, every key/value, service order and cached metadata
agree. Capture hashes only the sealed header once. Mutable branches inherit the
source policy; raw-capture branches retain their original zero-write ceiling.

Missing/empty/extended required chapters, default owners, invalid ordinals,
16,385-entry maps, excessive aggregate values, mismatched times and truncated or
extended headers refuse without hashing. Header backend refusal publishes no
owner. The literal enumeration oracle includes unsorted input, present-empty
values and retained historical ordinals. One thousand capture/refusal cycles
retain 219,088 occupied bytes before and after.

The existing `state_store` and `rpc` suites pass. Three strict runtime extraction
probes and one nominal compiler rejection pass. All 33 targeted verification
and failure-harness tooling tests pass; source-owned inventory and pinned
Nim/Rust formatting pass. Logs are under `build/chain-state-snapshot*`, with
native output under `build/tests/native/selected/`. Exact-head Linux CI and
full JAM/STF parity remain separate evidence.
