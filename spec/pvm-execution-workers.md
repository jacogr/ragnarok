# Explicit execution-worker code lifetimes

## Scope

This is a local ownership/performance policy under the existing pinned GP 0.8.0 initialization,
execution and engine contracts. It changes no guest instruction, gas, PC, host, permission or
source-attempt rule and grants no state authentication or publication authority.

## Ownership and admission

`newExecutionWorker` creates an explicit sequential worker with one decoded JAM source and one
successful prepared-program slot. A default handle retains ordinary one-shot behavior. Workers
are never global and must not be used concurrently across threads. Copies share worker identity;
the last handle releases retained sources and native caches. CPU, initial arguments, RAM, gas,
callbacks and application source provenance remain invocation-local and never enter the cache.

Initialization rechecks envelope/argument/page policies before allocation. Decode reuse requires
exact captured encoded bytes, JAM decode profile, and identical program-byte and declared-jump
parse limits. Entry validation remains per invocation. Changes to RO/RW data, arguments, gas or
entry never reuse an old CPU or memory image. The byte comparison allocates no detached copy.
Failed initialization leaves the previous admitted code available.

Prepared reuse requires exact immutable `Program` identity, selected backend, gas-analysis cycles
and every execution resource ceiling. A different key replaces the one idle successful slot only
after successful admission. Failed admission is retryable and does not displace the old owner.
The old source may remain independently retained by published machines, as required by immutable
snapshot ownership; it cannot execute against a new cache identity. Retained occupancy is bounded
by the last admitted decode policy and last successful prepared policy, plus independent caller
handles. Stream/native limits are cumulative over a retained owner's lifetime.

Every callback runs under the existing exclusive prepared-owner lease. Any same-worker cache
lookup during that lease returns `PreparationError.Busy`, including a different source or policy;
it cannot evict the active owner to bypass same-owner reentry refusal. The host adapter translates
this to `PreparedProgramBusy`. No additional thread synchronization or cross-thread sharing is
provided by this API.

## Verification and consumers

`pvm_worker_code` checks literal initialization data, separate argument pages and gas, exact source
identity reuse, changed parse policy/code and invalid entry, prepared stream persistence, complete
resource/backend keys, refused-admission preservation, different-source callback reentry refusal,
terminal host PC/gas and independent retained memory, plus 1,000 complete ARC lifetimes.

This prerequisite alone does not claim application reuse or measured speedup. Consumer changes
must retain workers across actual application loops and measure complete invocation cost,
preparation work and immutable observations using independent expected state/host controls. Native
compilation, execution and measurements remain CI-only.
