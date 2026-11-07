# Preimage bounds and preview compatibility

## Authority and compatibility decision

Current authority advances from `fad0ded4a433052397bf7234352a57fe491883f7` to
`44e0b1154ec1f556354b92b8ee58d097c2038167`. Its complete source delta changes
preimage limits and service provision statistics; it does not remove supervision.
The target [account definition](https://github.com/gavofyork/graypaper/blob/44e0b1154ec1f556354b92b8ee58d097c2038167/text/accounts.tex)
retains supervisor identity, creation slot and protected balance, and the
[accumulation rules](https://github.com/gavofyork/graypaper/blob/44e0b1154ec1f556354b92b8ee58d097c2038167/text/accumulation.tex)
retain optimistic junior execution, annulment and preserved provisions.

The vector preview `fdaa4c9482552e6554bd15a73d91b85917ff8446` explicitly removes
the supervisor feature from its changelog, account schema and selected fixtures.
The removal commit says only “Removed 539 vectors”; the preview description says
“NOT READY”. These establish a deliberate preview profile change, not a normative
reversal or a documented final release boundary. No further author rationale is
asserted. Production continues to implement the target GP rather than that profile.

The existing `vectors` source at `a49f241` remains an immutable supervisor-era
evidence pin. A separate `vectors_preview` entry selects the exact new revision
and hashes for preimages, assurances and codec evidence. Both histories are retained
in the same vendor repository; setup fetches preview objects without replacing the
historical checkout. Selected consumers name the preview explicitly. The account,
reports and accumulation fixtures keep their previous source/schema contracts.
There is no production old/new codec fallback or automatic supervisor defaulting.

The full Git diff covers 605 paths (573 modified, 28 removed, four added), beyond
the truncated API listing. The removals are preserved in the historical source;
no authored supervisor regression is deleted. The preview is unreleased. Open
erasure, storage-footprint and Refine proposals remain outside this upgrade.

## Supervisor inventory retained

| Concern | Current implementation and evidence |
| --- | --- |
| Metadata and storage | `src/codec/state/accounts.nim`: 105-byte records, supervisor identity/creation slot and protected balance; service supervision/table suites |
| Host numbering and authority | `src/state/accumulation/dispatch.nim`: host 29, existence/incarnation checks; native `pvm_accumulation_supervisor` |
| Junior resolution and transfers | `src/state/accumulation/annulment.nim`, `transfer_partition.nim`, `round.nim`, `round/transfers.nim`; independently authored conflict and transfer cases |
| Preserved provisions | `src/state/accumulation/selected_writes.nim` and current sequence publication; selected-provision and hash-return witnesses |
| Creation, endowments and rollback | Existing annulled-creation, global-role, transfer and selected-provision suites; supervisor-era account/privilege source projections remain pinned |
| Source contracts | `spec/vector-accumulation-disputes-upgrade.md`, source-audit and fixture contracts preserve historical bytes and explicitly derived records |

Removing this machinery would contradict the chosen authority. A future release
which actually excludes supervision requires an explicit authority/profile decision
and a separately reviewable metadata, host-call and state migration.

## Protocol and resource boundaries

The preimage extrinsic permits at most 256 items and at most 33,554,432 raw data
bytes, including the endpoints. Service identifiers and length framing are excluded
from the data sum. Block component inspection rejects a count beyond 256 as
`InvalidCount` before traversing records. Generic framing remains available for
locally bounded host-provided value sets.

State admission checks `TooManyItems` and `TooBig` separately from caller
`LimitExceeded`, before copying or hashing the payloads. The sum uses subtraction
under wrapping arithmetic. Invalid input produces no admitted certificate or writes.
Local capture, per-blob, wire and state storage ceilings remain independently valid.

Provision statistics were already grouped by exact service identity in
`src/state/preimages.nim` and copied into each service's C13 entry by
`src/state/core/service_activity.nim`; the new GP filter confirms that behavior.
The new 256-item preview case exercises two service groups in both populations.
Directed tests cover an exact 32 MiB total across two services, local rejection one
byte below it, and protocol rejection one byte above it before hashing.

The anchor-free assurance codec already matches the current GP. The selected
preview now supplies unmodified anchor-free codec bytes and all 22 assurance STF
cases. Symbolic verdicts remain the native test boundary; preview enumeration shifts
do not renumber production error enums or restore the removed parent field.

## Qualification results

Local qualification passed eight native suites: preimage admission/integration,
block composition, availability transition, supervisor host, annulled creation,
selected provision retention, annulled global roles and core/service activity.
Their registered 1,000-cycle ARC observations remained flat. The signed supervisor
conflict corpus passed all 30 independently authored complete-state transitions
over five chains.

The independent codec corpora passed 33,393 assurance and 17,065 block/extrinsic
requests. All 607 production modules and the peer entry point passed semantic
compilation. Focused Python checks passed (47 source/codec/contract checks,
17 setup checks and four preview checks, with overlapping source checks);
formatting, inventory and whitespace checks passed. These are scoped local
results, not full published STF parity or a production-validator claim.
