# Source-bound preimage request linkage

Scope: `src/state/preimage/linkage.nim` implements the second conjunct of
Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, `text/accounts.tex`,
eq:preimageconstraints. Every present preimage must have a request dictionary key
with its declared hash and exact actual byte length. Hash content is independent.

Only an exact complete immutable inventory grants exhaustive request membership.
Service and preimage counts and the complete worst-case pair comparison budget
are preflighted. Division bounds each row's multiplication before subtraction;
zero-request rows still consume preimage work. The bounded linear search compares
full-width lengths without narrowing and exact fixed hash bytes. History mode is
not part of the specified membership predicate. No further history consistency
or ordering rule is inferred by this certificate.

Missing request exposes only the original nominal service and local preimage
ordinal. Defaults, resource refusal and semantic failure retain no prefix source.
Success privately retains the exact original inventory and actual work counts.
No hashing, payload copies or extra output arrays are required. Separate content,
footprint, root trust and STF predicates remain unclaimed.

Native verification uses independently encoded complete sources, exact and
one-short budgets, same-hash wrong length, absent request, a late matching key,
request history mode independence, vacuous no-preimage success, no-hash observer,
1,000 ARC cycles, strict runtime controls and privacy/nominal compiler rejection.
Run `make unit SUITE=state_preimage_linkage`.

Observed locally: selected native suite passed, including same-length wrong-hash
request refusal. 1,000 ARC cycles retained 466,528 bytes before and after. Four
strict runtime refusals, seven exact compiler rejections and the genuine positive
control passed; inventory and pinned format checks passed.
