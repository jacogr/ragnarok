# Current PVM durable publication

## Scope and authority

Pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` remains the protocol authority.
This adapter adds no protocol interpretation or pin changes. A genuine `PreparedCurrentChainUpdate`
can now stage journal context, commit storage and install canonical/RPC handles under exclusive
ownership. Legacy update types remain separate. Disk IO runs only at startup or on an excluded
native worker, never in dispatcher callbacks.

## Contract

The disk snapshot must match the application parent by exact identity. The selected context must
match the complete encoded application history, chain identity, profile and generation. Preparation
captures validated context and generation once. Default/current publications carry no extractable
update; private immutable ownership retains the genuine prepared candidate without replay.

Commit checks the original context and generation again and preserves actual storage failures,
including IO uncertainty. Canonical/RPC installation occurs only after confirmed commit. Enabled
RPC requires the exact current lease and history before disk IO. A refused or replayed publication
cannot advance the head. Restart uses existing full-state local history validation for either backend.
This synchronous adapter does not yet wire current preparation into the worker/handoff scheduler.

## Completion checks

`make unit SUITE=pvm_current_disk_publication` exercises genuine current execution with report,
preimage and authorizer effects through single-file and managed storage, canonical and RPC modes,
refusals, stale publication, reopen, retained finality and 1000 ARC preparation/release cycles.
Legacy `disk_chain` and `managed_disk_chain` check the shared context helper. Source-owned privacy,
nominal and runtime probes retain exact diagnostic contracts. Run module, inventory and format checks.
Evidence is local macOS ARC/Clang; exact-head Linux CI and complete JAM parity are separate gates.

Local macOS validation passed: 304 source modules; the current disk publication and both legacy
disk suites; one exact runtime guard, two compiler rejections, inventory and formatting. Both current
physical backends and canonical/RPC modes passed; 1,000 ARC preparation cycles retained identical
occupied memory. Linked native and runtime checks ran serially. Linux CI remains separate.
