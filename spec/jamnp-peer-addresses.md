# JAMNP-S command endpoint configuration

Authority: JAMNP-S at `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, Required connectivity.
This layer integrates complete numeric endpoint routing into ordinary server/client, mesh,
legacy/current download, continuous sync and ancestor retrieval. It does not supply validator
membership, admission, epoch transitions or grid gossip.

`--net-bind IP` selects an explicit local address. `--net-peer-address IP` selects each remote
address in primary/additional `--net-peer` order; when used, supply exactly one per configured
peer. Numeric IPv4/IPv6 literals only, with one socket family across all configured peers and
any explicit bind. Wildcard remote addresses, DNS, mixed families and incomplete lists fail
before startup. Omitted addresses preserve existing isolated loopback proof commands. An
explicit remote without a bind uses a same-family wildcard local socket. Local bind alone
keeps the same-family loopback destination. RPC, management and UI controls are independent.

Every catalog, ancestor and dispatcher boundary copies complete addresses. Continuous sync
stores both local and remote addresses alongside the identity/certificate configuration and
reuses them on stale-source reconnect. Address selection grants no validator membership or
request authority; existing pinned TLS identity checks remain required.

Completion checks: named CLI normalization/refusal and failed-parse clearing; existing real
TLS catalog, ancestor and continuous-sync fixtures with explicit remote addresses; endpoint
transport TLS tests; production build covering command and reconnect call paths.

Telemetry dial observations copy the configured remote tuple; registration reports the selected
local bind (including wildcard) rather than inventing a loopback source.

The continuous-sync fixture also exercises stale-source replacement and disconnect/reconnect.
On Linux that fixture binds the server to127.0.0.2: a reconnect that forgets its stored address
cannot return to CaughtUp. Local macOS execution uses127.0.0.1; Linux-specific execution remains
a CI qualification. Catalog family/wildcard refusals precede even invalid certificate loading.
