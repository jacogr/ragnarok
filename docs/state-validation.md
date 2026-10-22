# Complete-state serialization validation

Use these adapters for complete serialized state snapshots. Authenticated partial evidence
continues through [global proof reads](state-global-proofs.md); it has no conversion into these
complete-source owners. The [global snapshot](../spec/state-global-snapshot.md),
[manifest](../spec/state-manifest.md) and [checkpoint](../spec/state-validated-checkpoint.md)
contracts define the exact scope and verification.

## Validate a retained complete snapshot

`validateGlobalState(source, profile, limits)` validates all sixteen required global chapters
through existing exact codecs. Provide an initialized `StateStoreSnapshot`, the explicit
`StateProfile` and independent per-chapter/item/aggregate-byte policies. Cached lengths for all
required entries preflight before copying or decoding values. Inspect `GlobalStateError` before
reading `.value`. `MissingChapter` identifies actual absence in the complete source;
`ChapterFailure` retains the chapter and exact codec reason, including malformed values and codec
resource refusals. A top-level `LimitExceeded` is a length-preflight refusal. No failed result
publishes a validated prefix.

Successful `ValidatedGlobalState.globalSource` returns the exact immutable source, including all
unvalidated service rows. `globalChapters` returns copied handles to immutable typed chapters;
replacing caller slots cannot modify the certificate. This owner alone makes no service
serialization claim.

## Match every service row

Call `validateStateManifest(globals, services, limits)` with explicit `StateService` descriptors:
metadata, raw storage keys/values, preimage hash/value pairs and request identities/histories.
The matcher uses existing composition codecs and compares every complete key/value byte with the
source, requiring equal cardinality and unique expected keys. Root equality is insufficient.

`services = []` claims a map with no service rows; it refuses a source containing undeclared
entries. `StateService.captured` is refused as `OpaqueValues`: hashed physical keys do not
establish logical namespace membership. Count/node/value/aggregate/raw-key policies remain
independent. Inspect `StateManifestError` and, only on `CompositionFailure`, `compositionError`.
Current request lengths exclude both reserved E4 prefixes, with no historical fallback.

Success retains the original complete source and fixed service/entry/byte observations.
Temporary recomposition and caller descriptors are released. `manifestSource`, `manifestGlobals`
and `manifestInfo` have guarded result access and preserve immutable ownership.

## Restore an existing checkpoint

`decodeValidatedCheckpoint(bytes, expectedRoot, services, profile, limits)` first calls the
existing complete V1 checkpoint decoder with the independently supplied expected root. It then
runs the same global and complete-manifest validation. Supply all `StateCheckpointLimits` fields:
checkpoint bytes, store restoration, global validation and manifest composition policies.

| Result | Available reason |
| --- | --- |
| `CheckpointFailure` | `checkpointError`: exact format, canonicality, resource, backend or expected-root refusal |
| `GlobalFailure` | `globalFailure`: the original failed global result, with guarded chapter/codec details |
| `ManifestFailure` | `manifestFailure`: the original failed manifest result and guarded composition reason |
| `None` | `value`: complete immutable manifest certificate retaining the newly restored source |

The embedded checkpoint root supplies no independent authority. The adapter has no root-only
fallback, alternative encoding, file I/O or automatic canonical installation. Returned state
survives overwriting/releasing the input buffer and caller descriptors.

These synchronous bounded operations belong outside transport callbacks. Observe the existing
single-threaded snapshot and canonical ARC lease rules when accessing source graphs. Serialization
matching does not validate account/preimage relationships, signatures, state transitions, finality,
Thin VRF or full current-pin JAM parity. Historical release vectors remain historical evidence.
