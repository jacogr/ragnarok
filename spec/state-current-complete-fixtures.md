# Authored complete typed current fixtures

Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`; no production or
upstream source changes. Existing signed fixture defaults deliberately commit a
C250 sentinel for preservation/rollback and omit parent C16. They are scoped
transition witnesses, not complete typed-map input goldens.

New opt-in `completeState` authoring emits canonical empty C16 instead of that
unrelated sentinel before parent commitments and all child signatures are made.
Defaults remain unchanged. Newly authored no-execution/no-blob fixtures explicitly
supply logical services 42/99 with exact known C255 metadata and empty child maps.
No raw keys or request identities are guessed from physical hashes or touched
operations. Complete matching, not enumeration alone, verifies those declarations.

Genuine plain/assured/disputed/ticketed/epoch current children validate all globals
and complete service manifests on both original parent and posterior state. The
successor has exactly sixteen global plus two metadata rows; targeted footprint/
content/linkage review succeeds under the original retained economic parameters
without content hashes. The default sentinel witness still refuses whole-map
matching, proving global qualification alone cannot grant complete service claims.

This is validated authored supplied inventory, not a PVM producer-owned logical
manifest export, independent published whole-block golden, code-availability or
full current-pin authentication/STF proof. Run
`make unit SUITE=state_current_typed_fixture` and affected default fixture regressions.

Observed locally: all five complete current cases and legacy sentinel control
passed. Existing current candidate, current checkpoint capsule and report-admission
regressions passed with fresh 1,000-cycle ARC release evidence; inventory and
pinned formatting passed under checked ARC/Clang release on macOS ARM64. Linux CI
and full current-pin upstream/authentication/STF parity remain separate.
