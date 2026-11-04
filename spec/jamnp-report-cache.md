# Retained checked work reports

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, CE136 and the existing
complete hash/profile [report-verification contract](jamnp-report-retrieval.md).
No dependency, toolchain or specification pin changes.

`ApplicationNode` retains successfully checked outbound Report responses independently of
canonical C10/C14 availability. Incoming matching CE136 requests can use that detached content
without canonical access, including while a foreign Services worker is Done but still owns its
exclusive graph/RPC lease. A report hash binds content; caching establishes no guarantee,
execution, judgment or availability authority. Other read methods keep their own canonical rules.

`ReportCache` is a main-thread value owner of private frozen request-bound replies. It stores at
most64 reports and2MiB of logical framed wire bytes, at most64KiB per entry. Fixed row capacity
and checked least-recently-used replacement bound both count and bytes before retention.
Only a complete Report-kind `CheckedReadReply` can populate it; mutable peer bytes or arbitrary
hashes cannot bypass the verifier. Duplicates update recency without adding storage. Age counters
never wrap. Retention refusal does not fail an otherwise successful checked read. Allocator
capacity, fixed metadata and transient encoding/response copies are outside the logical byte sum.
No complete map, header graph, native pointer or worker alias is retained in the cache.

The application host inserts only after collecting its exact completed, uncancelled successful
verification. Cached replies still require the native ticket's live peer generation/serial and
exact request method/hash. The host can service at most one filtered cached report while the
canonical gate is unavailable, and its normal admission turn can service another if a collected
owned job reopens the gate in the same poll. Native output credits and existing per-peer/global
read, selector and physical-close reservations apply unchanged. The host clears cache ownership
after native retirement during explicit close; reopening starts empty.

A miss must neither become a successful empty response nor block cached siblings behind a frozen
graph. `NodeService.takeRead(kind)` filters without taking unrelated work. `deferRead` returns a
freshly inspected complete claim to admission, immediately revoking its old serial. Re-admission
creates a new nonwrapping serial. Deferral restores the activity timestamp from before the claim,
so repeated cache probes do not extend the original inactivity or absolute deadline. A responding,
reset, retired, stale or foreign claim cannot be deferred. Canonical fallback still acquires the
ordinary Services lease when the graph gate opens.

Verification:

- `jamnp_report_cache`: independent complete checked reports, duplicate/LRU/count limits,
  large authorization traces exercising the byte limit before count capacity, immutable copies,
  explicit clear and1000 isolated insert/find/clear cycles with balanced ARC memory.
- Actual TLS claim deferral: old ticket immediately becomes nonlive, another kind's filtered read
  cannot consume it, fresh re-admission responds correctly, stale response cannot close its new
  incarnation and an already responding route cannot be deferred.
- Actual application TLS: canonical state has no report; checked outbound acquisition fills the
  cache; cached service completes while a foreign state worker remains Done; a deferred unknown
  request does not block a known sibling; synthetic29s probing followed by31s still resets the
  original30s inactive request; host close preserves the foreign lease, clears the cache and
  reopening falls back to canonical unavailability/reset.
- Canonical report and node-service regression suites, refreshed actual ApplicationNode duplicate
  lowering rejection, formatter and application build cover affected ownership/consumer paths.

Distribution and judgment runtime policy remains separate. This layer supplies checked-content
retention and detached service for subsequent audit recovery, without making a cached report
eligible for block inclusion or claiming full auditor operation.
