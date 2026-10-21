# Remote ancestor context

Scope: bounded CE 128 descending-inclusive responses supply immutable sealed parent
headers for existing report admission. Authority is pinned JAMNP-S revision
`439c45aad135dc654b3de6f56d7d694fd02b7aa8`, `simple.md` CE 128, and the existing
GP 0.8.0 block/header codecs. Pins and protocol behavior do not change.

A request binds the exact known child's parent hash, its slot and an explicit
positive E4-sized maximum. Response payload is an uncounted sequence of complete
GP blocks. Empty and shorter-than-maximum responses are valid protocol outcomes;
empty exposes no headers. Every sealed header must hash to the previously expected
parent and have a strictly older slot. Decode the complete extrinsic to determine
block boundaries; header identity alone does not validate historical execution,
signatures, extrinsic commitments or finality. Existing report admission keeps its
own complete linkage, profile, lookup-child and state-root checks.

Response bytes, per-block codec resources, retained header bytes and header count
have independent explicit limits. Check arithmetic and descriptor bounds before
allocation/access. Failures expose no captured prefix and retain exact nested
block codec reasons. Returned sequence storage is independent of the immutable
response owner. No StateStore, storage, Services, finality or canonical history is
modified by acquisition.

Completion witnesses: independent literal request bytes, genuine descending
chains, exact/short limits, shorter responses, empty/truncated/suffixed bodies,
wrong first identity, reordered/duplicate/unrelated parents, strict slots, default
owners/results, late failure atomicity, detached ownership and repeated ARC release.
Streaming FIN, transport retirement, command wiring and actual network operation
remain separate layers. M1 framing is complete; full serialization/JAM parity remain open.

## Response evidence

The focused native `application_ancestor_response` suite passes, including literal
E4 request bytes at the full u32 maximum, genuine composed three-parent responses,
shorter valid replies, duplicate parents, late block truncation and an extra
message/body suffix. Independent copies cannot replace retained header owners.
Its final 1,000-cycle success/late-refusal ARC observation retains 358,512 occupied
bytes before/after. Four strict runtime extraction failures with genuine positive
controls, six private-field rejections and verification inventory pass locally.
Evidence: `build/remote-ancestors-{unit,guards,inventory}.log`. This is local
macOS/ARC evidence, without a Linux CI or complete JAM parity claim.

## Fragmented receiver

`AncestorReceiver` owns one E4-framed payload and monotonically increasing local
generation. It checks the complete u32 claim against the explicit host-sized
response ceiling before allocating. Callbacks copy only the declared body;
truncated framing, trailing bytes and oversized claims release the entire buffer.
Both request FIN and actual response FIN are required before explicit producer
decoding. Late/foreign generations cannot append, finish or cancel a reused owner.
Native consumers must retire their stream callback binding before decoding/reuse.

`application_ancestor_receiver` passes every split, byte-at-a-time reception,
both FIN orders, all early EOF offsets, empty reply, extra bytes, quota refusal,
stale/cancelled generations and detached response ownership. Five runtime
extraction failures/positive controls, three privacy checks, actual `=dup`
lowering rejection and inventory pass. Its 1,000-cycle ARC observation holds
276,576 occupied bytes before/after (`build/ancestor-receiver-*.log`).

## Native stream binding

`AncestorStream` binds one receiver address/generation to one native stream,
checks all callback identities and uses explicit per-callback read/write bounds.
Partial request writes retain their exact offset; only actual native EOF supplies
response FIN. Reset, deadline and cancellation stop I/O but retain the native
handle until its final close callback. The exclusive binding's destructor checks
that this retirement occurred; actual duplication lowering rejects copies.

The focused `application_ancestor_stream` suite passes real TLS healthy/empty,
oversized, premature-close, no-FIN, deadline and reset scenarios. An independent
finite responder validates every literal descending request byte and request FIN.
One-byte input/output fragmentation and foreign/replayed callback checks pass.
The independent primitive observer reports zero hash calls during reception;
producer decoding occurs only after native teardown. Ownership rejection and
inventory pass (`build/ancestor-stream-*.log`). Peer pin selection and command
integration remain subsequent layers; no remote CI was requested.

## Pinned outgoing peer

`AncestorPeer` owns one outgoing endpoint, receiver and stable callback aggregate.
It checks the actual TLS certificate against the selected Ed25519 pin before
opening one local stream. A host-supplied monotonic total deadline covers handshake,
transfer and final stream retirement. Backward ticks reject without changing the
captured deadline. An unsolicited/late open cannot replace a live binding. Ready
requires both FINs, actual stream close and graceful native connection retirement; only then may the host decode headers.
Explicit close retires callbacks before buffer release/reuse or aggregate destruction.

