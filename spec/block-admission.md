# Block commitment admission and Safrole binding

Target: Gray Paper **0.8.0**, revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/header.tex` parent hash, extrinsic commitment, strict timeslot and prior-state-root definitions;
`text/serialization.tex` C.2 family encodings. Existing source/vector/dependency pins are unchanged.

## Commitment encoding

`src/crypto/extrinsic_commitment.nim` computes Blake2b-256 over the concatenation of **five**
32-byte hashes in ticket, preimage, guarantee, assurance, dispute order. The fixed outer sequence
has no encoded length. Ticket, assurance and dispute families use their exact canonical C.2 bytes.

Preimages use their canonical variable sequence count followed by E4(service) and B(blob) for each
record: no blob bytes or blob-length discriminator remain inside this projection. Guarantees use
their canonical variable sequence count followed by B(complete canonical report), E4(slot), and
the variable credential sequence; each credential retains E2(validator) and all 64 signature bytes.
Report hashes have no signing domain. Hashing the complete serialized extrinsic directly, omitting
an empty family, using a tree, adding an outer count or using an unsigned report is not equivalent.

A finite byte ceiling independently bounds the original captured extrinsic and the aggregate
projected encodings. Empty preimages can expand the projection, so original wire size alone is
insufficient. Checked counts, multiplication and additions precede projection allocation and
hashing. Defaults/refusals expose only their reason. Backend refusal at any blob, report, family
or final hash exposes no partial root. Allocation exhaustion remains fail-stop.

## Admission and application boundary

`validateBlockCommitments` borrows immutable `OwnedBlock`, complete `OwnedHeader` parent context,
and a retained complete-map `StateStoreSnapshot`, plus explicit frame and parent-header byte limits.
It revalidates the captured block under the caller's C.2 profile; an owner captured under a more
permissive configuration cannot bypass the selected application policy.

- C(11) must be an exact E4 and equal the supplied parent's slot. The child slot must strictly
  increase without wrapping; no wall-clock decision is made here.
- The child's prior-state root must match the retained complete-map commitment, which represents
  the **parent posterior state**, not the prior-root field inside the parent header.
- The child's parent identity must equal B(complete canonical parent header **including its seal**).
- Its extrinsic hash must match the prescribed five-family commitment computed from its own owner.

Only complete success returns an opaque immutable `BoundBlock` retaining the exact revalidated
block, its own decoded header, the supplied parent header and the exact parent snapshot. The parent
header is trusted chain context supplied by the caller; this boundary does not discover ancestry,
validate a genesis anchor or authenticate the parent anew. Private fields and checked accessors
prevent forging a binding or extracting values from default/refused results.

`advanceBlockSafrole` obtains the current store snapshot, requires compatible decoding/Safrole
core, validator, epoch and ticket domains, then performs admission before any Safrole work. It
extracts the admitted block's **own** header and tickets; callers cannot substitute a separately
provided ticket projection. Admission performs no state writes. Any admission or later Safrole
refusal leaves every original entry/root unchanged. Success retains the bound input and the
coordinator's atomic C(4)/C(6)/C(8)/C(9)/C(11) publication. The nested failed coordinator result
preserves its exact stage-specific typed cause, without partial state.

Full-state roots require complete maps. Partial light-node state must use its own verified proof
contract. Posterior disputes offenders are still supplied from a separately validated stage;
non-ticket extrinsic execution, offender-marker validation, wall-clock admission and complete
block execution/import remain outside this bounded increment.

## Evidence and reproduction

The admission suite executes ten unchanged signed tiny blocks: 12, 13, 25, 49 and 100 from each
of `traces/fallback` and `traces/safrole`, paired with the immediately preceding signed header at
vector revision `d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Every consumed source already has a
recorded raw Git-blob SHA-256 pin. Complete verbatim parent mappings reproduce the published roots.
Five complete Safrole chapters match the actual post-state values; other chapters/services remain
unchanged. No full-block post-state-root claim is made before other JAM transitions execute.

Negative cases alter each header commitment, the parent seal and a block's extrinsic owner; they
exercise independent byte ceilings, admission hash refusal, both ordinary verification refusals,
late publication refusal and retained owner lifetimes. Additional boundaries reject missing/short/long
C(11), a different parent slot, a wrong complete-map root, backward slots, divergent chain profiles
and a previously captured owner that exceeds a stricter ticket policy. Exact byte ceilings succeed;
source-buffer mutation cannot change a binding. A scoped 1,000-call success/first-hash-refusal
workload requires identical before/after live Nim allocation occupancy, not a general memory audit. Published trace headers/credentials are
never regenerated to accept changed inputs.

A separate native commitment profile compares independent Python/hashlib answers for empty data,
129 empty preimages (multi-byte count and projection expansion), rich preimages/reports/credentials,
and changes to each family. The pinned full codec extrinsic's known unordered dispute verdicts
remain an explicit rejection case. Its explicitly labelled **authored rich counterpart** sorts only
that fixture's verdict order, as the existing codec oracle does; dependency/published sources are
unchanged and production never sorts or retries malformed input.

Run `make check-modules check-unit check-failures check-guards check-python`; prepared fixtures,
source identities and reports remain under ignored `build/`. Networking code is unchanged.

## Next bounded work

The stacked [disputes transition](disputes-transition.md) derives posterior offender identities/markers
from the block's own disputes and prior C(5), replacing supplied offenders in its composed entry point.
Next: availability assurance validation and assignment updates. Wall-clock policy and complete
non-PVM/PVM execution and block import remain separately scoped work.
