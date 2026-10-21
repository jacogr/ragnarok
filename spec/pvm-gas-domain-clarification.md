# Positive gas domains and the already-merged upstream clarification

## Pinned contract and minimal witnesses

Gray Paper 0.8.0 at `07f041dabd073f9018b418e9ee72e79dd2185401` defines
`gas = [0, 2^64)` and `signedgas = [-2^63, 2^63)` in
[overview gasregentry](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/overview.tex#L166-L170).
The interval is half-open under
[notation Numbers](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/notation.tex#L51-L55).
The input to host-aware `Psi_H*` uses `gas`, but its output uses `signedgas` in
[pvm.tex](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L755-L763).

Original trap blob `[0,0,1,0,1]` has a two-unit block charge over five pipeline cycles. With input gas
`2^64-1`, its posterior balance is `2^64-3`; no host callback runs. The core
unsigned executor can represent this, but the host-aware function's declared
signed codomain cannot contain the same result. This is a pinned-text domain
mismatch, independent of any host underflow or implementation cast.

A second original witness uses the pinned general host cost equation
`gas' = gas - g` with `Omega_G` cost48. Input0 yields OutOfGas with balance-48.
Ragnarök currently represents that as credit0/deficit48; it does not wrap or clamp.
That behavior is explicitly covered by [host gas accounting](pvm-host-gas.md).

PolkaVM 0.37.0 at `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` exposes
[`Gas = i64`](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm/src/lib.rs#L151)
and [`RawInstance::set_gas(Gas)`](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm/src/api.rs#L1403).
Positive gas at or above2^63 cannot enter that public API. Reinterpreting it as a
negative i64 would test a different input, not establish parity. PolkaVM's guest
engine does not define the JAM Omega_G host embedding; do not attribute a host
clamping policy to this gas API alone.

## Existing upstream resolution: do not post a duplicate

[Gray Paper PR533](https://github.com/gavofyork/graypaper/pull/533),
“Various host function fixes/improvements”, merged on **2026-07-22** as
`0c0664eb52ba92afd8d21cef96c0e1da506eddfe`; its reviewed head is
`e764b5bcb641808e0d7c8e66791badf856e2464e`. It postdates our June3 release pin.
The reviewed patch removes the `signedgas` definition, changes host-aware output
and host-function gas to the unsigned domain, and uses `max(gas - cost, 0)` for
general host charging. This addresses the formal positive-domain mismatch while
also changing the pinned representation of host out-of-gas balances.

A read-only source check on2026-10-21 at upstream main
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` confirms `signedgas` is absent
from overview/PVM/invocation chapters and general host subtraction remains
saturating. This records that exact source, not an execution result or a pin update.

The PR includes substantially more host changes, including context/signature
rewrites. Its merged status is evidence of upstream disposition, not authorization
to adopt a partial patch or advance any specification/vector pin. Existing negative
balance, invocation gas-used and inner-invocation consumers require coordinated
review before migration. No claim is made that the current PolkaVM gas API
represents the paper's complete unsigned domain after that clarification.

A bounded all-state GitHub search on2026-10-21 found PR533 and related
[PR255](https://github.com/gavofyork/graypaper/pull/255) (historical signed result)
and [PR508](https://github.com/gavofyork/graypaper/pull/508) (the gas model).
Searches were `signedgas`, `gas signed`, `gas unsigned` in the Gray Paper repo,
and `gas i64` in PolkaVM. The latter found an asynchronous refund issue, not this
positive-input representability question. These searches are not exhaustive.
No issue or comment was posted. The local adoption note replaces a duplicate
issue draft because the relevant paper clarification is already merged.

## Completion checks and pending adoption

Add a source-owned public-reference/native pair with the identical trap blob and
full high-bit register sentinels. Compare eight shared input edges from0 through
i64::MAX; separately prove that checked public-API conversions refuse four
upper-half unsigned values. Native checks retain all twelve inputs through both
paper/JAM owners and guest/host-aware entry points, including exact posterior gas,
charged flag, source preservation, zero callbacks and 1,000 ARC release cycles.
The existing negative host balance remains an explicit pre-adoption witness.

This is current-contract verification, not adoption of PR533. Keep all production
code, host arithmetic, pins and unsigned native input contracts unchanged.
Upper-half native-only witnesses must never be described as PolkaVM execution
comparisons. The required full upstream fuzzing job remains separate.

Before adopting a newer paper revision, decide the complete pin/vector scope and
review host OutOfGas clamping, removal/retention of deficit APIs, invocation gas-used
normalization, inner gas accounting, all host-specific costs/signatures and existing
approved exceptions. Keep focused old/new witnesses through that review; a lone
clamp is not a complete migration plan.

## Concrete adoption review cases

| Omega_G input gas | Pinned balance after cost48 | PR533 balance | Exit |
| --- | ---: | ---: | --- |
| 0 | -48 (credit0/deficit48) | 0 | OutOfGas |
| 47 | -1 (credit0/deficit1) | 0 | OutOfGas |
| 48 | 0 | 0 | Continue |
| 49 | 1 | 1 | Continue |

For input0/47 both versions preserve the input registers through the underfunding
branch. The funded gas return register follows the posterior credit. Current native
assertions deliberately cover the pinned column; the PR533 column is a pending
adoption requirement derived from its reviewed equation, not claimed runtime behavior.
Machine/step/output, host gas/fetch/heap, refinement export and inner-machine
consumers currently carry deficit handling and need review together.

## Observed evidence

The public interpreted probe passes all eight representable inputs, full-register
checks, exact posterior gas/PC and all four explicit upper-half conversion refusals.
The native suite passes all twelve inputs through both owners and both execution
entry points, plus the pinned credit0/deficit48 host witness. Its isolated ARC check
records occupied memory192 before/after 1,000 complete release cycles.

The supported Make target passes all sixteen discovered interpreted reference/native
pairs. Eleven runner/summary controls, inventory and final pinned Nim/Rust
format-check pass. Every changed local Markdown target resolves. These are local
macOS results; no new Linux run, compiled backend, complete fuzzing or PR533 runtime
adoption is claimed. Production runtime files and all pins are unchanged.

Raw source/search evidence lives locally in `build/pvm-gas-domain-upstream/` and
`build/pvm-gas-domain-upstream-search.json`; fresh integrated results are retained
under `build/pvm-gas-domain-evidence/`. Reproduce with
`make unit SUITE=pvm_gas_domain_reference` and `make check-pvm-reference`.
