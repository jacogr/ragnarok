# Accumulation and dispute preview qualification

## Authority and source

The maintainer authorized this refresh on 2026-11-04. Gray Paper
`fad0ded4a433052397bf7234352a57fe491883f7` remains primary authority.
The vector source advances from `d7b73e396d2f872fcfca37cbbb7d7869675d34d6`
to `c84f9aa79de298aaefb9b60818c67a9416f66c8f` on `gp-next`.
This is unreleased preview data, not a published release. The 166 changed paths
are confined to accumulation and disputes, including eight new Tiny/Full JSON
scenarios and their binary companions. Existing feature exceptions remain scoped.

Source descriptions: pinned
[accumulation README](https://github.com/jam-conformance/jam-test-vectors/blob/c84f9aa79de298aaefb9b60818c67a9416f66c8f/stf/accumulate/README.md)
and [disputes README](https://github.com/jam-conformance/jam-test-vectors/blob/c84f9aa79de298aaefb9b60818c67a9416f66c8f/stf/disputes/README.md).

## Coverage and limits

| New scenario | Published data consumed | Native execution witnesses |
| --- | --- | --- |
| `discarded_junior_creates_no_service-1` | Both phases of account metadata, Tiny/Full | `pvm_annulled_creation_union`, `pvm_annulled_transfers` |
| `discarded_junior_keeps_provisions-1` | Account metadata, storage and preimages in both phases/populations | `pvm_selected_provision_stage`, `current_stf_supervised_conflicts_corpus` |
| `discarded_manager_privileges_revert-1` | Account metadata and complete C12 tuples in both phases/populations | `pvm_annulled_global_roles` |
| `progress_with_faults-8` | Complete dispute input and expected transition, Tiny/Full | `disputes_transition` |

Account, service-value and privilege corpora compare native serialization,
inspection and component roots with independent references: 104 metadata records,
18 storage values, 30 preimages and 20 privilege contexts. These projections do
not execute the published accumulation STF cases. Separate real guest suites and
the signed whole-state supervisor-conflict corpus exercise the listed behaviors
with independently authored fixtures. Complete execution parity for every published
accumulation case remains outside this qualification.

All 62 published dispute cases execute natively. Twenty-three have published
successful outputs; two retain the documented invalid dummy-assignment
incompatibility, leaving 21 accepted transitions. The new overlapping culprit/fault
key contributes two ordered output markers. Existing signature, ordering and
invalid-state checks remain active.

The regenerated live-transfer source starts at balance 229051 and ends at 229151;
the independent reference retains its exact 100-unit credit. Existing operand,
queue and round references consume the refreshed immutable sources.

## Provenance

The submodule gitlink and consumed-source hashes identify the exact preview.
Crypto, Safrole and report source trees are unchanged across the range. The crypto
qualification metadata follows the shared vector revision; its changed file identity
requires six primitive-input provenance records and dependent fixture fingerprints
to be refreshed. Signatures, commitments, complete-state roots, checkpoint hashes
and native expected-output hashes retain their previous values. Historical fixtures
retain their original identities.

Existing historical codec metadata is retained. Updating these two STF families
does not qualify every preview record against all current Gray Paper codec changes.
Production keeps one current representation and the established explicit test-side
historical projections.

## Separate lineage gap

This range contains no report changes. The lookup-slot repair on vector `master`
at `ac9160354fa31ee3671c67a6e333f42aa54aa57a` is absent from this `gp-next` target.
Track it separately; ancestry checks are unchanged. Other pending Gray Paper
proposals are outside this refresh.

## Verification

Local checked native qualification covers four corpora and six suites, including
`accumulation_round`. Registered ARC workloads retain flat occupied memory over
1,000 cycles. Python checks cover source identities, independent field/credit
references and all four new scenario descriptions in both populations. Fixture
hashes, formatting, inventory and whitespace are checked separately.
