# Local management RPC

The [management listener](../src/management/server.nim) owns the local access policy.
The [private registry](../src/management/protocol.nim) owns methods and result schemas.
The [resource sampler](../src/management/resources.nim) owns observation scope and scan lifetime.

## Verification and limits

`make unit SUITE=management_http` covers method isolation in both directions, strict JSON,
HTTP framing refusals, notifications/batches, bounded bodies, actual local-socket requests,
permission checks, conflicting binds, explicit close/restart and ARC destructor cleanup.
`make unit SUITE=rpc` retains the existing public parser and method behavior.

This increment does not change the documented M1 framing milestone or establish complete
JAM serialization, STF or validator-operation parity.

`make unit SUITE=management_resources` checks current RSS/free-space observations, sparse-file
logical versus allocated size, multi-turn complete scans, memory mode, missing/non-flat/oversized
layouts, overflow refusal and 1000 abandoned scans with unchanged live ARC allocation.

## Application activation

Add `--with-management` to a server/client/mesh/download command. The default socket is
`<data-dir>/management/admin.sock`. Use `--management-socket /absolute/private-directory/admin.sock`
to override it. Public startup creates a missing parent and sets its mode to 0700.
An existing parent must already be owned by the effective user and private. Startup leaves
its permissions intact. The listener refuses existing endpoint paths. A path supplied alone
does not activate the listener. Invalid paths, duplicate controls and activation on non-service
commands are rejected.
Management startup failure rolls back already-started listeners and state through joined Services
cleanup. Normal close/destruction removes its own socket; a fresh start may reuse the path.

Example local request after creating an owned mode-0700 directory and enabling the service:

```sh
curl --unix-socket /absolute/private-directory/admin.sock \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"ragnarok_unsafe_clientInfo"}' \
  http://localhost/
```

The URL is HTTP framing for curl's Unix-socket transport, not a bound TCP address.

Services polls management once per dispatcher turn before any early return for proof,
preparation, disk-publication or maintenance leases. This registry reads only copied startup
metadata, allocator counters and bounded OS observations; it never reads or retains the worker's
canonical graph or database owner. Future management mutations must design their own safe host
scheduling and cannot infer permission to access a leased owner from this read-only method.

`make unit SUITE=app_options` verifies independent explicit activation and atomic refusal.
`make unit SUITE=management_services` verifies disabled/management-only startup, actual admin
responses, close/restart and rollback preserving an existing conflicting endpoint.
`make unit SUITE=rpc_state_proofs` sends a real management HTTP request while the proof worker
still owns its canonical lease, then verifies the exact original RPC pause remains active and
normal proof completion/1000-cycle ownership checks still pass. Native lowering rejection fixtures
cover both ManagementServer and ResourceSampler aggregate copies.

Linux integration regression: merged CI at `42112504144fab5e14cc1e62bb0d5f2594994b15`
exposed pinned-compiler lowering of the Linux RSS helper's deferred Boolean return. The helper
uses an explicit guard and result assignment so the existing RSS/resource tests compile on Linux.
No bounds, cleanup or overflow checks are removed. Cross-target semantic checks of resources,
the management server and Services cover the Linux import boundary; native Linux CI separately
verifies the affected modules, guard diagnostics and runtime suites. See the
[compiler observation](../docs/nimony-compatibility.md#deferred-linux-rss-return).
