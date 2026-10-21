# Accumulation account-write facts

Authority: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, current
host rows and eq:accpar. Modification membership identifies logical accounts;
parallel publication also needs the exact physical keys written by each account.
This layer retains those facts for genuine implication versions and leaves all
existing foreign publication gates intact.

Each fact binds a nominal service to a copied physical key. Capture all actual
account writes, including metadata, storage/request/preimage deletion, child
creation and both direct-transfer endpoints. Initial incoming transfers contribute
the recipient metadata key even at zero amount. Global chapters and provisions
add no account-write facts. Preserve successful no-op/restored writes and deleted
keys; read final presence/value only from the same producing context. Deduplicate
identical service/key pairs in deterministic first-touch order. Different owners
of one physical key remain distinct facts for later collision rejection.

An explicit `accountWriteFacts` ceiling bounds unique pairs; zero disables capture
and guarded queries return a typed disabled reason. Preflight the entire immutable
extension before applying account writes. Failed/default results expose no copied
fact or candidate state. Contexts and checkpoints share only immutable fixed facts,
without retaining chains of parent effects. Existing self-key/creation/deletion
publication limits remain independent and source-compatible.

Completion witnesses cover all account hosts and ownership sets, initial credits,
no-op/restoration/deletion, repeated keys, creation-child keys versus payer-only
modification membership, non-account preservation, default/disabled/index guards,
capacity/backend refusal, checkpoint selection, nominal units and ARC release.

## Local verification (2026-10-22)

The extended source-owned tracking suite and15 affected native host/publication
consumers pass with fresh 1,000-cycle ARC evidence. Witnesses check each actual
service/key binding, creation-child keys, all three expired-forget keys, absent
and restored values, copied descriptor independence, initial zero-credit keys,
checkpoint selection and independent unique-pair ceilings. All264 modules,
56 strict effect-result guards, physical-ordinal/capacity nominal rejections,
focused failure/verification harnesses and inventory pass. Evidence remains under
`build/account-write-facts-*` and
`build/tests/account-write-facts-guards/results.json`. Local macOS validation is
separate from Linux CI, complete JAM/PolkaVM host parity and parallel publication.

Next: current `fnpartitionxfers` scheduling, then accpar conflict annulment/account
selection and bound physical-write publication. The primary upstream discussion
in [PR539](https://github.com/gavofyork/graypaper/pull/539) confirms transfer
accumulation must be separated from supervisor execution. The exact pinned
partition equation is already present; this is an implementation gap, not a
new discrepancy or permission to invent another scheduling rule.
