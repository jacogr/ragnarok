# Current canonical application and RPC installation

Connect genuine current composed sources and opaque prepared updates to the
existing ApplicationChain/RPC installation boundary. Current preparation returns
its own precise CurrentChainPreparationResult; no legacy completion or failure
is converted into current authority. Preserve the existing legacy overloads for
their explicit typed callers without automatic fallback.

Canonical-only installation requires exact original state and complete prior
view. Joint RPC installation additionally requires an open server with identical
ordered history/profile/finality and the exact optional exclusive lease. Install
current state/view and RPC view before bounded subscription work; do not rerun
guests, composition, capture or hashing. Keep the lease until its owner resumes
RPC. Subscriber overflow cannot undo an already installed head. Acknowledgment
requires exact installed candidate identity and does no additional work.

All preparation/IO/exclusion rules from the application design remain unchanged.
Disk consumers must still persist before installation; actual current disk
publication and worker/handoff integration remain subsequent work. Protocol pin
remains `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` with no interpretation change.

Completion witnesses: canonical-only and joint RPC adoption, exact child/source
identity, paused/exclusive lease enforcement, stale/foreign/closed/default
readiness refusal, no hashing during installation/acknowledgment, historical
aliases, guarded installation and fresh ARC evidence.

Local macOS ARC/Clang validation passed: 304 source modules; current application/
RPC, existing application and current prepared-update native suites; actual
loopback subscription/best-head delivery; three exact runtime probes and two
nominal compiler rejections; fresh 1,000-cycle ARC evidence; inventory and
formatting. Linked native/runtime checks ran serially. Linux CI is separate.
