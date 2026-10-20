# Execution bound to original verified inputs

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
work_packages_and_reports.tex computereport/E, ordered I and segrootlookup;
pvm_invocations.tex Psi_I/Psi_R. Vector pin remains
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: consume VerifiedImportInputs, derive its original package through its
verified extrinsics, and run authorization internally with caller-selected
complete state/core/parameters. Never accept a detached package, trace, CPU,
authorization/refinement result or replacement dictionary. Reject default input
owners before authorization. Preserve authorization's typed local failure; reject
protocol work errors and over-limit traces before materializing any input bytes.
Apply the independent local trace cap after the 49152-byte protocol trace gate.

Before input materialization, preflight an independent local byte cap for all
extrinsic payload plus 4104 bytes per import occurrence. Subtract the extrinsic
size from that cap before comparing imported bytes. Immutable source invariants
bound import multiplication to 3072*4104 and extrinsics to the package byte ceiling.
Materialize exact all-item tables exclusively from the retained verified owners.
Existing child capture/copy/execution budgets remain independent. Run ordered
refinement and source-bound digest projection through the existing authorized
composition, then derive report identity using only the original input owner's
lookup dictionary. Retain the original inputs beside that exact identity; the
identity owns its matching authorization/report/digests. Preserve typed failed
child alternatives without partial completed owners. Accessors return immutable
handles and require successful alternatives in optimized builds.

Execution remains conditional on the supplied complete state and root resolution.
Root freshness, known/unexpired status, package-hash/root correspondence and state
freshness versus the lookup anchor are explicit caller obligations. This layer
does not manufacture a root-trust certificate or retroactively certify older
execution. It binds the bytes actually executed and lookup actually committed to
the original verified input owner. State still owns block composition/publication.

Completion tests: real authorizer and multi-item guests fetching current/other
extrinsics, imported segments and original authorization trace; exact source/hash/
lookup/state/core binding, local input-copy caps and protocol authorization gate
precedence, typed late child failures, replay/copy/lifetime isolation, compiler
privacy/source rejection, optimized result/reason guards and fresh 1000-cycle ARC.

Next: authenticated root/state trust integration and auditable bundle assembly,
then erasure coding and complete work-report construction. M1 framing is complete;
full state serialization and whole-block parity remain open.

Local evidence: checked optimized macOS `make unit SUITE=pvm_input_refinement`
passes actual current/other-item extrinsic/import/trace reads, original package/
lookup/state binding, exact materialization caps, 49152/49153 trace boundaries,
protocol rejection precedence, nested lookup/backend and late child refusals,
replay/copy/lifetime isolation and fresh 1000-cycle ARC (370352/370352 occupied
bytes). Twelve optimized result/reason/owner/failed-child guards with genuine
successful controls and six compiler privacy/source/core rejections pass.
Formatted unit/driver semantic checks, inventory, 19 affected inventory/provenance
Python tests and pinned formatting pass. Lower production modules are unchanged;
prior lower-layer evidence remains applicable. Exact-head Linux CI is separate;
remote checks were not requested.
