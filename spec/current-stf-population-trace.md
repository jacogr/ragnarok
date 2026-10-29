# Authenticated TraceStep imports with changing rosters

Authority: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` governs the
independently qualified transitions. Published TraceStep/RawState framing follows
pinned `jam-conformance/jam-test-vectors` gp-next `23061ae1f9b51171c01387e7dde0f15794c98e24`.
RawState values retain current-schema bytes; no historical account format is
silently translated or accepted as an alternate representation.

Nine complete authored chains transport102 full pre-state/signed-block/post-state
steps through the production authenticated importer. They retain the exact roots,
complete map hashes, refusal paths and trusted configuration of the checkpoint
replay family: offenders, write/panic/checkpoint guests, ticket sealing, dependency
release/resize-clear, deferred gas and historical lookup bounds. Expected maps come
from independent equations before native execution; no other client emits answers.

For each transition the native driver supplies a correctly recommitted wrong
pre-state, a correctly recommitted wrong post-state, and a block with an altered
seal. These produce exact PreStateMismatch, PostStateMismatch and CandidateFailure
refusals and preserve the complete canonical map and selected hash. Valid imports
run actual candidate admission/execution and compare every key/value of the result;
the advertised posterior never constructs the installable successor. Actual typed
globals/services are qualified before installation and only accepted headers become
later lookup context.

Completion requires102 genuine imports,306 trace refusals and14 inherited report
refusals, independent complete framing/root checks, unchanged checkpoint answers,
strict per-chain completeness, inventory and formatting. This bounds authenticated
wire/import integration; full JAM/STF and external-client execution remain separate.

Observed checked macOS ARM64 ARC/Clang non-LTO: all102 imports,306 trace
refusals and14 inherited reporting refusals passed exact complete output comparison.
The unchanged102-restart corpus and its checkpoint controls also passed. All41
scoped independent/runner tests, inventory and pinned formatting passed.

Checked Linux amd64 passed all102 authenticated imports with identical complete
outputs, including306 trace refusals and14 inherited reporting refusals. Every
frozen runtime input matched the host and retained image
`ragnarok:db5-population-trace`
(`sha256:2c5c191b15216e32385a1eaa60b7a2d4198c20b39c753ac8e2f6be118e31f4cc`).
This is covered-source local evidence, separate from exact-head CI.

A follow-up keeps the trace frame policy in a short local binding to stabilize
the pinned formatter. Its values and transition behavior are unchanged. Scoped
formatting and trace checks cover the follow-up; the final operator qualification
records the final covered-source Linux replay separately.
