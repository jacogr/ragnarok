# Recent block history from finalized accumulation

## Scope and authority

Bind C(3) advancement to the private finalized [C(14)/C(15)/C(16) candidate](accumulation-ready.md). Authority remains
GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401`, recent_history.tex SHA-256
`1a5424af880851d77baf51d29d05a11cff689a007dd44d991f40cf7025a6fc36` equations
`correctlaststateroot`, `accoutbeltdef`, `recenthistorydef`, and the pinned Merklization equations
recorded in [the existing history transition](history-transition.md). Preserve ASCII `node`/`peak`
and all existing codec widths. No pins, domains or primitive implementations change. T wire order remains header hash, super-peak,
state root, E4 slot and package dictionary; the conceptual recent-history tuple does not change that
serialization order.

The current header identity hashes the complete sealed header from retained admission. Its prior
state root corrects the latest parent record; its slot labels the new record. The new record's
state root remains the prescribed zero placeholder until its child supplies the correction.
Reported package/segment associations come from this block's certified guarantees, independently
of assurance availability or the accumulated prefix. The belt receives the root of the complete
finalized selected output-pair union retained by C(16), including differing same-service pairs.

## API and ownership

`prepareAccumulationRecent` accepts only `PreparedAccumulationReady` and explicit header-byte,
output-log and recent-history policies. No loose header, root, package array or substitute state
can authorize a bound result. Derive original admission through exact retained history/finalization.
Check core-profile agreement and actual header/output/guarantee extents before work or allocation.
Read C(3) from the actual full-map ready successor, bounding detached bytes before exact decoding.
Reuse the existing output-root and history advancement algorithms, including parent correction,
canonical package order, eight-record eviction, optional belt peaks, carry and super-peak bagging.
Fork the actual ready successor under inherited store ceilings and atomically replace only C(3).
Any stage refusal discards its private work and preserves every source and caller snapshot.

The opaque result retains its exact ready source, immutable posterior history, accumulation root,
canonical entry and complete candidate map. Root values copy; history/state/source getters retain
immutable owners, and entry extraction copies bytes. Defaults and failures carry reasons alone.
Selected success and selected nested codec/header/output/history/store failures require guarded
accessors. This remains a full-node complete-map candidate, not whole-block publication or a light
state proof.

## Completion tests

Use genuinely signed full/partial/empty stopped accumulation with new guarantees distinct from
processed packages. Compare literal C(3) framing, complete sealed-header hash, corrected parent
root, new zero placeholder, canonical package/root associations, exact slot and optional peaks.
Use actual multi-round guest output pairs and independent Keccak transcripts for output roots,
carry and bagging. Compare independent complete-map roots and preserve C(14)/C(15)/C(16), earlier
service effects and all priors. Check exact/short/full-width resource policies before work, default
sources, profile refusal, header/root/history/trie backend refusal and retry, detached ownership,
entry isolation and 1,000 ARC cycles. Add extraction/privacy/nominal probes and run the selected
native suite, affected fixture consumers, inventory/tooling and pinned formatting. Reuse unchanged
history-vector/codec/PVM algorithm evidence.

## Remaining work

Combined C(13) publication, last-accumulation account timestamps, remaining transfer/account/privilege
coordination and whole-block publication remain open. M1 framing is complete; full state
serialization and accumulation/block parity remain open. PVM host publication remains independent.

## Local verification

Passed `make unit SUITE=accumulation_recent`. A literal 365-byte C(3) witness and independently
assembled complete-map root match genuine signed finalization. New guaranteed packages 10/11
remain distinct from processed queued packages 64..67 in full, unaffordable and empty cases.
The full sealed-header hash differs from the unsigned-prefix hash; parent correction uses the
admitted parent posterior root and the current record retains its zero placeholder. Empty output
creates a present zero peak. Four actual multi-round output pairs match independent raw `node`
Keccak transcripts, and authored prior peaks match independent carry and `peak` bagging transcripts.
C(14), C(15), C(16), earlier fulfilled provisions, unrelated entries and source maps survive.

Exact/short/full-width policies, profile/default refusals, entry-copy isolation and detached owners
pass. Independent header, output-root, belt-carry/bagging and private-trie failure/retry paths leave
priors untouched. Over 1,000 success/header-failure/trie-failure cycles, occupied allocation remains
2,104,544 bytes before and after. All twelve runtime extraction guards and five privacy/nominal
compiler rejections pass through the established runners. Python discovery passed 445 tests with
seven skips; source-owned inventory and pinned formatting pass. The affected `accumulation_ready`
and `accumulation_reentry_outputs` native suites also pass,
with 1,000-cycle occupied allocations unchanged at 907,824 and 659,424 bytes respectively. The
new signed fixture options preserve existing empty defaults. Underlying history codec, published
vectors, output collector,
PVM and history-transition implementations are unchanged, so their algorithm evidence is reused.
Logs are retained under ignored `build/accumulation-recent/` and the native selected-suite/evidence
directories. These are local macOS results, separate from exact-head Linux CI. M1 framing remains
complete; full state serialization and accumulation/block parity remain open.
