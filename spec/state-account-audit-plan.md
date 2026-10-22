# Immutable whole-account audit planning

Scope: preflight all policies for existing account footprint, preimage content and
request-linkage checks before payload copying/hashing. The underlying predicates
follow Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, accounts eq:deposits and
eq:preimageconstraints. A plan certifies resource admission only, not those predicates.

Only a genuine exact complete inventory is accepted. Planning explicitly bounds
two service-row passes plus each inspected preimage fact. First preflight row and
fact counts, dependent footprint checks and complete worst-case request comparisons;
then inspect only captured fixed preimage extents for individual/aggregate bytes.
Division/subtraction prove all charges and products before arithmetic. No payload
is copied or hashed. Refusal preserves its actual planning/footprint/content/linkage
policy boundary without a partial plan or invented reason.

Success privately freezes the original inventory, all supplied policies and fixed
work observations. Copied policies cannot loosen the frozen plan. Default plans
are invalid. Semantic faults such as wrong content deliberately remain executable
plans that later checks must reject. No trusted-root or successful invariant
certificate follows from planning, and there is no worker/Services/storage change.

Native coverage includes literal 5 planning/4 footprint/1 preimage/3 byte/1 pair
counts, exact and every one-short policy, source identity, frozen copied quotas,
wrong-content planning without false validity, empty complete source, hash-disabled
operation, 1,000 ARC retirements and strict payload/reason/private/nominal guards.
Run `make unit SUITE=state_account_audit_plan`.

Observed locally: selected native suite, 3 strict runtime guards, 7 exact compiler rejections and genuine positive control passed; inventory and pinned formatting passed. 1,000 ARC cycles retained 209,712 bytes before and after.
