# GP539 vector qualification

## Scope and authority

The maintainer authorized this vector upgrade on 2026-10-30. Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains primary authority.
The canonical `jam-conformance/jam-test-vectors` `gp-next` pin advances from
`23061ae1f9b51171c01387e7dde0f15794c98e24` to
`d7b73e396d2f872fcfca37cbbb7d7869675d34d6` (Regen STF vectors for GP 539).
This is unreleased branch data, not a new published vector release.

## Integration

The upstream commit changes 519 paths; 108 of the 379 previously consumed source paths
change. Selected source hashes are refreshed from exact immutable Git bytes.
The account and report-policy references now preserve the published supervisor,
supervisor-creation-slot and supervisor-balance fields rather than synthesizing zeroes.
The live-transfer projection retains its 100-unit credit; its published starting balance
changes from 227738 to 229035. Historical 89-byte trace metadata remains explicitly
projected into the current 105-byte layout, with its original provenance.

The Safrole source bytes and derived Bandersnatch vectors are unchanged. Updating
`official_jam.commit` changes the crypto pin-file hash, so the six JAM input witnesses
and their dependent report/descriptor hashes are refreshed without changing signatures,
crypto commitments, state values or observations. Historical mixed-profile signed-trace
refusal evidence retains its original source revision.

## Completion checks and limits

Require exact source provenance, independent account/width/root/credit references,
native account/report-policy/credit consumers, and the full CI run on the top fuzzing
PR. This pin upgrade does not claim complete execution parity for every upstream
accumulation case. Eight new JSON scenarios (four per population), including junior
transfers and supervisor discard/control cases, now supply both transition phases to
the independent/native account metadata corpus, with literal field-offset checks and
nonzero supervisor identities (these cases retain zero creation slots and balances). This covers serialization, not full execution
of those scenarios; existing independently authored current-STF supervision coverage
is retained.

## Restored junior services in the November 19 preview

The separate unreleased `vectors_preview` advances from
`e941b86247ec42faa206132ef895347e9fc70443` to
`7175ee4d98ae2d3132e45101497a2691b24bb683`. The exact Git diff has 503
modified paths and 28 additions, comprising 14 new Tiny/Full JSON and binary
pairs and the regenerated report and accumulation cases. The historical vector
gitlink at `a49f241a791f559d1502dc1b0b5328372995e375` remains the source for
historical consumers. Released [GP 0.8.1](graypaper-0.8.1.md) governs the runtime.
[Upstream comparison](https://github.com/jam-conformance/jam-test-vectors/compare/e941b86247ec42faa206132ef895347e9fc70443...7175ee4d98ae2d3132e45101497a2691b24bb683)

The restored `ServiceInfo` schema carries the supervisor ID and creation slot
after the code hash and the protected balance after the ordinary balance. It
matches the current 105-byte metadata codec. The report policy suite uses the
preview's actual metadata, rosters and credentials for seven cases per
population. The independently encoded input and the parent metadata match the
paired binary. Both populations use the shipped gas presets. The Tiny preview
rejects `too_high_auth_gas-1` and `too_high_work_report_gas-1` at its old
50M and 10M ceilings. The signed inputs pass the client's 235M and 47M shared
ceilings. The Tiny refinement override and bundle limit still agree with the
expected preview verdicts.

The initial accumulation planner checks 13 cases per population, including the
seven new junior-service and transfer scenarios, three recreation forms with
later work or transfers, recreation within one invocation, and both ejector
orders. It uses the paired input bytes, compares exact C.2 service inputs and
checks the selected gas prefix. The Full 16.45B boundary cases defer the second
report. In the corresponding Tiny cases the client's 94M budget floor admits
both reports initially, while the published inputs use an upstream 20M block
profile. The independent account corpus separately verifies 168 pre/post
metadata records against the paired binaries and exercises the native codec.

These fixture checks cover report policy, initial accumulation planning and
account serialization. Independent native execution checks cover host call 29,
ejection and reserved-ID recreation, deferred and annulled transfers, retained
provisions, and rollback of junior creation and privilege effects. Complete
posterior state and upstream guest gas totals remain outside the qualification.
The preview upgrade leaves host pricing and the documented compatibility
decisions in force.
