# Posterior ready queue after finalized accumulation

## Scope and authority

Advance C(14) on the private C(15) successor of genuine report-only finalization. Authority is
GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401`, accumulation.tex SHA-256
`bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`, History and Queuing
D/E and the final ready equation after `accumulationstatisticsdef`. No pins or domains change.

Let m be the candidate slot modulo epoch length and delta the strictly positive child-parent slot
difference. Replace row m with E(newly available deferred reports, processed packages). Clear rows
of cyclic ages 1 through delta-1 and apply E to older surviving rows. A full elapsed epoch clears
all prior rows. Current-row replacement takes precedence even for singleton epochs. Preserve row
and report order; remove only reports and dependencies named by the actual processed package set.
New deferred reports use the union of prerequisite and lookup package hashes, first edited by the
original parent accumulated union. Immediate newly available reports do not enter posterior C(14),
including when unaffordable. Never substitute the flattened priority-planning q for deferred reports.

## API and ownership

`projectAccumulationReady` accepts immutable parent ready/accumulated rings, explicit stable available
reports and processed hashes, absolute parent/candidate slots and independent work/codec limits.
It certifies no block provenance. Preflight full input work including rows that expire and hashes
that deduplicate before allocating projection scratch. Canonical codec output is captured as an
immutable ring with separately owned entry bytes. Package lookup uses bounded sorted scratch.

`prepareAccumulationReady` accepts only `PreparedAccumulationHistory`. It derives original parent
C(14)/C(15), exact available reports and both header slots from retained authenticated admission;
the newest certified C(15) row supplies the processed set. Profile checks precede chapter copies;
full decoding requires exact consumption. Fork the actual history successor under inherited store
limits and apply only C(14). Preserve service/provision effects, C(15), C(16) and every unrelated
entry. Failure discards only the private candidate, leaving every caller/predecessor immutable.

The opaque result retains exact history source, immutable ready ring and complete successor map.
Entry access copies bytes. Defaults remain distinct from initialized empty rings; payloads and nested
codec/store reasons are success/alternative guarded and private. Full-node complete-map semantics
are unchanged; light-state proofs need their separate contract.

## Completion tests

Native literal witnesses cover slot gaps, wrap, full-epoch expiry, singleton rings, exact row order,
processed removal, dependency subtraction, prerequisite/lookup union, historical filtering, unlocked
deferred retention, immediate exclusion, input/output bounds, full-width policies and independent
wire framing. Signed full/partial/empty stopped finalizations test exact source binding, preservation
of C(15)/C(16)/service effects, full-state root expectations, backend refusal/retry, detached owners,
copy isolation and 1,000 ARC cycles. Strict runtime extraction and privacy/nominal probes retain the
same supported verification paths. Run the native suite, source-owned inventory and formatting.

## Remaining work

Recent history C(3), combined C(13) publication and account accumulation timestamps, transfer/account/
privilege integration and whole-block publication remain open. M1 framing is complete; complete
state serialization and accumulation/block parity remain open. PVM account publication remains
independent.

## Local verification

Passed `make unit SUITE=accumulation_ready` on current master `21eae6dd`. Literal authored wire
expectations cover current-row replacement, crossed-row clearing, old-row retention, processed
package/dependency edits and prerequisite/lookup union. Full, partial and empty signed finalizations
preserve exact history/source identity and C(15)/C(16)/unrelated entries; an independently assembled
complete-map root matches. Earlier fulfilled provisions survive. Backend refusal leaves priors
unchanged and retry succeeds; detached owners and copied entry bytes remain independent.

The 1,000-cycle success/backend-refusal workload retains 907,824 occupied bytes before and after.
All nine runtime extraction guards and five privacy/nominal compiler rejections pass using the
established runners and prepared native libraries. Python discovery passed 445 tests with seven
skips; after adding the exact pinned report fixture binding, all 31 native fixture-harness tests
and source-owned inventory pass. Pinned formatting and diff checks pass. No existing protocol
codec, queue planner, finalizer or PVM implementation changed. Logs are under ignored
`build/accumulation-ready/` and the native selected-suite/evidence directories. These are local
macOS checks, separate from exact-head Linux CI. M1 framing remains complete; full state
serialization and accumulation/block parity remain open.
