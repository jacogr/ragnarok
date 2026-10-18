# Preimage admission and integration

## Authorized bounded scope

Implement GP 0.8.0 `accumulation.tex`, `preimagesareordered`, `fnprovidable` and `fnprovide`,
revision `07f041dabd073f9018b418e9ee72e79dd2185401` (SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`).
Use pinned `davxy/jam-test-vectors` revision `d3c089c9a1d5352ad353626d7a2db8589f137b2a`,
the complete tiny/full `stf/preimages` family. Add hashes for previously unused blobs without
changing the upstream revision or executing upstream generators.

Admit an owned preimage extrinsic only if its (numeric service, raw blob) pairs are strictly ordered
and unique, and each corresponding request is outstanding in the explicitly supplied prior state.
Retain the exact prior map and source owner in a private immutable certificate. Under local work,
copy and byte ceilings, integrate admitted data against a separately supplied post-accumulation
working store: skip services/requests no longer outstanding; otherwise write the raw preimage and
one-slot supplied history. Publish all writes atomically, including backend/resource refusals.

Expose per-service provided-count/byte contributions from the admitted extrinsic, matching the
published subsystem statistics. Complete C(13) assembly also needs report/accumulation statistics
and remains separate; preserve existing statistics chapters here. The explicit slot and prior/post
state selection are caller responsibilities until whole-block execution binds those phases.
Do not treat this API as a light-node partial-state store or execute accumulation/PVM.

## Completion tests

Replay all sixteen published input/verdict/account-state/statistics projections using independently
serialized fixtures. Check ordering by blob bytes rather than hashes or wire framing, duplicate
rejection, empty blobs, full slot/service domains, missing/nonempty/malformed requests and metadata,
post-accumulation deletion/cancellation, retained ownership, repeated ARC release and default/result
privacy. Verify exact/one-below resource limits, hash refusal, late batch/root failure rollback and
preservation of unrelated data. Add native misuse and compiler rejection probes.

## Next bounded work

Incoming transfer credit before invocation. Full C(13) assembly and block-level preimage publication
follow the complete execution pipeline; PVM integration remains independently developed.
