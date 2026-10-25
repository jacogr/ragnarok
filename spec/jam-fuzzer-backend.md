# Ephemeral JAM fuzzer state backend

Authority is the pinned fuzzer-v1 Initialize/ImportBlock/GetState contract and the
unchanged current Gray Paper implementation. Initialize supplies an explicit test
seed, not independently authenticated production genesis. The complete supplied
map is retained and committed exactly as received, independently of the header's
prior-state field. Production bootstrap and durable state are not modified.

The initial backend path supports a linear session. Explicit fork-state policy
now also supports the pinned depth-one sibling workflow and negotiated initial
hash/slot ancestry with actual child-header lookup-root evidence. Initialization and exact-hash state queries are supported
for any structurally owned bounded seed. Actual import uses the existing current
candidate pipeline with explicit host Parameters and resource policies, and installs
only a genuine prepared current update. If the seed cannot satisfy that pipeline's
existing application context requirements, import reports a local SeedContextFailure;
it never repairs the seed or returns a fabricated consensus rejection. Supporting
arbitrary genesis-like header/time pairing in actual imports remains a separate
state admission change.

Complete maps are available for the seed and bounded retained chain history.
Initial membership and actual full headers generated within this session are
retained in immutable branch contexts under explicit count/byte ceilings. Lookup
roots require the GP child-header predicate; initial membership alone cannot prove
a root. Missing/evicted context
is a local failure, not an import Error. Each session owns a private ephemeral
chain; reset discards all seed, chain and header owners.

Completion tests compare actual backend imports and complete GetState maps with
independently calculated current-profile STF observations; default, duplicate seed,
unknown state and actual candidate refusals remain typed. The backend returns the
original failed candidate stage for explicit protocol-versus-internal classification
by its caller. No generic candidate failure is automatically encoded as Error.

Observed local verification passed two independent current-profile chains with 20
signed imports and complete returned map comparisons. The original seed remains
queryable after rolling history eviction; a deliberately wrong prior-state root
returns the genuine failed candidate stage and leaves state unchanged.

Every backend chain is explicitly fuzz-only. That immutable domain survives
head/finality advances, exact-view comparisons and report certificates. Both
legacy and current chain producers reject a fuzz report certificate against an
ordinary view; prepared updates cannot cross domains. This keeps supplied seed
assumptions from becoming production publication authority.