`application_ancestor_peer` passes actual pinned TLS healthy/empty replies, wrong-key
zero-request refusal, oversized/premature responses, no-FIN timeout, backward time,
invalid policy/endpoint/request, partial startup, explicit idempotent retirement and a fresh second connection to
the same single-peer listener after graceful slot release.
Captured immutable headers survive full endpoint/receiver cleanup. Four privacy
checks, actual composite duplication lowering rejection and inventory pass locally
(`build/ancestor-peer-{unit,guards,inventory}.log`). Command acquisition and existing
report-admission integration remain subsequent work.

## Explicit command activation

`--download-remote-ancestors COUNT` is unique, download-only and state-enabled.
COUNT has one canonical positive decimal spelling in 1..64; omitted/default/failed
parses request no remote context. It can extend retained local and explicit-file
context without silently replacing either source. All requested ancestor counts
plus future download lineage must fit the existing policies before network IO.
The remote response total will use the explicit `input.blockBytes` ceiling, with
per-block codec and retained-header budgets checked independently.

The dedicated options suite passes every supported count, malformed/full-width/
duplicate/late-failure reset and unrelated-command refusal. Existing app, explicit
ancestor, disk-storage and recovery option suites, the private activation-field
rejection and inventory pass (`build/remote-ancestor-options-*.log`). Parsing alone
does not start remote acquisition; command wiring is the next layer.

## Download command integration

Before any ancestor/child request, reserve explicit-file/local count plus requested
remote maximum plus all future selected parents. Bound E4 response capacity before
Services/file IO. After startup, extend the oldest captured prefix header (or selected
head when none exists) with a descending request. The remote response total uses
`input.blockBytes`; per-block codec limits and remaining input/report header bytes
remain independent. Parent-inclusive report bytes charge the selected head once.

Acquisition uses the existing finite round-robin scheduler/cooldown and configured
TLS pins. Empty, malformed, over-budget, reset or wrong-lineage responses consume
one attempt without a prefix. A shorter nonempty valid response may supply context;
normal report admission still decides whether the later candidate has every needed
lookup proof. No child request follows an exhausted/refused acquisition. Existing
explicit/local inputs remain the newest prefix and complete report admission still
validates their links. RPC/UI tick while acquisition owns no execution worker lease.
One monotonic command deadline includes acquisition and all later children.
Graceful ancestor connection retirement precedes a fresh child endpoint, preserving
a single-peer listener's capacity. Teardown joins before captured aliases retire.

`application_remote_ancestor_command` passes actual forked TLS responders with a
newly guaranteed report and two guest executions: omitted ancestry independently
fails MissingLookupAnchor; fetched context permits real adoption. Independent literal
requests require descending-before-ascending order. Empty, changed seal, suffix,
missing FIN, wrong pin and quota failures issue no child request; wrong pin and
count preflight issue zero requests. Two pinned peers each observe one ancestry
and one child request during empty-first fallback. Legacy startup/progress suites
and inventory pass (`build/remote-ancestor-command-*.log`).

## Durable canonical separation

The command suite additionally fetches the genuine lookup ancestor before a real
disk-backed child adoption. Normal disk restart matches the independently composed
child hash/root and every serialized entry, retains exactly the original seed and
adopted child, preserves the real parent link and leaves finality unavailable.
The fetched historical header is absent from canonical snapshot/history lookup:
acquired report context grants no state snapshot or persistence authority.
`build/remote-ancestor-durable-unit.log` records the focused native pass. The test
starts with an explicitly fresh generated database, so prior interrupted invocations
cannot replace its source head or contaminate expected request identities.

## Actual executable and physical layouts

The registered `application_remote_ancestors` E2E workload uses the current Make-built
production executable and an independent native TLS/protocol/complete-map witness.
Journal and managed-layout commands each fetch the genuine lookup context, execute
the signed two-guest child, exit successfully and restore every expected serialized
entry/root/hash through normal disk startup. Both retain exactly seed/child history,
leave finality unavailable and keep fetched historical headers outside canonical
snapshot lookup. Literal requests prove descending-then-ascending ordering.

A changed historical seal returns Exhausted without a child request; a pre-existing
journal remains byte-identical and restores its original complete head. Missing FIN
returns the total-command Timeout without adoption. The native witness independently
verifies one request and the retained original state in both refusal cases. Actual
application exit codes are 0/0/2/2, and all four independent native witnesses exit 0.
The single-child CLI preserves its existing status-only output.

Production Make build, all four focused registered E2E cases, failed peer/witness
build safeguards, timeout cleanup and independent-verdict safeguards pass locally.
Full pinned formatting and source-owned inventory also pass. Evidence is under
`build/remote-ancestor-e2e/results.json`, `build/remote-ancestor-executable-run.log`,
`build/remote-ancestor-production-build.log` and `build/remote-ancestor-*-tests.log`.
This integrates master a000136 after native rebasing with unchanged layer patches;
no storage/Services API, upstream pins, remote CI labels or merge action changed.
