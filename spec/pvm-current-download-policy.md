# Explicit current download policy

Pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains definitive. This host resource
configuration changes no protocol interpretation, dependency pins or wire/storage formats.

Current policy documents begin with the exact header `ragnarok-current-download-policy-v1` and
supply all 389 unique `name=canonical-unsigned-decimal` rows in the explicit private
`src/app/current/download/policy/fields.nim` schema. It covers the scalar scheduler, input/ancestor ceilings,
current candidate reporting/queue/round, initial execution, continuation planning/execution, every
current composition stage, sealed-header capture and callback/total deadlines. Discovery permission
is an explicit boolean encoded only as zero or one. It is not inferred from a legacy document.

The schema was reviewed against 72 exported resource object definitions. Existing reporting paths
use the same declared BlockReportConfig, including its state-codec AvailabilityConfig; unrelated C2
record types with the same short name are not selected. The committed schema is explicit and frozen,
with no runtime reflection, generated field inference or defaults. Adding/changing resource leaves
requires version review. It does not serialize certificates, state, protocol facts or execution success.

Current and legacy types and headers are distinct. Neither decoder accepts the other's document.
Text/file input is capped at 65,536 bytes before parsing/assignment. Key/line/field/decimal counts,
canonical syntax, duplicates, unknown or missing fields, narrow nominal conversion and outer runtime
bounds are checked before returning a complete copied policy. Partial assignment stays private;
failures retain only the selected reason and bounded field name. Zero stage ceilings are explicit
caller policy and may produce the corresponding stage refusal; syntactic success is no execution
certificate. Positive callback, payload, peer, retry and total-deadline bounds are required at startup.

Run `make unit SUITE=pvm_current_download_policy`. The native suite independently omits each of
389 rows, checks selected deep current fields, exact field diagnostics, canonical numeric syntax,
uint64 maximum, narrow overflow, explicit boolean bounds, unknown/duplicate/malformed/version/
size/file refusals, and immutable policy copying. It executes a genuine signed two-guarantee current
candidate with the decoded policy and independently compares every resulting state entry; a tiny
sealed-header ceiling produces the actual typed preparation refusal. The 1,000-cycle parser ARC
workload is separate from execution. Source-owned privacy/nominal and result guards remain required.

The current command layer must select this schema explicitly and reconcile discovery permission
with its requested acquisition mode without silently replacing current ceilings. Production command
selection remains subsequent work. Local macOS evidence does not establish Linux CI, sustained
load or complete JAM/ThinVRF parity.

Local macOS ARC/Clang validation passed for the complete native suite, 1,000 parser ARC cycles,
privacy/legacy-policy nominal rejection, three runtime extraction guards and matching successful
policy extraction control, focused semantic checking, inventory and pinned formatter idempotence.
Probe success is constructed in a separate checked helper so the compiler does not replace the
intended runtime refusal with compile-time assertion propagation. Implementation contracts remain
unchanged; no arbitrary nonzero exit is accepted as guard evidence.
