# Feature contracts and pins

[Project overview](../README.md) · [Design](../docs/design.md) ·
[Implementation scope](../docs/design/scope.md)

This directory records feature scope, protocol interpretations, pinned references, completion
checks, observed evidence and remaining gates. The protocol target is Gray Paper 0.8.0;
start with the [migration audit](graypaper-0.8.0.md) for compatibility and open questions.
General development and architecture guides live in [`docs/`](../docs/README.md).

## Finding a contract

Contracts are named after their feature. Related work shares filename prefixes rather than
subdirectories; these entry points lead into the detailed records.

| Area | Entry points and related records |
| --- | --- |
| Codecs and snapshots | [Codec](codec.md), [owned snapshots](owned-snapshots.md), [block](block.md), [work package](work-package.md) |
| Cryptography | [Primitives](crypto.md), [Bandersnatch](bandersnatch.md), [signing domains](signing-domains.md) |
| State | [Layout](state-layout.md), [store](state-store.md), [composition](state-composition.md); `state-*` and `*-transition.md` records |
| Accumulation | [Driver](accumulation-driver.md), [execution](accumulation-execution.md), [complete batch](accumulation-complete-batch.md); `accumulation-*` records |
| PVM | [Program](pvm-program.md), [machine](pvm-machine.md), [execution](pvm-execution.md); `pvm-*` records |
| Application | [Application](application.md), [chain](application-chain.md), [candidate](application-candidate.md); `application-*` records |
| Optional services | [RPC](rpc.md), [telemetry](telemetry.md), [UI](ui.md), [browser](ui-browser.md) |
| Interpretation gates | [State clarifications](state-clarifications.md), [request namespace](request-namespace.md) |

## Source and tool identities

[`pins.json`](pins.json) records protocol and vector identities. Specialized files include
[crypto](crypto-pins.json), [Bandersnatch](bandersnatch-pins.json),
[QUIC proof](quic-proof-pins.json) and [PolkaVM cross-check](polkavm-pins.json) pins.
The active compiler and formatter are pinned in [`toolchain.json`](toolchain.json), the browser
backend in [`web-toolchain.json`](web-toolchain.json), and UI tools in [`ui-tools.json`](ui-tools.json).
Other JSON records preserve focused adoption evidence.

Upstream Git revisions live in [`vendor/`](../vendor/README.md); local fixture provenance is
explained in [`vectors/`](../vectors/README.md) and [`tests/fixtures/`](../tests/fixtures/README.md).
Passing a contract's checks establishes its recorded scope, not complete JAM conformance.
