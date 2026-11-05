# JAMNP-S builder work submission

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, CE133 and CE146;
Gray Paper `fad0ded4a433052397bf7234352a57fe491883f7`, work-package authorization,
extrinsic commitments and import justifications.

## Scope and ownership

This increment implements the synchronous admission boundary for builder submissions. It decodes
exact message payloads, caps the package before authorization, checks the selected core's C(1)
authorizer pool, executes the actual historical authorizer and permits body verification only from
that successful private grant. It authenticates every extrinsic and imported segment, preserving
original package ownership and import order. The result is the existing `VerifiedImportInputs`
owner consumed by refinement; it is not a guaranteed report or canonical adoption certificate.

CE133's first payload is E2 core followed by the package, capped at the GP encoded-bundle ceiling
plus two bytes. CE146's first
payload is E2 core followed by a canonical natural mapping count and strictly ordered unique
32-byte package/32-byte segment-root pairs; its second payload is the package, bounded by the same GP encoded-bundle ceiling and the
caller's explicit package-byte policy. A package must consume its entire message. Dictionary keys must exactly match package
import references, with the existing total dependency limit of eight.

A grant retains its original immutable complete state and successful authorization. Native callbacks
must never own it. Application integration must retain it under the managed Services graph gate,
including while another CPU job is Done but uncollected. The module does no I/O and starts no worker.

CE146 bodies have three exact payloads: concatenated extrinsics, all raw 4104-byte imported segments,
and canonical length-prefixed hash paths. CE133 verifies its one extrinsic payload and binds imports
separately acquired from availability. Explicit package/root mappings are authenticated against the
same source state's recent C(3) history; unavailable mappings are refused, never blindly trusted.
Root inclusion is not proof of current availability. Local byte/count/hash limits precede allocations.

## Completion checks

The focused suite must use actual authorizer execution and real extrinsic/import proofs. It covers
both forms, empty input tables, exact message boundaries, excessive/noncanonical counts, package
suffixes, wrong cores/pools, rejected authorizers, missing/wrong mapping roots, altered or truncated
extrinsics/segments/proofs, original ownership after caller mutation and repeated ARC release.
A valid completed input must reach the existing refinement/report and auditable-bundle pipeline.

## Remaining integration

This is the admission/execution boundary, not yet a live CE133/146 server. Subsequent work must add
bounded staged native framing, pause body reads until authorization is collected, manage grants
outside callbacks under the Services lease, fetch CE133 imports, and retire exact stream/job tokens.
CE134 sharing, report credentials, availability and audit participation remain separate work.

## Observed evidence

On current master `28f7c2c783c5c9f2bc4cb66654b9abb9266e7630` plus the preceding native
JAMNP-S stack, `make unit SUITE=jamnp_work_submission` passed under pinned Nimony,
checked ARC and the existing primitive observer link profile. The suite performs actual PVM
authorization and refinement and constructs an auditable bundle from the decoded inputs.
One thousand success/late-proof-failure cycles retained 748784 bytes before and after.
The first runner attempt exposed a test evidence filename mismatch; the test used the suite
identity for `recordArcRelease` and the corrected supported invocation passed. Inventory and
format checks passed. These are local results, not an exact-head Linux CI claim.

The earlier200KiB package ceiling was an implementation restriction, not the pinned GP input rule.
Target work_packages_and_reports.tex107..126 permits payloads up to the aggregate13,791,360-byte input
footprint and bounds the entire encoded bundle by13,904,950 bytes. Upload framing now uses that
existing codec ceiling; the package decoder still checks all footprint/gas/item constraints and
callers may impose smaller explicit resource limits. Global/per-peer physical quotas and the
authorization pause before reading body messages remain in force.
