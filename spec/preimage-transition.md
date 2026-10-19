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

## Implementation and phase contract

`src/state/preimages.nim` exposes `admitPreimages(prior, source, limits)` and
`integratePreimages(state, admitted, slot)`. Admission requires an initialized full-map snapshot and
a genuine preimage-schema `OwnedFrame`. It reapplies item/per-blob/aggregate payload ceilings even
when capture used broader limits, proves descriptor extents and E4 request lengths before copying,
and rejects rather than reorders hostile input. Ordering is numeric service ID followed by raw
lexicographic blob bytes, including proper-prefix and empty-blob ordering. Neither little-endian
service wire bytes, compact blob-length framing nor Blake2b digests determine this order.

For each supplied blob, admission derives its Blake2b-256 identity and exact existing E4-length/hash
request key. Account metadata must be an exact supported record; requests must be exact canonical
histories. Only an existing account with a present empty history is outstanding. Missing accounts,
absent requests and valid nonempty histories are `NotRequested`; malformed present records are
`MalformedState`. Provider refusal is `BackendFailure`, distinct from both protocol rejection and
local `LimitExceeded`. Whole-chapter/state validation outside the touched accounts is not claimed.
No new reserved request-length restriction or alternate representation is introduced.

The immutable acyclic `AdmittedPreimages` retains the exact input owner and prior map. It exposes
copied cardinalities and per-service `ProvisionCount`/`ProvisionBytes` through a nominal
`ProvisionIndex`, plus retained prior/source handles. Returned counters and copied source bytes
cannot alter admission. Per-service provided contributions describe the admitted extrinsic, even
when post-accumulation cancellation makes a blob unnecessary. Existing C(13) is not updated by
this module: report, accumulation and validator statistics still need their own block-level inputs.

Integration snapshots its explicit working store once and rechecks each admitted request against
that post-accumulation map. Deleted accounts, missing requests and valid nonempty histories are
ignored. Still-requested data receives a single Available timestamp at the supplied candidate slot
and the exact raw preimage value. No account metadata, balances, storage items or unrelated chapters
change. A malformed later post-state record refuses the whole operation, including earlier staged
writes. All request/preimage keys, copies and final Merklization complete before the store publishes
the single batch. Empty or entirely disregarded batches retain the same root without hashing.

The input/prior certificate is not an authenticated whole-block outcome. The caller must supply
the correct prior state, actual post-accumulation store and candidate slot in the correct pipeline
phase; distinct snapshots are intentionally permitted. No genuine accumulation/post-state
certificate is invented while execution remains incomplete. Full-map storage semantics remain
separate from future light-node partial maps/proofs.

## Verification evidence

`tests/preimage_transition_fixtures.py` hash-checks the sixteen JSON vectors at the unchanged pinned
revision, serializes their exact raw lookup/request mappings with existing independent test codecs,
and transports upstream verdicts and provided counters to the native suite. Eight previously unused
ordering-vector hashes were added within the existing `stf/preimages` pin group. No gitlink, upstream
revision or dependency source changed, and no upstream generator was executed.

The subsystem schema omits account metadata and other JAM chapters. Test embedding supplies
synthetic zero metadata solely to establish each published account's presence, plus an unrelated
opaque entry. Native tests compare every embedded pre/post entry and independently computed
embedding roots. Those roots are not presented as published complete JAM state roots, and these
account/provision projections do not claim full C(13) publication or complete block execution.

`tests/unit/state/test_preimage_transition.nim` replays all sixteen cases and adds literal raw-byte
versus hash/length-prefix ordering, numeric versus little-endian service ordering, duplicate/prefix
and empty-blob cases, full-width slots/services, exact/one-below local limits and copied-value
isolation. Missing/nonempty/malformed account/request cases remain distinct. Explicit separate
post-state maps test account deletion, request cancellation and fulfilled requests; disregarded
input still contributes to the admitted provision counters. Repeated integration does not overwrite
an already supplied timestamp.

Hash refusal during content/namespace derivation, request/preimage write preparation and final root
construction preserves the original store. Write-count, byte and node ceilings and a later malformed
post-state request also prove all-or-neither publication. Three privacy and two nominal compiler
probes protect owners/results, statistics ordinals and candidate slots; seven strict runtime probes
protect default/refused result extraction. A 1,000-cycle native ARC test covers admission,
publication and duplicate refusal without retaining discarded owners or candidates.

Local combined-tree verification passed after adopting the native restack containing the PVM
initializer:
`make check-inventory format-check check-modules check-unit check-failures check-guards check-python`.
This run compiled 99 source modules, passed 112 native suites and all corpora/runtime/compiler
checks, and passed 404 Python tests with three existing skips. The preimage ARC loop retained
10,944 occupied bytes before and after all 1,000 cycles. Reports are reproducible under
`build/tests/{modules,runtime,failures,guards}/results.json`; the final local log is
`build/preimage-transition/verification.log`. Linux CI verifies pushed revisions separately.
E2E behavior is unchanged and that group was not rerun locally for this state-only feature.

## Next bounded work

Incoming transfer credit before invocation. Full C(13) assembly and block-level preimage publication
follow the complete execution pipeline; PVM integration remains independently developed.


## Shared prepared-value application

[Accumulation provision fulfillment](accumulation-provision-integration.md) reuses the exact
`fnprovide` write kernel. `prepareProvidedPreimages` captures a canonical ordered/unique owned
service/blob frame under the same limits and computes immutable content/request identities once.
Its distinct `PreparedPreimageValues` owner makes no prior-solicitation or extrinsic-statistics claim
and cannot substitute for `AdmittedPreimages`. `integrateProvidedPreimages` rechecks current requests
and publishes the shared atomic batch. Repeated or entirely disregarded application needs no new
hashing. Extrinsic admission still requires prior solicitation with its original error ordering,
retained source/prior views and provided statistics. The existing published-vector replay remains
the regression check for that path.
