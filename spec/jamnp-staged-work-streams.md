# Staged builder work streams

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab` CE133/146 and Gray Paper
`fad0ded4a433052397bf7234352a57fe491883f7`.

This layer adds bounded source-free native stream routes for builder work. The host explicitly
calls `enableWorkStreams` only when its task dispatcher is installed; ordinary actors reject
these selectors immediately until activated. Callbacks copy one
bounded chunk and perform no hashing, PVM execution, canonical access or grant ownership. Exact
E4 message lengths are checked before body growth. Raw header decoding uses the actual
chain refinement/accumulation gas ceilings before CPU admission. Reads stop at the small header boundary;
the route never overreads a body prefix while authorization is pending. Only a host turn after
actual Services authorization resumes body reading. Exact request FIN and actual successful
host completion precede the bare response FIN. Reset, extra messages, stale controls and incomplete
messages cannot acknowledge work.

CE133 has one header message (E2 core plus package, at most 204802 bytes) and one exact extrinsic
message. CE146 has two header messages (core/mappings at most 515 bytes, package at most 204800)
and three body messages (exact extrinsics, exact raw segments, bounded proofs). The complete
bundle remains at most 13904950 bytes. Imported CE133 witnesses are separately acquired; framing
alone cannot manufacture availability or a completed report.

Native connection factories use public pinned LSQUIC flow-control settings to bound unread input
while a route pauses: 64 KiB per stream and 256 KiB per connection for node connections, with
window auto-growth disabled. Other endpoint profiles retain their defaults. Both primitive sides
validate optional window values before engine construction. Native flow-control credit is separate
from host frame/body memory; it is not a claim that all library allocations equal these windows.

Completion evidence must include actual authenticated TLS requests, real two-stage Services
execution, no body consumption or successful FIN before authorization/completion, fragmented and
oversized frames, zero-length body messages, unexpected suffixes, resets and actual-close quota
release. Public structural routes do not confer guarantor duty, report credentials, inclusion,
canonical adoption or light-state authority. Application validator activation and the remaining
sharing/availability/audit protocol families remain separately identified work.

## Observed evidence

On master `92e3b178b17c43850c921712606876d588493971` plus the preceding 29 native
layers, `jamnp_staged_work_streams` passed with actual authenticated builder TLS and real
Services authorization/refinement. Its cases exercise CE133, CE146, empty messages, paused
header-byte accounting through uncollected Done, withheld request FIN, corrupt import proofs,
trailing bytes, local cancellation during Done, foreign Done, oversized and truncated headers,
truncated bodies, full-width excessive proof lengths, observer/disabled-host refusal, per-peer
and global physical quotas, actual-close release and actual-chain gas rejection before CPU.
One thousand genuine detached transcript/copy-release cycles retained 22192 bytes before/after.

The first live fixture underallocated stream slots (128 versus the existing required 238); using
512 corrected setup without weakening the production capacity guard. The cancellation witness
now distinguishes local close from receiving a peer reset while still requiring actual server
retirement and no successful FIN. Temporary diagnostics were removed. The known formatter
joined a long `or peerReads` token; separate short guards avoid that issue without changing policy.

Affected `quic_transport`, `jamnp_node_connections`, `jamnp_node_service`,
`jamnp_managed_work_submission`, `jamnp_ticket_production` and `jamnp_preimage_gossip` suites
passed. Transport checks include atomic invalid-window refusal and the pinned 16 KiB minimum.
Fresh actual lowering rejected NodeService and enclosing ApplicationNode duplication.
`make build`, format and inventory checks passed. The final additional EOF/E4 cases changed
only the new test source; its full suite passed again. These are local results, not Linux CI.

The ordinary ApplicationNode dispatcher does not yet activate these work routes. The successful
native-host/Services integration above is an explicit dispatcher, not a claim that CLI validator
work participation, guarantor duty, CE133 fetching or CE134 sharing is already complete.
