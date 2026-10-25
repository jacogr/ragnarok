# Whole-map reporting across an epoch boundary

Authority: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`reporting_assurance.tex` assurances, guarantor assignments/priorassignments,
guarantee credentials and vacancy; `statistics.tex` pre-rollover assurance
accounting and posterior reporter-key attribution; Safrole and accumulation
queue equations. Vector and toolchain pins are unchanged.

Two independently authored chains use distinct active/pending/staging/previous
roster orders and distinct historical entropy words. They advance from slot1
through2,10,11,12,13,14,15,16,17 under the explicit two-core/six-validator profile.
The empty slot2 child supplies an authenticated lookup ancestor with a child-committed
posterior root before reporting starts. Both guarantee two reports at10,12,16; one chooses current-rotation credentials,
the other previous-rotation credentials. At12 the latter must use the old active
roster and old eta2, while current credentials use the newly active roster and
old eta1. At16 both rotations use the new active roster. No RingVRF proof input
is submitted; the unchanged original qualified ring commitments remain inputs.

Four prior-roster assurances at11/13 retain both assignments. Five at12 release
the old reports before replacing both cores in the same block. Five at14/17
release the later reports. At the crossing assurances are signed against the
prior active roster and added to previous statistics before rollover. Guarantee
statistics map reporter keys into the posterior active order, rather than
reusing credential indices across rosters. Reports retain an explicitly authored
recent but unaccumulated prerequisite, isolating availability/ready-ring behavior
from guest execution. Complete maps preserve every service namespace byte.

Expected blocks, exact complete checkpoint bytes and roots are independently
calculated before native compilation/execution. The frozen fixture holds roots
and checkpoint hashes, with a descriptor binding its exact content and the
original distinct-roster fixture. The original map is authored test input, not
independent genesis-generation qualification. No other client's emitted output
or observed production successor supplies expected bytes. The local V1 checkpoint
remains a comparison envelope, not GP protocol serialization.

The registered `current_stf_epoch_reporting_corpus` executes the real candidate
pipeline, qualifies all globals and exact service namespaces, installs successful
children and preserves the original retained complete map. Wrong-key signatures,
wrong-core assignments, too-old rotations and invalid assurances are independently
classified and re-sealed as valid block inputs. Every refusal must leave the
canonical complete map and selected head unchanged; no partial candidate is
installed. Expected observations cover18 transitions and28 exact refusals.

Reusable native resource limits and exact failure projection live in a support
module with no executable entry point. The reporting reference shares its unchanged availability/pool/history/ready/core
statistics equations through an explicit helper. Epoch callers supply independently
selected reporter indices and assurance rollover destination. Existing same-epoch
frozen maps and refusals must remain byte-identical.

Completion checks: new registered corpus, existing reporting regression corpus,
independent invariant tests, source inventory and pinned formatting. Local checked
ARC/Clang evidence and exact-head remote CI remain distinct. This closes the
bounded epoch/reporting interaction gap; it does not establish general JAM STF,
external-client conformance, arbitrary population/eviction combinations or guest
execution of these reports. The existing conflicting-allowance ambiguity is unchanged.

Observed locally on macOS ARM64, pinned checked ARC/Clang release (the ordinary
non-LTO corpus profile): all18 transitions and28 exact refusals passed full-output
comparison. The existing reporting corpus passed its original20 transitions and35
refusals with its frozen expected maps unchanged. Ten independent reference tests,
verification inventory and pinned formatting passed. These local observations do
not infer a remote Linux CI result.
