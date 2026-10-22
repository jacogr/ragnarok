# Signed block to prepared current candidate

Pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains authoritative;
this adapter adds no protocol interpretation or pin changes.

`prepareCurrentCandidateReports` shares existing authenticated block/report preparation, freezes
current resource policies, and retains the selected head's exact parameter tuple. The opaque current
prefix supports ancestor-demand planning without running guests. `completeCurrentCandidateReports`
rechecks exact original history before completing reports, planning original queue/round, running
the current sequence and whole-state builder, and capturing one private prepared chain update.
`prepareCurrentCandidate` uses this same split path for one-shot consumers.

Only complete success exposes `PreparedCurrentChainUpdate`. Actual prefix/report/queue/round/
current-completion/capture failures remain guarded and retain no successful prefix. Legacy execution
and state composition are never called. No application, RPC or disk head changes during preparation;
existing current installation/durability APIs consume the returned update afterward. Worker and
transport scheduling remain separate integration work; full JAM/ThinVRF parity is not claimed.

Completion checks use real signed blocks and compare entire current state roots against existing
phase-by-phase witnesses; one-shot/split equivalence, exact original-head refusal, complete refusal
causes, provided preimages, 1,000 ARC cycles, runtime/nominal/privacy checks and existing candidate
regressions. Local macOS evidence remains distinct from exact-head Linux CI.

Local macOS validation passed: 305 source modules; current and existing application candidate native
suites; real signed current blocks with/without provided preimages; complete root equality for split
and one-shot entry points; stale/absent/queue/execution/capture refusals; seven exact runtime guards,
two compiler rejections; 1,000 ARC cycles; inventory and formatting. Linked checks were serial.
Exact-head Linux CI remains separate.
