# Judgment publication and disputed-report auditing

This native stack layer extends available-report auditing with JAMNP-S
`aa0e2b8498c0b1bc1725af2903704d701c6577ab` CE145, CE136 negative-report acquisition and
qualified forced auditing, under Gray Paper `fad0ded4a433052397bf7234352a57fe491883f7`.
The preceding layer retains original private execution sources and provides genuine evaluation,
optional original-key signing and CE147/138 acquisition. Nothing in this layer grants finality or
substitutes a negative publication for actual report reproduction.

A publication first needs complete bounded structural decoding and actual original-epoch Ed25519
membership/signature verification for every record. The GP message is ASCII `jam_valid` or
`jam_invalid` followed by the full report hash; epoch/index metadata selects the actual original
roster, but is not added to the signed domain. Unmerged epoch-domain proposal #578 is not adopted.
Current/previous roster populations remain independent, including null and repeated positions.
Missing historical epochs remain unavailable, never mapped to the current key at the same index.

Managed receipt checks the selected head and can use a still-anchored side view or retained
historical membership source for the original epoch. The whole message shares one read and
signature budget. The exact authenticated source hash and root accompany each claim through
guarantor verification and execution-origin admission. Independently installed finality retires
membership older than its previous epoch. Distinct authenticated keys at the same epoch and
ordinal remain separate ledger entries.

Support retries exclude failed hashes and continue toward older eligible sources even when the
selected head advances. Inbound receipts and locally owed publications reserve separate
judgment and report-serving capacity.

The receipt policy accepts an independent local ledger limit. The initial declaration,
local route refresh, and native gossip policies have separate configurable row ceilings.
Size them for the number of duties and judgments retained across the active epochs.
A full-profile validator can retain more than 256 locally owed judgments without widening
the inbound receipt ceiling. Local refresh has its own byte budget and can retain a
publication even if the relayed refresh quota is full.

A negative receipt may try a separately retained branch after a reporting context fails.
Even when the same key occupies the auditor position on both branches, each alternate
must establish that key in its own original-epoch roster and qualify the supporting
guarantee and execution origin in the same trusted branch. The resulting private origin
binds the actual membership hash and root used for support.

A signed negative claim alone does not qualify its supporting guarantee or certify report
invalidity. Unknown reports require full-hash-bound CE136 acquisition, actual two/three original
credential role/signature qualification and a genuine complete execution source. Never fabricate
an availability block or pending C10 assignment for a report learned only from a negative judgment.
Full sources remain private to Services; controllers get detached routing/records and exact host
selectors. Private evaluation and original-key signing use genuine computed/recovered evidence.
Local quotas, missing history, timeout, cancellation and backend failure never invalidate a report.

Complete-message work/retention reservations precede expensive verification or publication.
Late malformed records, bad signatures and unavailable credentials cannot publish an accepted
prefix. Exact duplicates are idempotent; conflicting valid claims are retained as bounded conflict
evidence rather than overwriting earlier obligations. Gossip preserves the original signer and
reaches the relevant original auditor grid and successor validator sets. All native and managed
controls remain exact through Done, cancellation and joined shutdown. Omission stays disabled.

Completion checks: independent Ed25519 message/wire witnesses; original and resized epoch rosters;
whole-batch late failure, duplicate/conflict and retention bounds; actual TLS request/response FIN;
known and previously unseen negative reports; genuine guarantee qualification, private forced
computation and signing; foreign leases, deadline/cancel/close paths; checked native Linux,
ARC/Clang ThinLTO and stable repeated ownership observations. The later-CE144 source decision in
`jamnp-audit-runtime.md` remains pending independently of this work.

Implementation and qualification are in progress; this contract does not claim completion.

The private unknown-report path distinguishes the judge's original membership source, the actual
standalone-guarantee reporting context and the complete execution snapshot. All three roots and
whole parameter profiles are independently bound to Services' actual retained chain. There is no
manufactured availability block: evaluation and fetch metadata expose an explicitly absent block
reference for disputed-only work. Full consensus guarantee credentials remain a distinct stronger
type; standalone signature support does not bypass the report admission/population checks.

Historical execution uses actual C11 time. Pinned GP `guaranteeing.tex` specifies the most recent
state when needed; `pvm_invocations.tex` and `accounts.tex` bound historical lookup to the D-wide
window, with the additional audit margin. A retained full snapshot must satisfy the actual lookup
window and anchor time under its own parameter profile. Missing or expired history returns
`HistoryUnavailable`, never an authorizer/refiner fault or a negative signing capability. Whole
entry/node/value retention scans precede publication. Ordinary available reports preserve their
original complete predecessor, and generic recovery/evaluation/signing binds the exact physical
registered target in either source form.

CE145 claim verification, report hashing/decoding, standalone guarantee support and full-map
capture run on the existing bounded managed worker. Optional receipt explicitly enables a
separate selector only after full-node private retention is configured. The foreground host holds
one exact FIN-complete incoming claim, acquires missing reports over CE136 from the original live
publisher, and keeps the same deadline through all stages. Actual bounded historical contexts can
be retried after a support refusal; a slot label never supplies a replacement roster. Whole-message
signature/hash/read/workspace/output reservations precede support verification. The private exact
collector validates all sources and reserves aggregate registry capacity before inserting any
negative origin. Generic collection cannot expose source-bearing receipt output, including Done.

Source-free qualified records become eligible for detached bounded storage only after complete
receipt succeeds. Duplicate epoch/index/report/validity claims are idempotent. Opposite valid
claims occupy separate accountable rows; neither replaces the other or determines local report
truth. Negative obligations are deduplicated by original report hash and auditor epoch. Detached
hash-verified raw report replies remain available for CE136 serving independently of the report
input aliases frozen on the private worker. Full report/key/state graphs do not enter the ledger.

Disputed CE147 routing uses the actual qualified original guarantor keys. CE138 routing retains
all compatible explicitly authenticated candidate rosters from the reporting and original audit
contexts. Matching population alone never chooses an assurance epoch; each candidate keeps its
original positions, nulls and repeated keys. Epoch-zero C9 does not invent epoch minus one. All
six signed report descriptor fields, original coordinates and Merkle root are rechecked before
recovery. Distinct proven shard indices, rather than peer/response count, determine the threshold.
No compatible or sufficient reachable source remains unavailable. Maximum request policy is
3072 (three bounded 1023-position candidates plus three guarantors); actual configured budgets and
whole-round proof/workspace reservations remain independent.

The optional forced-audit controller uses the node's configured original-key signer, private
registry, and ordinary acquisition controller. A qualified negative receipt triggers a role
plan. Original auditors relay the received signature and reproduce the report. A completed
private evaluation can produce signed judgments at the original local positions. Publication
prepares the detached CE136 reply alongside the signature. Gossip forwards original records
and uses the successor cohorts known to the current plan.

Native qualification covers real TLS judgment receipt and relay, late guarantee rejection,
authenticated recovery, publication cancellation, and a complete ordinary-node forced audit
that reproduces a valid report after a negative receipt. The judgment suite also checks stable
occupied memory over 1000 cycles.

The node refreshes successor routes from detached original roster data and retires completed
disputed execution origins. It also schedules initial CE144 duties from selected and admitted
side branches. Later-tranche scheduling and the associated available-block retention policy are
deferred under the [CE144 source decision](jamnp-audit-runtime.md#deferred-later-tranches).
