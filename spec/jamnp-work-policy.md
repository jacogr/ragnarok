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
seed, failed startup, actual finite node shutdown and the disabled default. The v1 profile remains unsigned. The explicit v2 extension below activates the bounded guarantee
pipeline; assurance and audit lifecycles remain separate outstanding work.

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

## Explicit guarantor profile (v2)

Selecting `ragnarok-work-policy-v2` explicitly opts into the complete bounded guarantor pipeline;
omission and v1 never load its private signer. V2 requires the original submission fields plus
all fields in [the guarantor schema](../src/app/work_policy/guarantor_fields.nim). It adds report
composition and eligibility, private serving retention, CE137/147/148 response work, signature
collection, CE135 receipt/delivery, CE133 segment acquisition and original-assurer fallback
recovery. There are no inferred child budgets. Shared submission/execution stages use the same
explicit base policy, and distribution uses the same explicit eligibility policy.

`NodeWorkSettings`/`encodeGuarantorPolicy` serialize explicit inputs. The node's versioned loader
preserves the v1 contract and accepts v2 only when every required field and bounded controller
constructor succeeds. Both versions share strict lexical, canonical-number and backend parsing.
The complete file is validated before Services, sockets or optional key loading. The actual node
TLS certificate/key arguments supply signing identity; the policy cannot name replacement keys.
The existing full-state/light-mode command gate remains mandatory. CE135 activation also requires
the actual TLS identity to have the configured validator role; an explicit file cannot bypass it.

The foreground command and ordinary application-node tests use one `configureNodeWork` activation
path. It enables submission, acquisition, recovery, TLS-matched signing with retained serving, and
receipt/delivery before polling. Default policies enable nothing. Startup failure returns through
joined host/Services cleanup without admitting work. A bounded `NodeWorkSetupError` identifies
the refused controller through startup logging without exposing key or policy contents. Read and
signing operations still require
fresh genuine source/state/duty/authorization/refinement evidence; a parsed policy is not such
authority. The independent ticket seed continues to control Safrole ticket production.

Checked native verification passes `jamnp_work_policy`, `jamnp_node_command`,
`jamnp_work_exchange_runtime` and `app_cli`. Coverage includes every required v2 leaf being
removed independently, strict malformed/overflow/whole-file refusals, unchanged unsigned v1,
real file-driven three-node signature collection and CE135 delivery, foreground v2 startup and
joined shutdown with/without the independent ticket seed, and refusal of a distinct non-validator
TLS identity. All eighteen runtime scenarios pass. CLI ARC evidence retains 101488 bytes before
and after 1,000 cycles. Pinned formatting, verification inventory and all 555 production modules
plus the application entry point pass locally. The checked production ARC/LTO build also passes.
These checks do not claim native Linux CI.
