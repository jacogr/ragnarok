# Source-bound complete service inventory

Current GP pin `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, T and accounts
invariants. Capture compact logical service declarations only after complete exact
manifest matching. This supplies provenance for subsequent checks, without claiming
footprint/preimage/STF validity or discovering identities from opaque digest keys.

An existing genuine `ValidatedStateManifest`, explicit declarations and all capture
policies are required. Preflight service count, every retained fact and native
descriptor byte extent before output allocation or hashing. Revalidate the supplied
declarations against the original complete map before retaining fixed metadata,
storage key/value lengths and physical keys, preimage hashes/lengths/keys, and
request identities/tagged histories. Never retain caller arrays or duplicate payloads.
A late key/backend refusal exposes no prefix. Source identity remains the original
manifest owner; a second equal-root source does not replace it.

Ordinals are full-width distinct service/storage/preimage/request types. Returned
facts and metadata are detached fixed copies. Default/out-of-range results are
guarded; missing indices do not fabricate absence facts. Captured order is the
explicit declaration order. Resource refusals, failed manifest validation and late
key derivation reasons remain distinct and private.

Tests cover fixed literal declarations, mutable input/output isolation, exact source
identity, independent exact/short fact/byte limits, backend refusal before and after
matching, wrong declarations, full-width indices and 1,000-cycle ARC retirement.
No storage API/format, Services, proof integration, root policy or pin changes.

Local checked macOS validation passes the new module, source helper and native/
misuse drivers. The native suite checks exact compact observations, immutable
copies, whole-source revalidation, independent exact/short descriptor limits,
full-width ordinals and early/late backend refusal. Its1,000-cycle ARC workload
retains89,440 live bytes before/after. Four strict runtime guards, genuine linked
success and eight compiler privacy/nominal rejections pass. Inventory and pinned
formatting pass. Logs: `build/state-inventory-*`, `build/tests/state_inventory/`.
These local results do not establish complete state/STF or exact-head Linux parity.
Next: checked footprint equations and source-bound account invariant validators.
