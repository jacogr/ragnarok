# Validator requested-preimage possession gossip

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, CE142/143 and its
previous/current/next validator grid. No pin or dependency changes.

After requested content passes exact advertised length and full-hash verification, propagate
possession only to authenticated validator neighbours under the effective epoch-gated topology.
Keep automatic gossip independent of public checked requests and private blob acquisition. A
successful bare-FIN acknowledgment records delivery only; it establishes no remote state or GP
inclusion authority. Recheck local retained possession and current canonical outstanding-request
state before each new transmission; canonical withdrawal or cache eviction retires the intent.

Bound retention to eight service/hash/length intents, at most3581 peer-generation observations per
intent and one active announcement. Rotate rows and peer discovery; limit work to one recipient
per turn. A peer generation is announced at most once after success, with finite delayed retry
for transient refusal. New authenticated generations receive fresh delivery. Non-validator local
nodes and non-grid/non-validator recipients never gain gossip privilege from a certificate or
an ordinary UP0 connection. Physical request quotas, generation-bound cancellation and close
remain owned by NodeService; no CPU/canonical work occurs in native callbacks.

Completion witnesses: actual checked acquisition followed by a literal CE142 announcement to a
third authenticated grid validator; no announcement before possession or to ineligible peers;
exact bare-FIN receipt, duplicate suppression, delayed retries, generation renewal, cache/request
retirement, bounded pressure and explicit close without affecting foreign worker leases. Preserve
full/light storage separation and the prior announcement/acquisition regression evidence.

Ownership and scheduling:

- `PreimageGossip` owns only copied claim facts, acyclic peer-generation namespaces and one exact
  `NodeRequestTicket`. It has no canonical graph, native callback storage or CPU ticket. Close
  cancels that ticket before dropping row storage; duplication is unavailable. Candidate tokens
  bind a private scheduler namespace plus nonwrapping row generation, so foreign, evicted and
  reopened candidates cannot affect current intent.
- Successful delivery suppresses duplicates on the same authenticated generation. A fresh
  connection gets its own observation even if the validator key is unchanged. There are at most
  three admitted attempts per generation, separated by30s after failure. Native capacity refusal
  consumes no attempt. Every row retains at most3581 observations; a stale generation yields its
  slot before a fresh observation is added. At most one row/recipient is dispatched per host turn.
- `NodeService.preimageNeighbour` requires both validator roles and accepted grid membership.
  Ordinary UP0 eligibility for a non-validator never authorizes gossip. Existing epoch/finality
  gating continues to own when a topology becomes effective.
- Verified private fetch completion records service-specific notifications, even when services
  share one blob owner. Cached valid announcements can add another requested service namespace.
  A checked local publisher's acknowledged recipient is already delivered and is not announced
  again. Public checked-request capacity remains independent of gossip and automatic acquisition.
- `ApplicationNode.dispatchGossip` performs fresh retained-possession and exact canonical request
  checks in a staging activation. Every temporary canonical alias retires on return before the
  next CPU admission. Gossip acknowledgment polling remains safe during foreign canonical leases.
  Cache eviction or current request refusal retires the exact candidate; no partial store or remote
  claim is used as canonical request authority.

Observed verification:

- `jamnp_preimage_gossip` passed independent literal three-party TLS witnesses. Non-validator B
  introduces a requested blob to validator A; only after full verification does grid validator C
  receive CE142 and acknowledge with bare FIN. C uses its own generated/pinned TLS identity.
- Duplicates do not reannounce to the same generation; C's authenticated reconnect receives fresh
  possession. A real non-grid validator receives no gossip. Corrupt acquisition produces none.
  A withheld acknowledgment FIN keeps exactly one operation active. Malformed E4 acknowledgments
  cause at most three attempts across synthetic31s/62s/100s clocks, with no successful delivery.
- Two services requesting the same content get distinct service-bound announcements with one
  verified blob/cache entry and one remote fetch. Nine subsequent checked content fetches evict
  the original blob and retire its gossip intent. Retained CE143 content remains serviceable
  during a foreign Done lease; explicit close, including an active withheld FIN, preserves that
  foreign worker's exact collection authority.
- Pure capacity, duplicate, successful withdrawal and foreign/evicted/reopened candidate checks
  passed. One thousand scheduler create/offer/close cycles retained368 occupied ARC bytes before
  and after. Actual lowering rejected copies of `PreimageGossip` and containing `ApplicationNode`.
- The prior `jamnp_preimage_announcements` and `jamnp_report_cache` suites passed with their fresh
  balanced1000-cycle ARC evidence. `make format-check` and `make build` passed with checked ARC/Clang thin-LTO application settings.

This layer connects checked network acquisition, cached valid introductions and checked local
publishing to grid delivery. Canonical ingestion/adoption integration and the other JAMNP-S
protocol families remain separate outstanding work; this is not a full validator-completion claim.
