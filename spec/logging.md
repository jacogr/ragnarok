# Shared application logging

## Scope and ownership

This layer builds on [JIP-1 host logging](pvm-host-log.md). It adds an independent diagnostic
facility in `src/lib/logging.nim`, not a state/consensus event journal. The application owns one
noncopyable, fixed-address `Logger`. Producer handles borrow that owner and its immutable filters;
all producers, service callbacks and execution workers must retire before `close`. Close drains
accepted records, joins the single native writer and releases its lock/condition. Sink contexts
outlive that join. Handles never own a guest memory snapshot. Restart advances a nonwrapping
lifetime generation, so an old handle cannot submit to a restarted owner. The owner itself must
still exist when inspecting a retired handle. Default handles are disabled for ordinary logging.

The default sink writes its worker-owned immutable batch directly to POSIX stderr, handling
partial writes without sharing the runtime's mutable stream object. OS output errors discard the
remaining batch; diagnostics never become guest or application protocol errors. A custom sink
borrows bytes only for its synchronous call and must not retain them, raise, close/restart its
logger or recursively log through it. `processed` counts records passed to a sink, not bytes
durably written. A blocked sink can delay shutdown indefinitely; no IO deadline is claimed.

## Filters and output

`--log-level info,pvm=debug,network=warn` selects a global threshold and component overrides.
Default is `info`. Levels, in increasing verbosity, are `off`, `fatal`, `error`, `warn`, `info`,
`debug`, `trace`. Targets are `startup`, `pvm`, `telemetry`, `rpc`, `network`, `storage`, `app`.
Target-only overrides keep `info` elsewhere. Spellings are exact, duplicate options/targets and
malformed policies are rejected; a global threshold must precede target overrides. The same flag
is available in dedicated command grammars and offline trace checking. No environment/global
mutable policy is introduced. This increment does not add dynamic runtime reconfiguration.

The `log` template checks filters before evaluating message expressions. Fully disabled policy
starts no output thread. Records have a `[level][target] ` prefix, escaped non-ASCII/control bytes
and exactly one physical newline. Each complete record is capped at 2048 bytes, including a visible
truncation suffix. Callers remain responsible for bounding enabled message construction; the
record cap bounds encoding/copying, not an arbitrary caller's formatting work.

A fixed 256-record ring stores plain owned bytes, with batches of at most 16 records. Producers
use `tryAcquire`, never wait for queue space or perform sink IO. Busy/full queues drop new records.
Accepted records preserve queue admission order; records from concurrent producers have no stronger
ordering guarantee. Relaxed `accepted`, `dropped`, `processed`, `batches` counters are inspectable
and wrap modulo 2^64. A final warning reports dropped records outside the queue when startup
warnings are enabled. Turning that target off also suppresses this summary. This is a deliberate
lossy diagnostic policy, unsuitable for required audit records or command responses.

## Application and PVM integration

Startup, RPC/telemetry setup and network peer events use the shared sink. Future instrumentation
can use the other named targets; this increment does not migrate every existing status line.
Command stdout results/readiness markers and immediate setup failures retain their existing
contracts. These outputs can still block their callers and are outside the queued facility.

The explicit handle travels through candidate execution policies and authorization, refinement
and accumulation dispatch contexts. It is not serialized state or a protocol resource budget.
JIP-1 levels map 0=fatal, 1=warn, 2=info, 3=debug, 4=trace; unrecognized numeric values require
trace verbosity. Host 100 still charges exactly ten gas and returns WHAT, including filtered or
dropped diagnostics. Filtering happens after charging and before guest memory reads, allocation
and escaping. Both complete guest fields must validate before any record is submitted. Local
4096-byte per-field admission remains, followed by the shared 2048-byte output cap. This may
truncate a previously longer console line without changing guest state. The default unconfigured
library host adapter retains its original synchronous stderr behavior for compatibility; application
execution supplies the configured handle, including when policy is off.

## Completion evidence and limits

On macOS arm64 with pinned Nimony `4724f66c2e01b17810c844f26575b2317995fda2`, checked ARC/Clang
release tests exercise disabled lazy formatting, escaping/truncation, policy parsing, generation
retirement, two concurrent producers and joined shutdown. A controlled blocked sink admits every
remaining queue slot, then deterministically counts 31 dropped records while producers continue;
release and close drain all accepted records and preserve FIFO. PVM tests verify identical gas,
registers and memory for filtered records, plus admitted warning output. These are correctness and
bounded-work witnesses, not an equal-output throughput speedup claim.

`tests/models/logging_writer.nif` models the real queue/batch bounds, locked admission/take/wait,
unlocked sink work and close/join guards. The base passes; removing capacity, draining or either
wakeup produces an invariant counterexample. The close-during-sink witness is reachable. All six
cases agree between serial and four-worker checks. The model does not prove payload/FIFO,
OS-output liveness or the caller's producer-retirement precondition; native tests and explicit
ownership contracts cover those separate obligations.

Run `make unit SUITE=logging`, `make unit SUITE=pvm_host_log`, `make unit SUITE=app_options` and
the affected PVM host/dispatcher suites, `make check-inventory`, `make format-check` and the model
checks. Local all-source semantic smoke covers all production modules plus the main entry point.
The application build and eight CLI process checks passed (help/version, default/off/override,
invalid/duplicate policy and a dedicated command). AddressSanitizer passed the concurrent logger
suite. Actual ownership lowering rejects logger duplication with the expected `=dup` diagnostic.
The affected authorization, refinement, accumulation and host-gas suites passed with unchanged
occupied-memory baselines across 1000 cycles. Inventory, repository formatting and diff checks
passed. Logs are retained under `build/ci/logging-*` and `build/tests/logging-*` in the isolated
logging checkout. Full Linux CI and whole-client parity are not claimed by this local evidence.
