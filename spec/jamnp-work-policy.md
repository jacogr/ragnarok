# Explicit node work execution policy

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab` CE146 and Gray Paper
`fad0ded4a433052397bf7234352a57fe491883f7`. The ordinary `node` command may activate its
managed bundle dispatcher only with `--node-work-policy FILE`; omission preserves disabled work.

The bounded versioned text contains every numeric child resource limit and named PVM backend.
Unknown, duplicate, missing, malformed, overflowed and oversized inputs fail atomically before
network activation. No file value may select canonical state, identity, a private signer or a
logging callback. Logging borrows the command's existing stable owner. A complete policy configures
resource ceilings; actual state/duty/authorization/proof/refinement checks still establish success.

Verification must cover all-field round trips, actual execution using decoded limits, complete
schema refusal cases, bounded file reads, CLI normalization with/without the independent ticket
seed, failed startup, actual finite node shutdown and the disabled default. This activation does
not add CE133 availability acquisition, report credentials or the remaining availability/audit flows.

## File format

`ragnarok-work-policy-v1` is the first line. Each of the 85 values in
[`work_policy/fields.nim`](../src/app/work_policy/fields.nim) follows as an exact ASCII `key=value`
line. Blank lines and lines beginning with `#` are allowed within the 32 KiB whole-file limit;
a final newline is optional. Numeric leaves use canonical unsigned decimal. Backend leaves use
`jit`, `interpreted`, `polkavm-interpreted` or `polkavm-compiled`, matching the existing explicit
engine API. Removed engine names, enum ordinals and case/whitespace aliases are refused.

`encodeWorkPolicy` emits the entire schema from explicit admission, execution, duty and timeout
inputs; it invents no child budgets. `decodeWorkPolicy`/`loadWorkPolicy` return a guarded complete
activation policy or a bounded reason/field diagnostic. The CLI reports that diagnostic through
its existing logging owner. Logging pointers are never serialized. The independent optional
`--node-validator-seed` continues to control Safrole ticket production.

## Observed verification

Local checked ARC/Clang verification passed: `jamnp_work_policy`, `jamnp_work_dispatch`
(14 actual TLS/PVM cases with decoded policies, including zero-step authorization refusal),
`jamnp_node_command`, `app_cli` and `app_options`. Command tests cover missing/malformed files,
policy-only and policy-plus-ticket-seed startup, bounded shutdown and default disabled handling.
The CLI release check retained 101,488 bytes before/after 1,000 cycles. Fresh actual lowering
rejected copying WorkDispatcher and ApplicationNode after the policy type was separated from
transport. Application build, formatting and inventory passed. These are local results, not
exact-head Linux CI evidence.
