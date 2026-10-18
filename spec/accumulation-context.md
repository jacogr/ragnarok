# Initial accumulation contexts

## Authorized bounded scope

Implement the initial `partialstate` and `implications` bindings of GP 0.8.0, revision
`07f041dabd073f9018b418e9ee72e79dd2185401`: `accumulation.tex`,
`finalstateaccumulation`, and `pvm_invocations.tex`, `implications`/`accinvocation` initializer `I`.
Source hashes remain recorded in `spec/pins.json`; no authority or vector pins change.

Retain the [invocation bootstrap](accumulation-invocation.md) and its exact service state.
Bind the complete account mapping through its immutable full-state source, plus decoded C(2)
authorization queues, C(7) staging validators and C(12) privilege roles/always-accumulate map.
Require complete chapter extents and coherent chain cardinalities under explicit local ceilings.
Initialize both regular and exceptional contexts to the same immutable `I` value: service ID,
partial state and next free ID, empty transfers and provisions, and absent yield.

The bound adapter must derive state and profile from the original block certificate rather than
accept caller-supplied substitute components. Parent partial state and posterior entropy have
separate provenance. No mutable checkpoint, host call, PVM dispatch, transfer credit or publication
is included, and a complete-state source must not be confused with a light-node partial map.

## Completion tests

Native tests will check all initial fields, exact chapter consumption, missing/malformed chapters,
profile mismatch and exact/one-below resource ceilings. Distinct chapter contents and unrelated
service records must survive extraction and source replacement without mutable aliases. A genuinely
signed block will exercise the bound path. Default/result privacy, nominal API positions, strict
runtime extraction and repeated ARC release will be verified through the existing test groups.

## Next bounded work

Connect initialized contexts to a bounded execution/checkpoint interface only when backed by genuine
PVM outcomes; do not synthesize successful accumulation or publish unexecuted state changes.
