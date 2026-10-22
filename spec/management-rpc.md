# Local management RPC

The management API is a Ragnarök extension, independent of JAM/JIP public RPC. It uses
HTTP/1.1 over a Unix domain socket and a separate JSON-RPC method registry. No public WS
methods are registered here; no management methods are registered in WS RPC. This is optional
and disabled unless explicitly selected. UI, state and WS activation do not imply management.

## Access and transport

The operator supplies an absolute socket path of at most 103 UTF-8 bytes in an existing directory
owned by the effective process user with no group/other permissions (normally mode 0700).
The directory must have trusted ancestry. The listener creates a mode-0600 socket before
listening. Filesystem access is the authorization boundary: only that OS user and privileged OS
administrators can connect. There is no TCP listener, CORS support or bearer token in this scope.
Existing socket/file paths are refused without removal. After a crash, the operator must verify and
remove a stale socket. Normal shutdown removes only the device/inode this listener created.

POST `/` requires HTTP/1.1, Host, `Content-Type: application/json` (optionally
`; charset=utf-8`) and one decimal Content-Length. Every reply closes the connection and
includes `Cache-Control: no-store`. Notifications yield HTTP 204; JSON-RPC responses yield HTTP
200. Transport errors produce empty HTTP 4xx responses. GET, upgrades, Origin, Expect,
Content-Encoding, Transfer-Encoding, duplicate headers, folded headers and pipelined suffixes are
refused. A late second request cannot execute: the connection accepts one request and closes.

Limits: four connections; 4096 header bytes; 8192 request-body bytes; 8192 reply-body bytes;
eight JSON nesting levels; 256 JSON tokens; sixteen batch members. Each connection has an
absolute five-second deadline. Each dispatcher turn accepts at most one connection and performs
at most one nonblocking read/write per slot. Socket descriptors are close-on-exec and suppress
SIGPIPE. No thread is created per connection or request.

Strict UTF-8 and JSON tokenization are shared neutral plumbing with public RPC. Method lookup,
request state, connections and access policy are separate. Duplicate envelope fields are invalid.
JSON-RPC string/numeric/null IDs retain their exact value. Empty positional/named params are
accepted; malformed/nonempty parameters yield -32602. Valid notifications emit no JSON reply.

## Initial method

`ragnarok_unsafe_clientInfo()` returns a deliberately small admin-only object:

- `version`, `revision`: embedded application identity.
- `pid`, `effectiveUid`: local process identity.
- `role`, `managementSocket`: selected role and private endpoint.
- `chainPath`, `databasePath`, `stateEnabled`: startup configuration; no implicit path is invented.

Paths are administrative information. The schema contains no private keys, seeds, passphrases,
certificate contents or arbitrary environment variables. This method performs no key management.
Future key generation/import/activation requires separately designed management methods.

## Verification and limits

`make unit SUITE=management_http` covers method isolation in both directions, strict JSON,
HTTP framing refusals, notifications/batches, bounded bodies, actual local-socket requests,
permission checks, conflicting binds, explicit close/restart and ARC destructor cleanup.
`make unit SUITE=rpc` retains the existing public parser and method behavior.

This increment does not change the documented M1 framing milestone or establish complete
JAM serialization, STF or validator-operation parity.

## Resource observations

`resources.memory` reports `residentBytes` for the entire process (current Mach task resident size
on macOS, `/proc/self/statm` resident pages on Linux), and `dispatcherHeapOccupiedBytes` /
`dispatcherHeapReservedBytes` for the calling Nimony thread's allocator. Heap counters exclude
worker heaps and foreign-library allocations; process RSS includes resident memory across threads.
These are different scopes, not additive components of a total. RSS failures yield null.

`resources.filesystem` names the database filesystem (or the management directory for a memory
backend). `totalBytes`, `freeBytes` and `availableBytes` come from statvfs: free includes blocks
reserved for privileged use; available is what an unprivileged process can normally allocate.
Failed metadata queries yield null, never an apparent zero-capacity volume. These are local OS
observations, not a promise that a subsequent database write will succeed.

`resources.database` exposes `enabled`, `status`, `logicalBytes`, `allocatedBytes`, `files`,
and `sampleAgeMs`. Memory backends use zero database disk bytes and status `memory`.
Legacy journal layout counts its selected database file. Managed layout counts all regular files
in its flat directory, including manifests, locks, staged/retired files; it does not count unrelated
files elsewhere. Logical bytes sum file lengths; allocated bytes sum OS st_blocks times 512.
Sparse files can therefore have smaller allocation than length. Shared/cloned/compressed filesystem
storage can make these observations differ from uniquely attributable physical-device consumption.
Directory metadata and filesystem overhead are outside file allocation totals; hard-linked directory
entries are counted individually.

RSS/heap/filesystem values refresh at most once per second outside request dispatch. Database scans
start at most every ten seconds, inspect at most sixteen directory entries per dispatcher turn, and
stop after 4096 entries including dot entries. A completed sample remains available with its age
while a refresh runs (`sampling`). Before the first complete scan, sizes are null. IO errors,
overflow, symlinks, nested directories or entry-limit refusal invalidate the sample and produce
null sizes with a diagnostic status. No recursion or database-owner access occurs. A scan is an
observation across turns, not a transactional snapshot; concurrent appends/compaction can change
sizes during it. A later sample refreshes the result.

`make unit SUITE=management_resources` checks current RSS/free-space observations, sparse-file
logical versus allocated size, multi-turn complete scans, memory mode, missing/non-flat/oversized
layouts, overflow refusal and 1000 abandoned scans with unchanged live ARC allocation.
