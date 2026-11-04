# Source-eligible work-report guarantees

Target JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, CE134/135, and Gray Paper
`fad0ded4a433052397bf7234352a57fe491883f7`, reporting/assurance and work-report computation.

This feature must authenticate the original package's complete recent-anchor tuple, lookup-anchor
identity/slot/posterior root and inclusion-age window before granting any signing or sharing
capability. The candidate next block uses the current head's actual complete posterior root to
correct the latest C(3) record. Older lookup roots require the retained child-header commitment;
the current head's lookup root can be checked directly against its trusted complete map. A header
hash alone cannot authenticate a substituted posterior state.

Historical code lookup remains the GP historical-availability mechanism, using a recent complete
view and the declared lookup time. Work-report computation explicitly supports this mechanism;
this feature must not silently replace it with a different execution-state model. Context validation
alone proves neither authorization, package/dependency eligibility, successful computation nor
credential authority. Private immutable capabilities must retain their exact original header and
source identity under the managed worker lease.

Completion requires real local Ed25519 signing bound to TLS identity and current duty, source-bound
eligibility before signing, acceptable shard populations across the anchor's inclusion window,
CE134 same-input execution and returned hash/signature checks, third-guarantor grace, and CE135
verified distribution to the required current/next recipients. Omission remains disabled. Supporting
code, negative/source/lifetime tests, real multi-peer TLS evidence and ordinary activation belong
in the same coherent feature group. No report signature or complete runtime guarantee flow is
claimed by an anchor-only component.

## Implemented foundations and evidence

`work_anchors.nim` qualifies the exact original decoded header and posterior source map using
bounded corrected C(3), the shared reason-only GP anchor tuple/age rule, and retained sealed
child-header commitments. Current-head lookup roots use the trusted complete posterior map.
This qualification remains separate from package/pipeline eligibility and credential authority.
The new native suite and existing signed-report anchor suite pass;1000 success/refusal cycles
retain86848 and79792 bytes respectively, with equal before/after observations.

`work_signer.nim` loads only a bounded unencrypted PKCS8 Ed25519 private key matching the configured
leaf certificate. Paths are bounded before conversion. A maintained TLS parser never prompts,
rejects malformed leading framing, non-whitespace suffixes and duplicate keys, and commits seed
output only on complete success. Native scratch is wiped. Private file bytes go directly into
caller-wiped storage so read/limit failures create no intermediate secret heap copy. The opaque
owner exposes public identity only; no mutable seed alias or arbitrary-message signing API escapes.
Managed integration must load and retain this owner privately and freeze every alias until the
exact worker collection/join. Actual transport identity and duty must still be checked when used.
The native signer boundary suite passes, including late refusal without seed output, key mismatch,
path/file limits, malformed/encrypted/duplicate inputs and1000 cycles retaining87856 bytes.

The existing bounded-file consumer suite, application build, formatting and inventory checks pass.
Linux-target semantic checking of both new modules passes; this is not native Linux CI. Report
policy/pipeline eligibility, acceptable shard counts, actual signing, CE134/135 runtime flows and
operator activation remain unfinished. These foundations stay in the guarantee feature branch;
they are not a separate helper PR and do not establish full JAMNP-S completion.
