# Output union across completed accumulation rounds

## Scope and authority

Extend `accumulation_outputs.nim` from its initial-round projection to an exact retained history
ending at a genuine `CompletedAccumulationContinuation` or `CompletedAccumulationReentry`.
Authority is GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
`accumulation.tex` SHA-256 `bc919b34266cee75577f5fb3282b55768d0d75b6b8fe15d2835a228be18e6a6f`,
`accseq` output union, `accpar` B, and `finalstateaccumulation`. The notation source SHA-256 is
`5a6f602406d66a7b323f6e9b27d57e8284f782cc942deb32671082000127579f`: ordered set conversion
uses ascending values, with byte sequences ordered lexicographically. Thus pair order is numeric
service followed by commitment octets; identical full pairs collapse. Different commitments from
the same service and equal commitments from different services remain distinct members.
Terminal selection and [history-root semantics](history-transition.md) retain their existing pins.
No source, codec representation or signing domain changes.

## API and ownership

The original initial-round overload and `AccumulationOutputLimits` remain supported. Two new
`prepareAccumulationOutputs` overloads accept completed continuation/reentry owners and
`AccumulationOutputHistoryLimits`: independent ceilings for completed rounds, total executed
outcomes, and unique output-log items/bytes. Every initial, first continuation, repeated reentry
and idle terminal completion counts as a round. Missing-code skips contribute no executed outcomes;
absent and duplicate yields still consume outcome work. Limits are local policies, not certificate
claims that recursion has terminated.

Only the supplied completion's own predecessor chain is accepted; callers cannot assemble unrelated
batches or replace provenance. Iterative traversal bounds batch descriptors and aggregate outcome
count before inspecting yields. Candidate row storage is bounded by the execution ceiling and
native extent checks. Sorting and adjacent full-pair compaction take O(Y log Y) work and O(Y) scratch
for Y present yields. The final unique set's exact count-prefixed wire extent is checked before
allocating retained rows or encoding. This permits many duplicate yields under a small final log
budget without unbounded candidate storage. No hashing, normalization, guest execution or state
writes occur during collection or encoding.

`PreparedAccumulationOutputs` remains the single immutable public representation. `outputsInfo`
adds copied round/outcome counts. `outputsSource` always returns the original initial completion;
`outputsContinuation` returns the first continuation or `NoContinuation`; `outputsReentry` returns
the latest included reentry or `NoReentry`. Defaults remain `Uninitialized`. All failed results carry
reasons alone and extraction is success-guarded. Output pairs and each encoding are independent
copies. Explicit `outputsRoot` reuses the existing root algorithm and guarded backend reasons.

An output history may be a prefix of supported accumulation: this API does not certify final
accseq termination or publish C(16), recent history, service state or the block. Transfer execution,
account/privilege effect merging and whole-block coordination remain open. M1 framing is complete;
full state serialization and accumulation parity remain open.

## Completion tests

Use real signed initial/continuation/reentry rounds and actual guest returns. A guest returns the
compact bootstrap (slot, service, input count) from its initialized argument page: initial input
counts and repeated report groups provide both differing same-service commitments and repeated
identical pairs. Check independent literal sorted log bytes and raw Keccak node transcripts,
reversed execution arrival, partial and terminal histories, independent exact/short/full-width
policies, absent and skipped yields, initialized empty logs, default sources, copied records and
encodings, original complete-map identity, retained history lifetime, explicit hash failure/retry,
and 1,000 ARC cycles. Extend strict extraction and nominal guards, run the original output suite
and the reentry fixture consumer, inventory/provenance, Python tooling checks and pinned formatting.

## Local verification

The new `make unit SUITE=accumulation_reentry_outputs` passed with six completed rounds, ten
executed outcomes and four unique pairs. Genuine same-service differences, repeated equal pairs,
equal hashes across services and present zero hashes are covered. Independent literal 145-byte
log bytes and a balanced raw Keccak transcript match; short policies, source identity/lifetime,
copy isolation and backend refusal/retry pass. Its 1,000-cycle ARC workload retained 655,184
occupied bytes before and after. The existing `accumulation_outputs` suite also passed with
712,992 occupied bytes unchanged over 1,000 cycles. The affected `accumulation_reentry_cycle`
fixture consumer passed with 914,944 occupied bytes unchanged over 1,000 cycles.

All twelve strict extraction probes and seven privacy/nominal compiler rejections passed.
Python discovery passed 443 tests with seven skips; source-owned inventory and pinned formatting
passed. Diagnostic compiler iterations reused existing native libraries; maintained native suites
ran sequentially through Make. Evidence is under ignored `build/accumulation-reentry-outputs/`.
These are local macOS results, separate from exact-head Linux CI.
