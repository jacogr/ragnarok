# Qualifying an authenticated current successor

Use this read-only path after the existing candidate producer has returned a successful
`PreparedCurrentChainUpdate`. It preserves the original block/report/execution/composition chain,
physical snapshot identity and full child Parameters. It does not rerun guests, replace a map,
install state, select root trust or infer finality.

Run all operations, handle copies and alias retirement on the stable host before proof enqueue or
after matching collection or joined shutdown. The fixed-address one-slot proof worker keeps its
canonical ARC graph lease through cancellation and Done. Read-only access still retains/drops ARC
aliases and cannot bypass that lease. Existing generic Services `ViewFailure`/`viewError`, service
overload errors and RPV1 transport are unchanged.

## Choose the evidence required by the consumer

| Input and operation | Successful evidence | Explicit policy and work |
| --- | --- | --- |
| Prepared update, `captureCurrentProfile` | `DerivedCurrentProfile`: original update, cardinalities and full Parameters | Prior C9 extent/roster limits; hash-free exact previous-roster decoding |
| Derived profile, `qualifyCurrentGlobals` | `CurrentGlobalSerialization`: all sixteen globals on that update | Global per-chapter/item/aggregate byte limits; cached full preflight; hash-free |
| Qualified globals and full supplied service declarations, `qualifyCurrentState` | `CurrentStateSerialization`: exact complete service matching and compact inventory | Manifest service/map/key limits plus compact fact/descriptor limits; mandatory bounded matching hashes |
| Qualified current state, `reviewCurrentState` | `ReviewedCurrentState`: original state and same-inventory targeted review | Frozen review limits; original full child Parameters choose deposit profile; preparation before content hashing |
| Qualified current state and full supplied declarations, `captureCurrentLogicalState` | `CurrentLogicalState`: original current provenance plus retained supplied raw keys | Independent compact and extra raw-key descriptor/count/byte limits; mandatory complete revalidation |
| Retained logical companion, `copySuppliedServices` | Detached mutable complete service declarations | Whole service/child descriptor/fact/per-value/key/payload budget preflight; hash-free |
| Prepared update, `captureCurrentUpdateCheckpoint` | Original-source checkpoint capsule and copied fixed context | Explicit V1 byte limit; bounded detached export; hash-free serialization |

Inspect each result's error before extracting `.value`, and select nested reason accessors only for
their actual failure stage. Defaults and refusals never mean successful empty inventory, key or
report. Complete-source absence, missing partial witness, malformed value and resource refusal have
different meanings. Partial proof views remain in the separate [proof API](state-global-proofs.md)
and cannot enter this complete-map qualification path.

The four `StateProfile` cardinalities are not a complete chain configuration. Current/core/epoch
values come from the same original child; the previous population comes from its exact C9 bytes,
with no current-population fallback. Keep the full original Parameters where configuration matters.
`reviewCurrentState` selects those internally; callers cannot inject a replacement economic profile.
Undercoverage remains a successful observation rather than a new global funding rule.

`CurrentLogicalState` retains two compact captures: the original current state's inventory and the
new raw-key companion's revalidated inventory. They bind to the exact same physical snapshot but
have different compact owner identities. Do not join same-inventory predicate certificates across
them. The higher original current owner supplies profile/full-Parameters provenance; the companion
supplies original raw storage keys, fixed preimage/request identities and original source payloads.
Copy-out arrays/bytes are detached and mutable; modifying them creates no certificate.

The child's header root names its **prior** state. Use the original successor snapshot commitment
for posterior serialization observations; it is not an independently published posterior golden.
C15/C16 completion is state processing, not chain finality. The checkpoint capsule preserves actual
view finality separately and reports `NoFinality` when the retained view has none. Installation
remains with existing application/PVM APIs that check exact original parent state and full prior
view/Parameters/finality, rather than root equality alone.

## Interpret the available evidence

The [source audit](../spec/state-current-source-audit.md) records fourteen published pre/post maps
from seven exact pinned trace blobs. Their twenty-six metadata rows are 89 bytes, while current
metadata is 105 bytes. Native decoding refuses unmodified release rows; explicit test-only expansion
changes every selected map root. Expanded metadata and opaque hashed keys do not establish an
unchanged complete current-pin corpus or a full logical source manifest.

Independent authored current-schema maps now qualify complete serialization, refusal categories,
service ordering, account audits, whole reviews and lossless raw-key/service reconstruction. The
review corpus has 192 schedule/order cases, including exact whole-report arithmetic refusals.
These are schema/predicate witnesses, not published full valid-state/STF vectors.

The opt-in complete signed current fixtures author canonical C16 before the parent root and block
signatures, rather than repairing a completed map. Their actual ordinary/assured/disputed/ticketed/
epoch successors match supplied declarations. Existing default rollback-sentinel fixtures are
unchanged and still refuse complete typed matching. This is supplied-and-validated inventory;
`PreparedCurrentChainUpdate` does not export a complete producer-owned logical manifest.

See the source contracts for [current globals](../spec/state-current-globals.md),
[current serialization](../spec/state-current-state.md),
[current review](../spec/state-current-review.md),
[raw-key retention](../spec/state-supplied-logical-inventory.md),
[detached reconstruction](../spec/state-supplied-services.md) and
[current-bound logical provenance](../spec/state-current-logical.md).

## Remaining producer contract and parity gates

PVM and state agreed to defer a public delta API until a jointly designed producer contract has a
concrete consumer. Preserving supplied information is complete within the contracts above; execution
propagation is a separate feature. That design must settle:

- Exact original logical/physical parent and prepared-successor provenance, including untouched keys.
- Explicit operation identities and ordering, including absence versus present-empty values.
- Selected regular, exceptional and checkpoint rollback outcomes without replaying guests.
- Service creation/deletion and non-guest composition changes across every namespace.
- Bounded retained event/key/payload storage, immutable ownership and atomic failure.

A touched-key trace or physical before/after map difference cannot recover untouched raw keys or
maintain complete logical provenance. Supplied before/after declarations could prove a narrower
observational relation, but would remain supplied evidence rather than a producer mutation certificate.
No speculative public delta API is introduced here.

Full current-pin STF qualification still needs independent complete current-schema pre/post source
material, actual selected producer integration and the outstanding normative/crypto gates. The
[current Bandersnatch pin record](../spec/bandersnatch-pins.json) preserves release-reference IETF
verification separately from adopted current Thin VRF parity. Conflicting bless allowances retain
`AmbiguousPrivileges` under the [existing integration contract](../spec/pvm-accumulation-integration.md).
No pins, compatibility fallback, RPC root/schema policy or storage API/format are changed. M1 framing
and current request namespace completion do not imply complete state serialization/STF or JAM parity.
