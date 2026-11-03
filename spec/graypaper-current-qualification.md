# Current Gray Paper qualification

Target source: `fad0ded4a433052397bf7234352a57fe491883f7`, compared with
`3861aed15d7d016a3a416e14e61fc67dddf6daec`. The upgrade covers authorizer code limits,
package gas inclusivity, report refine-load bounds, refinement failure precedence,
bless duplicate keys, parent-free assurance wire records, and compact validator statistics.
The final qualification layer updates the source pin and public preset tuple after all behavior
changes are represented; intermediate layers qualify target behavior without claiming whole-upgrade completion.

The vector dataset remains `d7b73e396d2f872fcfca37cbbb7d7869675d34d6` on `gp-next`.
Its old assurance/statistics bytes are historical evidence and do not independently qualify the
new encoding. No dataset switch or alternate decoding is authorized. The existing compact-gas
interpretation and fixed E4 service keys remain in force.

## Execution bounds

`text/definitions.tex`, `text/work_packages_and_reports.tex` and
`text/reporting_assurance.tex` distinguish input data (13,791,360 bytes) from the encoded
bundle (13,904,950 bytes). Fetch keeps the input limit. Package gas sums accept equality.
Reports independently bound refinement gas, imports, exports, extrinsics, input footprint,
bundle bytes and authorization gas, and require exported segment-count equality.
Every aggregate checks remaining capacity before arithmetic. Invocation errors retain their
kind before successful output oversize/export checks. Authorizer code permits196,608 bytes.

Completion checks include exact/one-over package gas and report load boundaries, full-width
counter overflows, per-report reset, authenticated authored reports, real refinement invocations
with overlapping failure conditions, exact/one-over authorization code, and unchanged fetch input
limit. Remaining upgrade layers and their focused tests must pass before claiming completion.

Signed combined-activity fixtures use the actual Tiny per-report refinement ceiling of1B gas,
then verify the two-report2B service total. The old UINT64_MAX signed-report overflow scenario
is incompatible with admission bounds. Independent pure core/service projection witnesses retain
full-width arithmetic overflow coverage; no admitted certificate bypasses the new report policy.

## Execution-layer evidence

Checked native suites pass for package boundaries, signed report policy, actual refinement report
results, authorization invocation, authorized/owned-input refinement, both startup-policy paths,
computed admission, assured queues, auditable bundles, fuzzer profile selection and accumulation
statistics. The latter retains independent literal wire expectations and fresh1,000-cycle ARC
release evidence. The independent mathematical package corpus agrees byte-for-byte on8,127
context/import/commitment/item/package requests, including exact gas equality and one over.
All486 production modules and the peer entry point pass checked-release semantic compilation;
final fuzzer/CLI changes receive focused semantic and native checks. Package reference tests and
trace-conformance tooling tests pass; formatting, inventory and whitespace checks pass.

Evidence is local macOS checked/optimized execution under the recorded pinned toolchain,
retained in `build/gp-execution-*` and `build/tests/gp-package-corpus/result.json`. It establishes
this layer's behavior, while source-pin adoption, bless and new wire/state encodings remain
subsequent qualification layers. Whole-client and exact-head Linux CI claims remain separate.

The bundled `config/tiny-devnet-policy.conf` is migrated with the v2 schema and explicitly
sets Tiny refinement gas to1,000,000,000. The current-policy native suite loads that actual
shipped file through the same file decoder used before devnet listener startup, in addition
to exercising generated policies. Its fixture provider passes the source path directly and
records a transport digest; it does not substitute a copied policy or infer its correctness.
