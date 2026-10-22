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
