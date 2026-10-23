# Complete state import from authenticated proof views

Scope: unchanged pinned complete-map Merklization, proof verification and full-state store contracts.
`ProofView` remains partial evidence. Its root, witness count and verified present facts alone never
supply completeness. `importProofState` requires an independently selected expected root, admits
all view traversal and temporary entry descriptor/payload copies, rebuilds the candidate complete
map through the existing bounded store, then requires its recomputed root to equal that expected root.
A proper witnessed subset returns `Incomplete` and exposes no candidate snapshot or partial prefix.

Verified absence contributes no fabricated entry. Present-empty values remain real map entries and
cannot be omitted without changing the recomputed root. Default views, wrong expected roots, local
copy refusal and original complete-store resource/backend failures remain distinct. Limits bound
absence lookups too; every complete-store policy is retained for subsequent writes/forks. Temporary
copy accounting is separate from the store's existing internal allocation/node/value policies.

Success owns an independent complete physical snapshot. It provides no current producer, original
logical compact identity, typed schema validity, canonical adoption, finality or root-discovery policy.
Consumers supply root trust independently and may subsequently run existing explicit typed/global/
supplied declaration qualification. No RPC method, storage/checkpoint/proof wire format, dependency
pin or light-mode backend changes. This is a checked completeness conversion, not an unchecked
partial-map constructor or a claim that light state in general is complete.

Native tests authenticate mixed embedded/regular/empty leaves, complete and proper-subset views,
missing present-empty entries, absence-only/empty-root views and wrong independent roots. Exact/short
copy/count/value policies refuse before hashing. Backend refusal/retry, independent mutation,
inherited store limits, source-scope retirement, strict result/privacy guards and 1,000 isolated ARC
cycles cover the new boundary. These are implemented-scope witnesses, not independent whole-STF
current-schema golden vectors or producer mutation certificates.
