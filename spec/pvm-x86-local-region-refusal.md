# Candidate-local x86 region refusal

The existing PVM source, gas, attempt, immutable-owner and executable-storage contracts are
unchanged. This is an admission/coverage fix, not a guest-semantics change or a speed claim.

`publishX86Region` previously marked its sole region cache permanently refused before validating
the candidate. A two-block round of64 high-multiply operations per block fits each ordinary leaf
but exceeds the unchanged4096-byte connected-code bound. That local failure prevented an unrelated,
smaller loop in the same source owner from ever becoming a region. Ordinary native leaves and
checked guest outcomes remained correct.

The unchanged-master diagnosis was confirmed in native Linux x86
[run40927711385](https://github.com/jacogr/ragnarok/actions/runs/40927711385), private source
`11c56443e928104891dcc93b07876008b1860384`, runtime
`3b69eced305a9464e064f4bd43773b11d190258e`. The affected owner recorded zero small-loop region calls
versus three in a fresh owner; complete CPU/attempt outcomes agreed with checked execution.
Raw storage/region positives and explicit executable refusal passed. Original ZIP, source/image
hashes and exact outputs are retained; independent audit SHA-256:
`c8f64beeaa845ac7af53167a9cdc736cbdac8c39b90b54b0cd10ee328b2f68c1`.

Local shape, source-coordinate, operation-count, branch-tail and generated-size negatives now leave
the sole cache available for other candidates. The existing per-header eight-complete-visit budget
still bounds rediscovery and permanently restores ordinary whole-block workers after exhaustion.
There is no new retry table, owner field, cache capacity, hot-worker branch or reset policy.
Exhausted global1024-publication capacity, missing arena and failed physical publication retain
lifetime refusal. Already admitted ordinary native entries remain callable.

The registered `pvm_x86_region_refusal` suite covers local negatives before allocation, the same
working owner rejecting an oversized candidate then publishing/executing a small region, exact
eight-probe exhaustion, genuine publication and physical byte capacity, forced/unsupported storage
refusal, both source guest orders, repeated-negative cold-accounting stability, positive later
native-region counters and complete CPU/attempt-state prefix agreement. Quotas, source facts,
native image ABI and code generation are unchanged. Actual native qualification and independent
review are required before acceptance; no application timing claim is made.

The suite is an isolated native owner-state profile, using the same per-suite header/define
declarations as existing ARM policy witnesses. The profile validator admits only the fixed x86
selector/refusal pair alongside ARM, rejects mixed/missing selectors and mismatched refusal,
and retains the strict compiler-option allowlist. Directory-wide codec execution is unchanged.
