# Source-bound effective supervisor selection

Scope: current Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`text/accounts.tex`, eq:effectivesupervisor. For a present service, select its
nominee only if that nominee exists and its creation slot equals the recorded
expectation; otherwise select the service itself. No recursive/transitive
supervision, cycle rejection or extra temporal rule is inferred.

The input is an immutable complete service directory. Two bounded binary lookups
obtain exact captured metadata. Missing target returns `NoService`; absent or
recreated nominee produces the specified self fallback and an explicit fixed
decision reason. Default provenance does not establish absence or authority.
Success privately retains the original directory; copied fixed observations do
not mutate it. Default observations remain invalid and all result payloads are
guarded. No hashes, detached payloads or additional arrays are needed.

This independent reader does not modify the existing accumulation authorization
implementation, Services, storage APIs or root authority. It is not authorization
for a different runtime source and confers no trusted-root or full STF validity.

Native coverage includes correct incarnation, missing/recreated nominee, self
nomination including stale creation expectation, a two-service cycle's one-hop
results, absent target at domain boundaries, exact retained source and immutable
copies, hash-disabled operation, 1,000 ARC retirements and strict payload/private/
nominal guards. Run `make unit SUITE=state_service_supervision`.

Observed locally: selected native suite passed all incarnation/absence/cycle
cases and hash-disabled execution. 1,000 ARC cycles retained 340,976 bytes before
and after. Two strict runtime guards, five compiler rejections and genuine
selection control passed; inventory and pinned formatting passed.
