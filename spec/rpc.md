# WebSocket JSON-RPC foundation

References: [JIP-2 at 14b55b8135285c2239a5ada8a86337907bc17108](https://github.com/polkadot-fellows/JIPs/blob/14b55b8135285c2239a5ada8a86337907bc17108/JIP-2.md),
Protocol and Methods; [JSON-RPC 2.0](https://www.jsonrpc.org/specification), updated 2013-01-04,
sections 4–6; [RFC 6455](https://www.rfc-editor.org/rfc/rfc6455), sections 4–7.

## Usage and implemented scope

Append `--rpc-port 19800` to an existing `build/ragnarok server`, `client`, or `mesh` invocation.
The endpoint is `ws://127.0.0.1:19800/`. RPC is disabled when the flag is absent; an invalid port,
duplicate flag, or failed listener bind fails startup. It is independent of `--telemetry` / `--chain`.
The endpoint lives for the lifetime of the existing proof-peer session. It adds no standalone
node daemon or chain execution. An explicit genesis pair initializes the read-only view below.

Send a WebSocket text message:

```json
{"jsonrpc":"2.0","method":"ragnarok_clientInfo","params":[],"id":1}
```

`ragnarok_clientInfo()` reports client diagnostics. The result includes:

- Implementation name, development version, pinned compiler version, Gray Paper version,
  target OS and architecture, and peer command role (`server`, `client`, or `mesh`).
- Milliseconds since RPC startup, observed connected peer count, and occupied/reserved ARC
  allocator bytes (not process RSS). Mesh counts its logical remote once across two role engines.
- `bestBlock`: the configured genesis descriptor when imported, otherwise null.
- `chain` and `finalizedBlock`: null; no network identity or finalization view is published yet.
- RPC transport, loopback address, port, available method names, subscription availability,
  maximum message bytes and batch size.

No private keys, environment variables, command-line secrets or filesystem paths are exposed.
Ragnarok-specific extensions use `ragnarok_`. Standard JIP-2 methods retain their specified
unprefixed names. `parameters()`, `bestBlock()`, `parent(hash)`, `stateRoot(hash)`, `statistics(hash)`, `listServices(hash)`, `beefyRoot(hash)`, `workReport(hash)` and the service queries below are implemented; other JIP-2 chain methods
and subscriptions remain unavailable and return JSON-RPC `-32601` for identified requests.
This is not complete JIP-2 support. In particular an
unavailable block database cannot be reported as an empty chain or a successful subscription.

Queries use an immutable genesis snapshot imported independently of telemetry metadata.
Advancing heads, finalized queries and subscriptions still require block import and update events.

## `parameters()` and startup configuration

Append `--chain /path/to/chain.json` alongside `--rpc-port 19800`. `--chain` may serve RPC
without telemetry; telemetry still requires it. Startup reads one bounded file snapshot for both
services. RPC requires one `protocol_parameters` string with exactly 244 unprefixed hexadecimal
characters, decoding the 122-byte GP 0.8.0 `fetch(0)` tuple. Both hex letter cases are accepted.
Missing, malformed, duplicate, truncated or extended explicit configuration fails startup before
opening the RPC listener. With no `--chain`, diagnostics remain available and `parameters()`
returns JIP-2 error `0` (“Chain parameters unavailable; configure --chain”). No defaults are inferred.

Requests take no arguments (`params: []` or omitted). The result is `{"V1": {...}}` with all
33 JIP-2 field names. The 29 encoded fields retain their exact unsigned integer values, including
64-bit values above JSON clients' floating-point precision. Clients must use lossless JSON number
handling when needed. Invalid arguments use `-32602`; notifications remain silent.

**Temporary zero placeholders:** `tickets_attempts_number`, `val_count`, `basic_piece_len`, and
`segment_piece_count` return **0 to mean “not yet derived.” These are not actual chain values.**
This is an explicitly documented incomplete implementation of their JIP-2 meanings, selected by
the maintainer; zero must not be used to size validator sets, produce tickets or encode data.
These values require live state, which this proof peer does not yet maintain:

- `val_count` must come from the relevant validator roster, not `3 * core_count` or a test profile.
- `tickets_attempts_number` must follow GP 0.8.0 Safrole's `ceil(2 * epoch_period / pending_validator_count)`.
- Erasure-coding sizes must follow GP 0.8.0's validator-dependent original-shard count and fixed
  4,104-byte segment, with the JIP-2 mapping specified when live-state support is added.

References: JIP-2 `parameters()`/Errors at the revision above; [JIP-4](https://github.com/polkadot-fellows/JIPs/blob/14b55b8135285c2239a5ada8a86337907bc17108/JIP-4.md)
`protocol_parameters`; GP 0.8.0 at `07f041dabd073f9018b418e9ee72e79dd2185401`, Appendix B
`fetch(0)` (`text/pvm_invocations.tex`), Safrole `valcount`/`ticketsextrinsic`, and erasure coding
`ecoriginalshards`. The GP fetch tuple has 29 fields; it does not encode these four state-dependent
values. JIP-4's linked historical fetch encoding is not accepted as an alternate byte layout.

Configuration validation here covers strict JSON, the exact GP tuple, and basic usability:
core count at least two, nonzero epoch/slot/rotation periods, and epoch tail no later than the epoch
end. Parameter validation alone does **not** import or validate genesis state, initialize a live chain, or establish all
cross-field consensus constraints. Unknown chainspec fields are syntax-checked but not interpreted.
Parsing is bounded to 8 MiB, 32 nesting levels, 262,144 values and 64 root members. The immutable
parameter owner retains only fixed-size integers; file edits after startup require restarting the node.
The existing proof-peer codecs still receive their own explicit configurations; this increment does
not silently reconfigure consensus execution or replace those contracts.

## Genesis-only chain queries

When both JIP-4 `genesis_header` and `genesis_state` are supplied, startup imports one immutable
configured genesis view. Omitting both preserves parameters-only operation. Supplying only one,
or an invalid pair, fails RPC startup before opening the listener. Telemetry-only operation retains
its existing metadata extraction contract.

- `bestBlock()` returns the configured genesis header's Blake2b-256 hash and slot. This is the only
  known head; it does not advance or imply synchronization or finalization.
- `stateRoot(header_hash)` returns the computed root of the supplied genesis state map when the
  hash matches genesis. It is the posterior root, **not** the header's prior-state-root field.
- `parent(header_hash)` returns JIP-2 error `1`: no parent block descriptor is available, including
  for genesis. The genesis header's parent bytes do not provide a parent's slot or prove a block exists.
- Unknown block hashes return error `1`, with the requested padded Base64 hash in `error.data`.
  With no genesis view, `bestBlock()` returns error `0`; hash queries return error `1`.

Both hash methods require exactly one canonical padded Base64 string decoding to 32 bytes.
Malformed hashes or argument lists return `-32602`. `bestBlock` takes no arguments. Existing
batch and notification behavior applies. Finalized queries and all subscriptions remain unsupported.
The four parameter placeholders remain unchanged in this increment; deriving them is separate work.

The genesis loader checks strict bounded JSON, exact 31-byte hex keys, hex values, duplicate decoded
keys (including case aliases), header framing/complete consumption, active roster C(8), and timeslot
C(11). Header author range uses that roster, and the header slot must equal C(11). The existing
complete-map state store owns a copied immutable mapping and computes its Merkle root. The header
hash includes the complete sealed header. Input files are never reread by a query.

**Trust and validation limits:** the operator-supplied genesis header and map are the trust anchor.
The map is treated as the complete configured serialized mapping. Import does not establish
that all required chapters exist or are semantically valid, verify genesis signatures/key material,
execute a block, check consensus invariants, or compare against an independently trusted posterior
root. C(8)/C(11) checks supply structural decoding context, not whole-genesis consensus validation.
No light-state proof or partial-map import is supported; this is a complete-map in-memory view.

Resource ceilings supplement the existing 8 MiB chainspec policy: 256 KiB header, 16,384 entries,
4 MiB per value and aggregate decoded values, and 1,048,576 trie nodes. Merklization happens once
at startup, before serving, not in the dispatcher. Ownership is acyclic; dropping the server releases
its retained snapshot. There is no persistent database, block import, fork choice or finality tracking.

References: pinned JIP-2 Common types, Errors, `bestBlock`, `parent` and `stateRoot`; pinned JIP-4
`genesis_header`/`genesis_state`; GP 0.8.0 Header (agreed genesis header/state), Appendix C header
serialization and state Merklization. The synthetic test fixture is deliberately structural test data,
not a deployable network genesis; expected hash/root values come from Python hashlib and the existing
independent trie reference. Native and live WS tests cover exact results, absent/unknown data,
malformed pairs and hashes, shared telemetry startup, and file mutation after capture.

## Genesis-only service queries

The pinned JIP-2 `serviceData(header_hash, service_id)`,
`serviceValue(header_hash, service_id, key)` and
`servicePreimage(header_hash, service_id, hash)` read the same retained genesis map.
The block and preimage hashes are canonical padded Base64 encoding exactly 32 bytes.
Service IDs use unsigned JSON integer syntax in the uint32 range; storage keys are canonical
padded Base64, including the empty string, with at most 4,096 decoded bytes.

`serviceData` returns the serialized C(255, service) record: the existing GP 0.8.0
version-zero 89-byte metadata layout. Storage and preimage queries use the maintained
state-key constructors and require an existing, structurally valid account record.
Preimages are checked against their Blake2b-256 hash before returning them. These local
checks do not establish whole-genesis consensus validity. See [service state serialization](state-service-values.md)
and the pinned GP 0.8.0 state Merklization/account definitions referenced there.

Results are Base64 byte strings. Missing accounts or entries return `null`; a present empty
value returns `""`. Unknown blocks return JIP-2 error `1` with the requested hash in
`error.data`. Malformed arguments return `-32602`; malformed metadata, inconsistent preimages,
backend failures and output-budget exhaustion return error `0`. Notifications remain silent.

Each returned raw value is limited to 32 KiB. A batch shares a 65,535-byte encoded response
budget, reserving space for every request's exact escaped ID and error envelope before reading
values. A value that fits alone may receive error `0` in a batch; callers can retry it alone.
Values are never truncated. Snapshot-owned views are immutable, and copying/hashing follows
size checks. No persistent service database, post-genesis state or subscription is added.

Synthetic service fixtures cover metadata, absent and empty values, preimages, uint32 boundaries,
and output limits. Expected namespace keys, hashes and roots were independently generated with
Python hashlib and the existing trie reference. Native tests also cover malformed arguments,
orphan entries, inconsistent preimages and owner isolation. Live WebSocket tests check exact
results and bounded batches with IDs whose escaping expands their encoded size.

## Genesis-only preimage request histories

`serviceRequest(header_hash, id, hash, len)` follows the pinned JIP-2 method, using the maintained
GP 0.8.0 `C(service, E4(length) || hash)` key constructor and request-history decoder. Hashes use
the same canonical 32-byte Base64 format; service ID and advertised length use unsigned JSON
integer syntax across the full uint32 range. No allocation depends on the advertised length.

A missing account or key returns `null`; a present requested-but-unprovided history returns `[]`.
A provided history returns 1–3 exact unsigned slot numbers: supplied, forgotten, requested again.
The entire value must be a canonical count plus up to three E4 slots (at most 13 bytes). Bad counts,
truncated slots, suffixes and invalid account metadata return error `0`. Unknown blocks return
error `1`; invalid arguments return `-32602`. Existing notification and shared batch-budget rules apply.
These are structural reads of the retained snapshot, not checks of chronology, provision validity
or cross-map account invariants. No subscription, submission or state update is added.

**Pinned namespace limitation:** lengths `4294967294` and `4294967295` share serialized key
namespaces with preimages and storage under GP 0.8.0. A missing key still returns `null`, but a
present key returns error `0` with an explicit ambiguity message, even if its bytes decode as a
history. The map alone cannot identify their logical origin. This is an RPC information limit,
not a new invalid-length rule: the full E4 parser/codec domain, specification pins, duplicate-key
policy and pending [request namespace](request-namespace.md) migration remain unchanged.

Native tests freeze independently computed request keys and cover all four history shapes,
zero/max slots, full length parsing, malformed histories, every truncated three-slot prefix,
present/absent marker keys, missing accounts, batches, notifications and repeated ARC cleanup.
The live WebSocket harness checks exact histories and errors after the chainspec file has changed.
A `rpc_` compiler probe protects the result discriminator. See [request serialization](state-requests.md)
for the pinned GP equations and codec ownership contract.

## Genesis-only activity statistics

`statistics(header_hash)` follows the pinned JIP-2 method of that name and returns the exact
C(13) bytes as padded Base64. It requires one canonical 32-byte header hash. An unknown block
returns error `1` with that hash in `error.data`; invalid arguments return `-32602`.
Missing or malformed statistics/context return error `0`, never `null` or fabricated zero activity.

Before returning bytes, `src/chain/statistics.nim` validates the complete chapter with the existing
[activity statistics codec](state-statistics.md), including the accepted compact gas encoding.
Decoding uses the core count retained with genesis and the actual C(8)/C(9) validator populations;
these populations may differ after resizing. Both rosters and statistics must decode exactly,
with no trailing bytes. This is structural validation, not verification of activity against blocks.

The same 32 KiB raw-blob and 65,535-byte aggregate reply limits apply. Oversized values or a batch
with insufficient space return error `0` without truncation. Roster copies are independently
bounded to 1 MiB each; decoder populations and service counts also obey their existing limits.
Queries read only the immutable startup snapshot. `subscribeStatistics` remains unavailable.

Native tests cover independent literal bytes (including uint64-max compact gas), all truncated
chapter prefixes, malformed counts/dictionaries, differing roster populations, missing data,
response limits, notifications, batches and repeated ARC cleanup. The live WS harness checks
exact statistics from the frozen service fixture after the source file has changed.

## Genesis-only service discovery

`listServices(header_hash)` follows the pinned JIP-2 best-effort discovery method. It returns
an array of unsigned service IDs in ascending numeric order, including ID zero when present.
The supplied hash must identify the configured genesis snapshot. Unknown blocks return error `1`
with the requested hash in `error.data`; malformed hashes or argument lists return `-32602`.
A known snapshot with no discoverable accounts returns `[]`.

Discovery runs once at genesis capture. It recognizes only exact GP 0.8.0 C(255, service) keys
with complete supported version-zero metadata, using the existing account decoder. Malformed,
truncated, extended or unsupported metadata is omitted. Storage/preimage entries do not establish
an account, and matching only the first key byte is insufficient. This best-effort list describes
the structurally valid accounts found in the operator-supplied map; it is not proof of account
eligibility, activity or whole-state consensus validity. See [service metadata](state-accounts.md)
and the pinned JIP-2 `listServices` definition.

The private list contains copied scalar IDs and retains no source aliases. It is bounded by the
existing 16,384-entry genesis map limit; duplicate map keys are rejected before discovery.
Requests do not scan the map or decode metadata. Rendering shares the 65,535-byte reply budget:
a list too large for its single/batch allowance returns error `0`, never a silently truncated list.
The protocol has no pagination parameter, and subscriptions remain unavailable.

Native tests cover numeric versus serialized-key ordering, zero/uint32-max IDs, exact key shape,
malformed records, orphan keys, empty lists, unknown blocks, immutable extraction, notifications,
batches and large-list response limits. Live WebSocket tests verify discovery from the frozen
service map after startup file mutation. A `rpc_` compiler probe protects the private ID sequence.

## Protocol and bounds

Only WebSocket version 13 is supported; HTTP is used solely for the RFC 6455 upgrade handshake.
POST bodies are never dispatched as RPC. The endpoint accepts local non-browser tooling:
Origin-bearing requests are rejected. TLS, remote binding, browser Origin configuration,
compression, binary messages and subprotocol negotiation are outside this increment.

Input JSON is validated strictly before dispatch, including number spelling, object keys,
escapes, surrogate pairs, trailing data and duplicate envelope members. Parameters are positional
arrays or omitted. IDs preserve their numeric lexemes or decoded string values without machine
integer/float narrowing. Parse errors use `-32700`, invalid envelopes/batches `-32600`, unavailable
methods `-32601`, and invalid parameters `-32602`. Valid notifications never receive replies,
including errors and notification-only batches.

Parsing uses the pinned Nimony `std/parsejson` streaming API, which also underlies `std/json`.
The tree API converts numbers to integers/floats (including a lossy float fallback for large
integers), so RPC uses streaming numeric lexemes to preserve IDs. The stdlib owns structural
parsing and string decoding; a lexical policy rejects its non-JSON extensions (comments,
trailing commas, permissive escapes/numbers). The event adapter enforces string object keys,
a single root and resource limits before retaining each event. Decoded strings are checked
for valid UTF-8, and stdlib error state is checked even when it emits a string event.

The server accepts masked client frames, fragmented text with interleaved ping/pong, and valid
close handshakes. UTF-8 validation covers the complete reassembled text, so a fragment may split
one Unicode scalar. Server frames are unmasked. Framing violations close with 1002, binary data
with 1003, invalid UTF-8 with 1007, and cumulative oversized messages with 1009. Extended 64-bit
frame lengths are rejected because their canonical minimum exceeds the configured limit.

Resource limits are eight connections, 4 KiB upgrade headers, 16 KiB messages, 16 nesting levels,
2048 JSON values and 16 requests per batch. Input/output is owned per connection. Each dispatcher
turn performs at most one accept and one read (4 KiB), frame dispatch and write per slot. Responses
share a 65,535-byte budget, including escaped request IDs, envelopes and batch punctuation.
Responses that exceed their remaining allowance return a reserved error envelope.
Backpressure pauses reads until the outstanding response is delivered. Handshakes, partial
messages, fragmented messages and queued writes have five-second budgets; idle upgraded
connections expire after thirty seconds. Ping/pong cannot extend a fragmented message's budget.

The listener/connection composite is explicitly non-copyable. ARC destruction and explicit close
retire native descriptors and owned strings; no foreign callback borrows RPC data. Mesh borrows
one stable stack owner only during its synchronous dispatcher loop. All sockets are nonblocking
and close-on-exec, and SIGPIPE is suppressed per socket/send.

## Verification

`tests/unit/crypto/test_rpc.nim` covers JSON-RPC envelopes, batches, notifications, strict malformed
JSON, numeric/string IDs, Unicode boundaries, RFC 6455's published handshake example, every
truncated frame prefix, masking/length/control errors, fragmentation and repeated ARC destruction.
It is registered in `make check-unit`. `make check-guards` includes a lowering-level server-copy
rejection probe. `make check-modules` discovers the new modules automatically.

`tests/rpc_checks.py`, required by `make check-e2e`, independently encodes/decodes WebSocket
frames against the actual peer process. It checks upgrade verification, requests, notifications,
batches, malformed JSON, fragmented text with ping/pong, close handling, unmasked rejection,
HTTP POST rejection, saturated handshake expiry, three concurrent QUIC clients and clean shutdown.
`make check-python` verifies the updated inventories and orchestration. Local macOS results do
not substitute for the Linux CI groups.

Parameter coverage uses independently specified fixture bytes and the complete expected V1 object,
including 64-bit maxima and all four zero placeholders. Native tests cover truncation, malformed hex,
configuration syntax/duplicates, invalid basic settings, snapshot isolation, unavailable configuration,
argument validation and batches. Compiler probes protect private configuration/result fields and
reject extraction from known failure. Live WS checks exercise configured and unconfigured nodes,
file mutation after startup, maximum-size batches, and invalid/missing configuration startup.

## BEEFY root query

`beefyRoot(header_hash)` returns the padded Base64 accumulation-log super-peak from the
newest C(3) history record for the configured genesis block. This follows JIP-2 at the revision
above and Gray Paper 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/beefy.tex`, equation `accoutsignedcommitment` (`last(recenthistory).superpeak`).
It reads the stored commitment; it does not return a signature, assert finality, or recompute
and validate the history's consistency with the MMR peaks.

`src/chain/beefy.nim` exactly decodes C(3), checks the newest header and slot against the
retained block, and copies its nominal root. Missing or empty history, malformed/suffixed
bytes, mismatched identity/slot and policy refusal return RPC error 0; an unknown block
returns error 1 with its requested hash. Empty history is not interpreted as a zero root;
a matching record may legitimately contain zero. Input is bounded before copying to 256 KiB,
eight records, 341 packages per record, 2728 total packages and 1024 peak positions. These
are RPC resource policies, not additional consensus limits. Failed/default results carry
no root; successful extraction returns a fixed copy with no retained decoder lifetime.

Native tests use independently encoded history records to check last-record selection,
nonzero/zero roots, missing/empty/truncated/suffixed/oversized histories, mismatched headers
and slots, unknown blocks, argument validation, batches and notifications. Live WebSocket
checks read a fixed expected root after the source chainspec has been changed, proving
startup snapshot isolation. No live block import, BEEFY signing/finality, or subscriptions
are added. The next RPC increment should follow the available block-import/update pipeline;
subscriptions and live head/finality views still require those state sources.

## Retained work-report lookup

`workReport(hash)` returns the canonical report bytes as padded Base64 when its Blake2b-256
identity matches a report retained in configured genesis C(10) availability assignments or C(14) ready queues. It
excludes guarantee credentials, guarantee slot and registration slot from the returned bytes
and their hash. References: JIP-2 at the revision above; GP 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, Appendix C.2 work-report serialization,
`text/merklization.tex` chapter 10 and `text/reporting_assurance.tex` guarantee report hashing.

`src/chain/reports.nim` validates the entire C(10) chapter with the existing codec, using the
actual C(8) validator population. Both chapter copies and each nested guarantee are bounded
to 1 MiB, with at most 341 assignments. These are RPC resource policies. A matching report
must fit the existing 32 KiB raw response limit and remaining aggregate JSON budget; rejection
returns error 0, never a truncated blob. Whole-chapter validation precedes lookup, so malformed
later assignments or trailing bytes cannot authorize an earlier match. Native hash failures
also return error 0. Returned report handles are immutable, acyclic ARC owners and outlive the
parent decoder; serialization copies bytes without exposing mutable backing storage.

Unknown hashes, missing/empty retained report sources and unconfigured nodes return JIP-2 error 2
with the requested report hash in `error.data`. This is local retention, not a historical report
archive or a network fetch: reports no longer present in either retained chapter are not searched. Structural decoding does not verify guarantee signatures or consensus
eligibility. Live import, archive retention, submission and subscriptions still need their
corresponding state/event sources.

Native tests use the independent Python report/guarantee oracle and Blake2b implementation
for a fixed canonical report and its expected identity. They cover empty/missing state,
malformed/truncated/suffixed/oversized assignments, unknown hashes, exact reply budgets,
parameter validation, batches, notifications, independent copied bytes, retained report lifetime
and repeated ARC retirement. A compiler rejection protects the result discriminator. Live WS
checks retrieve the report after the source chainspec changes, alongside existing service and
concurrent QUIC traffic checks. These authored fixtures do not claim official conformance.

### Ready-queue fallback

After an ordinary C(10) miss, lookup exactly decodes C(14) and searches every row/item.
A C(10) match or failure is returned immediately; malformed C(10) cannot be masked by a
ready match, and a C(10) match does not require reading unrelated C(14). Within each searched
chapter, complete structural validation precedes matching. A malformed later ready row or
dependency set rejects an earlier potential match. Missing C(14) or a clean miss retains error 2.

References are the same pinned GP revision, `text/merklization.tex` C(14),
`text/accumulation.tex` `readyspec`, and [the ready-state schema](state-workqueues.md).
The fixed ring has no outer count: its epoch length is now captured privately in `Genesis`
from the same parameters used for header validation, exposed through a guarded nominal accessor.
RPC does not infer it from bytes or use mutable request-time parameters. Report hashing excludes
dependency sets. Returned report owners survive retirement of both the queue and configured map.

Ready lookup policies are 1 MiB total chapter/report bytes, 4096 epoch rows, 4096 reports
per row and in total, 64 dependencies per report and 16384 dependencies in total. Bounds
precede input-derived allocation, including empty ring descriptors. They are resource policy,
not new consensus limits. Existing raw/aggregate response budgets apply to matching reports.

Native tests cover absent/empty/nonempty C(10) fallback, multiple rows/items and duplicate
identities, final-row lookup, dependency ordering/uniqueness, late malformed data, exact response
budgets, oversized chapters/epochs, retained report lifetime and repeated ARC retirement.
A distinct independently encoded ready report is also queried over live WS after chainspec
mutation, alongside the existing availability report and concurrent QUIC clients. The next
substantive extension needs a live block/state publication boundary and a bounded report
retention policy; this increment does not fabricate those sources.

## Raw state inspection extension

`ragnarok_stateValue(header_hash, key)` reads one exact serialized state-map entry from the
retained configured block. This is a Ragnarok extension, not a JIP-2 method. The header hash
uses canonical padded Base64 for 32 bytes; `key` uses canonical padded Base64 for exactly
31 bytes, following GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` serialized state keys. Service storage preimage keys are not accepted
as a substitute; callers must supply the complete serialized map key.

The result is a Base64 blob for a present value (including `""` for a present empty value),
or `null` for a missing key. Unknown/unconfigured blocks return error 1 with the requested
header hash in `error.data`. Invalid arguments return -32602. Reads check the 32 KiB raw
value ceiling and remaining aggregate response budget before copying or Base64 allocation;
oversized values return error 0 without truncation. Lookup uses the existing immutable state
owner and does not mutate, enumerate or expose a writable map.

Example: C(11), the retained timeslot, uses key byte 0x0b followed by thirty zero bytes:

```json
{"jsonrpc":"2.0","id":1,"method":"ragnarok_stateValue","params":["5mOOsjxqUxhky5HYvxomxm/u7dg7VcwqcsnDWQBCjtQ=","CwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="]}
```

The example fixture returns `"BwAAAA=="` (E4 slot 7). Raw reads intentionally perform no
chapter-specific structural or consensus validation: they may return bytes rejected by typed
queries. They provide no state proof, live-state subscription or historical-state archive.
This supports inspection of retained chapters while those larger state sources remain absent.

Native tests cover exact key length/canonical padding, invalid argument shapes, unknown blocks,
missing versus empty entries, opaque binary data, the exact raw size ceiling and one byte beyond,
aggregate batch refusal, notifications and repeated ARC retirement. Live WebSocket checks query
a known chapter and missing key after source-file mutation alongside existing RPC/QUIC traffic.

## Paginated state-key discovery extension

`ragnarok_stateKeys(header_hash, start_after, count)` lists exact serialized keys from the
same immutable configured block used by `ragnarok_stateValue`. This is a Ragnarok extension,
not a JIP-2 method. `header_hash` is canonical Base64 for 32 bytes. `start_after` is either
`null` to start or canonical Base64 for a 31-byte serialized key. `count` is an integer from
1 through 128; no implicit defaults, fractions or exponent notation are accepted.

The result is `{"keys":[...],"next":...}`. Keys use unsigned bytewise lexicographic order,
not Base64 string order or numeric service-ID order. The cursor is exclusive and need not be
present in the map: a subsequent page begins at the first greater key. `next` is the last
returned key when more keys remain, otherwise null, including when the last page is exactly
full or the cursor lies at/beyond the final key. Continue with the same header hash to stay
bound to one state snapshot. An example initial request is:

```json
{"jsonrpc":"2.0","id":1,"method":"ragnarok_stateKeys","params":["5mOOsjxqUxhky5HYvxomxm/u7dg7VcwqcsnDWQBCjtQ=",null,128]}
```

Genesis capture retains a private sorted fixed-width key index only after complete-map
validation, bounded by the existing 16384-entry limit (at most 507904 key bytes plus sequence
metadata). Guarded ordinal access returns copies, never mutable backing storage. Pagination
uses binary search plus at most 128 key copies; it reads no state values and includes keys
whose values are empty or structurally invalid. This is discovery, not schema validation,
proof generation or a historical state archive. Key width/order follow the pinned GP
serialized-state namespace described above; pagination semantics are Ragnarok-specific.

Unknown blocks return error 1 with the requested hash; invalid arguments return -32602.
Aggregate reply-budget refusal returns error 0 and no partial page or continuation cursor.
Native checks cover exclusive and absent cursors, final/empty pages, strict arguments,
opaque entries, copied-key isolation, maximum page/batch limits and ARC retirement. A private
field rejection protects the index. Live WS checks traverse every fixture key over multiple
pages and compare the result with independently sorted serialized fixture keys after the
source chainspec changes. Live block publication and proof/archival queries remain future work.

## Sealed-header inspection extension

`ragnarok_header(header_hash)` returns the complete canonical sealed header as a padded
Base64 blob. This is a Ragnarok extension, not a JIP-2 method. It includes all GP C.2 header
fields and the seal, and its Blake2b-256 identity is exactly the queried header hash. The
input uses the existing canonical 32-byte Base64 hash contract. Unknown/unconfigured blocks
return error 1 with the requested hash; invalid arguments return -32602.

Reference: Gray Paper 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
Appendix C.2 header serialization, through the existing [header codec](header.md).
Genesis retains the already validated `OwnedHeader` rather than reconstructing fields or
capturing a second byte buffer. Its guarded accessor shares an immutable acyclic owner;
serialization returns independent copies. The owner survives the original chainspec buffer
and genesis handle. Existing 256 KiB capture validation remains unchanged.

RPC checks the 32 KiB raw response ceiling and remaining aggregate budget before allocating
or copying header bytes. A valid captured header too large to return produces error 0,
without truncation. This reports configured bytes, not proof of seal validity, finality or
successful block execution. Live imports, block-body retrieval and state proofs remain gaps.

Native tests compare the entire independently specified header, validate lookup arguments,
exercise notifications/batches, retain owners after source retirement, and mutate copied
bytes without changing the owner. Independently framed headers at exactly 32768 and 32769
bytes exercise size and aggregate-batch refusal; their hashes were computed independently
with Python Blake2b. Private-field rejection protects the retained header. Existing server
retirement checks now also cover its header owner. Live WS checks retrieve the sealed header
after chainspec mutation and independently hash its bytes to the advertised block identity.
