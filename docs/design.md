# Ragnarök design

**Language:** Nimony 0.6.3 (pinned nightly), ARC. **Target:** native Linux. **State:** protocol foundation;
full JAM execution, the complete state-transition pipeline and validator operation remain future work.

Protocol target: Gray Paper 0.8.0; the Bandersnatch draft-text/reference discrepancy remains an explicit
[parity gate](../spec/graypaper-0.8.0.md).

## Module design

Read the relevant module page before architectural changes. This overview holds cross-module
boundaries; it is not a running list of feature increments.

| Module | Design |
| --- | --- |
| Application entry and services | [Application design](design/app.md) |
| Codecs and ownership | [Codec design](design/codec.md) |
| Cryptographic primitives | [Crypto design](design/crypto.md) |
| PVM | [PVM design](design/pvm.md) |
| QUIC networking | [Networking design](design/quic.md) |
| RPC and chain context | [RPC design](design/rpc.md) |
| State storage and transitions | [State design](design/state.md) |
| Telemetry | [Telemetry design](design/telemetry.md) |

[Implementation scope](design/scope.md) records milestone coverage and remaining boundaries.
Feature contracts, normative interpretations, current limitations and next bounded work belong
in the corresponding `spec/<feature>.md`, not this index or an unrelated module's page.

## Shared boundaries

Protocol logic remains native Nim. Private acyclic ARC owners retain immutable snapshots;
borrowed operations have explicit lifetimes, and failed/default results expose no success payload.
Full and light modes retain separate storage contracts; see [state design](design/state.md).

Accumulation execution hands an opaque finalized successor to state-owned block composition
and publication. Original block authority travels with that immutable owner; callers cannot
substitute detached maps or headers. See [the successor boundary](../spec/pvm-state-successor.md).

All upstream sources are pinned submodules. Project-owned bridges contain primitive/transport
integration, not hidden JAM codecs, PVM or state logic. Native dependency sources remain pristine.
