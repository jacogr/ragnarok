# Bounded reads of authenticated values

Scope: already verified immutable proof lookups, unchanged proof/wire formats and root authority.
`VerifiedStateLookup.copySlice` returns exactly an admitted byte interval without first copying the
entire payload. Default lookups, proven absence, invalid full-width ranges and local byte ceilings
remain distinct typed refusals. Offset/length validation uses subtraction before native narrowing;
zero-length reads at a present value's end succeed, including present-empty values. Even zero-length
reads of authenticated absence return `MissingValue`. Detached mutation cannot change retained facts.
The slice inherits already completed whole-value authentication; it is not an independently verifiable
subvalue proof or a new root/complete-map certificate.

`sameVerifiedLookup` compares root, exact key, presence and bytes directly within immutable owners.
It refuses defaults and needs no crypto or mutable payload copies; independently captured raw proof
paths may represent the same fact. Existing overlapping `mergeProofViews` uses this comparison,
removing the two whole-payload temporary copies previously used for each overlapping present key.
Root disagreement, output quotas, conflict refusal and atomic immutable union semantics stay intact.
No store/database API, scheduling, worker, dependency pin or format changes are introduced.

Native checks authenticate a 128 KiB value, present-empty and absent facts, independently captured
same-root witnesses and crossed-root evidence. Exact/short/saturated copy limits, overflowing and
end-boundary ranges, literal cross-boundary bytes, detached mutation, source-scope retirement and
exact duplicate-union quotas are covered with the backend disabled after authentication. After warmup,
1,000 isolated slice/refusal/equality/union cycles require unchanged ARC occupancy with fresh evidence.
Existing proof-view, service/historical code and whole-map page transfer consumers retain their
separate verification contracts; no broad allocation or throughput benchmark claim is made here.

Local measurement used fixed independently verified 128 KiB facts, three warmups and ten alternating
baseline/candidate runs, each with 1,000 duplicate merges, on macOS arm64 with pinned Nimony,
checked release ARC/Clang Thin LTO. Baseline median was 102.37 ms (100.70–120.45 ms range), candidate
43.00 ms (42.55–43.67 ms). Public allocator snapshots repeated twice reported 270,336 live bytes
for two detached whole-value reads versus 64 for two four-byte slice reads; these are retained-copy
snapshots, not instrumented merge peaks. Generated C confirms two full-value read calls in the old
overlap branch and zero in the new branch. Valgrind/hyperfine were unavailable; no instruction-count,
Linux, whole-process peak or general throughput claim follows. The fixed source/build commands,
baseline/candidate binaries and full samples are retained in local ignored
`build/state11-proof-value-profile/` with `build/state11-proof-value-benchmark.py` as the regression
command. Standard allocator/runtime sources and all checks remain unchanged.
