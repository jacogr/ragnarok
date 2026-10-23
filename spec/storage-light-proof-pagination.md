# Bounded retained evidence pagination

This standalone storage feature adds immutable cursors over canonical retained proof evidence.
It extends [batch retrieval](storage-light-proof-batches.md) without changing V1 encoding,
proof semantics, chain/root trust, file selection or mutation policy. Application/startup
integration and consensus root selection remain gated. M1 framing completion remains distinct
from complete state serialization and full JAM client completion.

`proofCursor(snapshot)` returns an opaque `LightProofCursor` at the first canonical entry.
It retains the original image without copying bytes or materializing keys. Default snapshots
return `Uninitialized`. A cursor's `initialized` query is safe on defaults; `root` and
`finished` require initialization. Cursor fields are private and callers cannot manufacture
positions or combine one image's position with another image. Copies are independent immutable
traversal positions, so retry and branching are deterministic.

`readPage(cursor, LightProofPageLimits)` preflights the largest canonical prefix fitting the
item, individual-proof, aggregate-node and aggregate-raw-value ceilings. Count/extent/native
allocation bounds pass before allocating output. If a later entry cannot fit, the preceding
prefix succeeds with its continuation still pointing at that entry. If the first entry cannot
fit, or zero item allowance prevents nonterminal progress, it returns `LimitExceeded` without
a page or advanced cursor. Callers may retry with larger limits. No successful nonterminal
page is empty. At the end, even zero ceilings return a successful empty terminal page.
Default cursors return `Uninitialized`.

A successful opaque page exposes guarded `len`, `proofs` and `nextCursor` accessors. `proofs`
returns independently mutable owned output; it never exposes retained page buffers. The next
cursor retains the same original complete root and image. Present empty values, authenticated
absence and zero-node empty-root evidence remain distinct proof semantics. Enumeration never
invents evidence for unknown keys or recomputes a root from partial contents.

Preflight examines only bounded entry headers plus at most the first non-fitting header;
a second bounded pass copies selected proof bytes. No whole-image scan, retained index,
hashing or IO is required per page. Work is O(selected entries and bytes), with constant
position state and page-sized detached output. The caller controls retained cursor/page counts
and any additional copies from repeated `proofs` access. A retained cursor survives image
forgetting, file-owner closure and file removal; it does not acquire new freshness or durability.

Completion checks cover page sizes one through six over five retained queries; canonical order,
retry, branching, root identity, exact/short aggregate and per-proof limits, maximal uint64
policies, nonterminal zero allowances, terminal retries, defaults, empty images and zero-node
absence. Exact complete-trie transport and verification at an independently calculated root
check every proof. Mutable page extraction, temporary owned restoration, forgetting, actual
file reopen/close/removal and 1,000 success/failure ARC cycles exercise retained ownership.
Dynamic result/cursor/page misuse guards and private-field compiler rejections prevent defaults
or external construction from authorizing continuation or evidence extraction.

## Local verification

The new pagination and affected batch/single-query suites pass in checked native builds.
Page sizes one through six, exact/short/maximal policies, canonical proof/verifier comparisons,
zero provider calls, independent mutation, retry/progress, terminal/default/zero-node cases,
owned restoration and actual file retirement pass. The 1,000 success/failure lifetimes hold
22,048 occupied ARC bytes before/after. Thirty-two snapshot runtime guards, nine selected
positive controls and five new cursor/page privacy rejections pass. Formatting and inventory
pass. Local evidence does not claim exact-head Linux CI or power-loss qualification.
