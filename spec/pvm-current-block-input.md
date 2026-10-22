# Current signed raw-block receiver

Pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains authoritative.
This reception adapter changes no protocol semantics, pins or storage formats.

`CurrentBlockInput` retains exactly one admitted raw extent, original application history,
immutable ancestor handles and frozen `CurrentCandidateLimits`. Its nominal generation cannot
be used as a legacy reception ID. Admission and fragment callbacks perform only bounded copying
and cached context checks; they never hash, run guests, install heads or perform disk IO.
Busy, stale callbacks, truncated/overlong extents and invalid resource/profile bounds grant no
new authority. Cancellation retires only the matching active generation and never resets its counter.

Explicit preparation consumes Ready input once through authenticated current candidate APIs.
Only complete current execution, whole-state composition and capture expose
`PreparedCurrentChainUpdate`; typed codec/current-candidate failures expose no successful prefix.
Ancestor discovery retains the original current report prefix, generation and frozen policies.
Raw bytes retire once this prefix owns the block. Resumption preflights replacement ancestors
before retaining them; lookup checks and execution run on a later preparation turn. A changed
original history refuses before execution. Fetched headers confer no canonical-state authority.

Optional synchronous enqueue checks current handoff capacity before preparation. Pending and
unacknowledged Finished both preserve Ready input for retry. This layer does not switch Services,
network producers or the native preparation worker; those are subsequent lifecycle consumers.
Existing legacy receiver APIs remain separate during migration.

Completion witnesses: genuine signed fragmented blocks; independent complete current root equality;
owned fragments/ancestor containers; no-hash reception/backpressure/resume; exact generation,
profile, malformed/trailing/size, stale-parent and typed capture failures; genuine lookup suspension
and resumption; current handoff installation/acknowledgment; 1,000 ARC cycles. Runtime extraction
and privacy/nominal/actual ownership-lowering probes are source-owned. Local macOS evidence and
exact-head Linux CI remain separate; this is not complete JAM/ThinVRF or production Services parity.

Local macOS ARC/Clang validation passed: current raw receiver and current candidate native suites,
independent complete roots and real lookup resumption, 1,000 release cycles in each suite, eight
runtime extraction guards, three privacy checks, nominal generation rejection and actual ARC
`=dup` lowering rejection. All314 source modules, inventory and pinned formatting passed.
Linked checks were serial. Exact-head Linux CI has not been requested.
