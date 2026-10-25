# JAM serialization status

Reviewed 2026-10-25. This is the current scope and evidence index. Historical M1
qualification records describe their original revisions; their old “next” and
“pending” paragraphs are not an active backlog.

## Authority

Production targets unreleased Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`
and vectors `23061ae1f9b51171c01387e7dde0f15794c98e24` (gp-next), as recorded with
source hashes in [pins.json](pins.json). VERSION remains 0.8.0; no new release is
claimed. [The coordinated upgrade](graypaper-unreleased-upgrade.md) records the
adopted changes. No specification, vector, compiler or native dependency pin changes here.

The exact release-to-target diff in `text/serialization.tex` and
`text/merklization.tex` adds explicit Boolean serialization, the destination-supervisor
Boolean in deferred transfers, and supervisor identity/incarnation/protected balance
in account metadata. These changes are implemented. Request admissibility additionally
follows the adopted account/host domain bound. The accepted vector-compatible C12/C13
width interpretation remains explicit; there is no alternate-width fallback or adoption
of a proposed validator-statistics format merely because a newer proposal exists.

## Implemented serialization

| Scope | Current behavior and evidence |
| --- | --- |
| Appendix C.1 | Canonical naturals, E0..E8 integers, Boolean 0/1, tuples through typed codecs, bytes/sequences, optional alternatives and packed bitstrings. Scalar set/dictionary schemas are bounded and canonical; arbitrary child-codec adapters are outside the public API. See [codec coverage](../docs/codec-coverage.md). |
| Appendix C.2 | Work outputs/digests/reports, availability/refinement/work-package records, all five extrinsic families, markers/headers, complete blocks, accumulation operands and tagged input union. Deferred transfers include the strict destination-supervisor Boolean and occupy **154 bytes**. See [C.2 records](c2-records.md). |
| T chapters 1–5 | Authorization pools/queues; recent history, package dictionaries and belt peaks; pending validators/ring root/schedule/tickets; dispute sets. Exact typed capture, canonicality and bounded ownership are implemented. |
| T chapters 6–11 | Entropy; staging/current/previous validator rosters; optional full availability guarantees; E4 timeslot. Current/previous roster profiles remain independently specified. |
| T chapters 12–16 | E4 roles and E4-service/E8-gas privilege pairs; E4 validator counters/service keys and compact core/service statistics; ready/accumulated epoch rings; ordered service/output pairs. |
| Account metadata | Version-zero **105-byte** records, including supervisor identity/incarnation and protected balance. Old 89-byte metadata is refused; no production conversion/default policy. See [accounts](state-accounts.md). |
| Service entries | Explicit storage/preimage namespaces, unframed raw values, and request E4-length/hash keys with tagged 0..3 E4-slot histories. Lengths **0..2^32−3** are admitted; **2^32−2 and 2^32−1** return `InvalidLength`. See [requests](state-requests.md). |
| Complete mapping | Exact typed chapter capture, profile binding, typed service declarations, bounded composition and duplicate rejection. Immutable snapshots retain original bytes; opaque hashed service captures have explicitly narrower meaning. See [composition](state-composition.md). |
| Complete-source qualification | All sixteen chapters plus exact supplied service manifests, preimage content/identity checks, logical inventories and validated local checkpoints have bounded source-bound contracts. Partial proofs do not certify complete state. See [global validation](state-global-snapshot.md) and [manifest](state-manifest.md). |
| Merklization | 31-byte keys, canonical node encoding and full-map roots; separate full-state and partial light-proof contracts. See [trie roots](state-trie.md) and [storage](../src/storage/README.md). |

This audit found no further unimplemented byte-layout change in the reviewed
Appendix C/T delta. The subsequent [GP-derived qualification](serialization-gp-qualification.md)
checks those encodings independently within the bounded contracts. This is not
certification of every current JAM state or every protocol rule.

## Evidence and what it establishes

| Evidence | Qualification |
| --- | --- |
| Published C.1/C.2 families and independent component corpora | Exact named encodings, malformed/boundary cases, canonicality, ownership and failure contracts within each suite's declared scope. |
| Fourteen selected published complete pre/post maps | Original roots reconstruct independently. Their 26 metadata rows are 89-byte historical records, even at the current vector pin. Original root agreement is serialized-map compatibility evidence. |
| Explicit 89-to-105-byte test projection | Derived roots and zero supervisor fields are labelled separately. These are neither unmodified upstream current-schema goldens nor a network migration policy. See [source audit](state-current-source-audit.md). |
| Authored complete and multi-service corpora | Fully identified current service records and all namespaces; exact checkpoint bytes, manifest matching, ordering and restored-root agreement. See [complete corpus](state-complete-serialization-corpus.md). |
| Authored profile matrix | Eight complete states across tiny/full and resized current/previous rosters; both Safrole schedules; nonempty contents in all sixteen chapters. Exact-byte and typed-restoration checks pass on checked macOS ARM64 and Linux amd64 under emulation. See [profile qualification](state-serialization-profiles.md). |
| Cryptographic/STF evidence | Qualified Draft 35 Thin primitives and authored complete current STF cases have separate contracts. Neither a correct root nor codec success proves valid cross-chapter state, whole-block parity, finality or root authority. |

The pinned upstream [ServiceInfo schema](https://github.com/davxy/jam-test-vectors/blob/23061ae1f9b51171c01387e7dde0f15794c98e24/lib/jam-types.asn)
still lists the release account fields without supervisor identity/incarnation or
protected balance. Its [trace guide](https://github.com/davxy/jam-test-vectors/blob/23061ae1f9b51171c01387e7dde0f15794c98e24/traces/README.md)
also limits supplied traces to tiny configuration. A gp-next label alone therefore
cannot establish coverage of the current supervisor metadata or full configuration.

The pinned trace tree contains 1,008 JSON paths across eight suites. The source audit
qualifies the seven named trace pairs it actually checks, not all of that tree; do not
turn a path inventory into a corpus-wide validation claim.

## Qualification basis and remaining scope

**M1's documented C.1/C.2 framing baseline is complete. Current reviewed layouts
have independent Gray-Paper-derived serialization qualification within their
implemented schema/resource contracts and the accepted C13 width interpretation.**
See [the equation-to-check matrix](serialization-gp-qualification.md) for the exact
families, covered source identities and observed verification.

The maintainer selected derivation and verification from the pinned Gray Paper on
2026-10-25, excluding expected vectors emitted by another JAM implementation or
reverse engineering. This supersedes the earlier requirement to wait for original
published current-schema complete maps before completing this serialization scope.
Original gp-next cases are retained where compatible. The newer account/transfer
fields are checked by independent equations and literal byte/field anchors;
authored and projected observations are never relabelled as original published data.

The new [typed whole-state suite](state-typed-serialization.md) constructs all sixteen
chapter inputs from native logical fields before comparing encoder output; it does
not merely capture expected wire bytes and re-emit them. All 37 existing serialization
corpus tasks retain their original independent expectations and strict verdicts.
A finite corpus is scoped qualification, not a universal proof over every state.

Additional independent published complete maps remain useful corroboration. Such
inputs need exact revision/blob identities and current schema/field/root checks;
hashed service keys cannot recover original logical keys. Their current absence
from the qualified source set does not block the chosen spec-derived work. No pin
migration, alternate decoder or invented network conversion policy is introduced.

Whole-block STF parity, valid-state relationships and protocol-policy decisions remain
separate work. The current privilege-selection ambiguity is documented in
[the current STF contract](current-stf-bless-allowances.md); successful serialization
does not resolve it. Actual power-loss qualification requires physical hardware,
which the maintainer does not have; it is a separate storage qualification limit.
Simulation evidence must retain its narrower description.

## Reproduction

Run `make unit SUITE=state_serialization_profiles` for the generated profile matrix.
The existing complete, multi-service, source-metadata and refusal suites retain
separate identities and fixture provenance. `make check-python`, `make check-inventory`
and `make format-check` own reference/tooling, registration and formatting verification.
Local macOS/Linux results and exact-head remote CI are distinct observations; see
feature contracts for the covered sources and build profiles.

The [changing-roster STF coverage record](current-stf-changing-rosters.md) tracks
subsequent independently derived reporting/execution and replay/operator evidence.
Those interaction qualifications preserve this document's serialization boundary;
they do not establish complete JAM/STF or external-client conformance.
