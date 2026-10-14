# Bounded Bandersnatch offload proof

This M2/M3 increment keeps one native QUIC I/O dispatcher and adds exactly two fixed OS workers
per offload listener. Each language uses its existing typed Bandersnatch adapter over the same
maintained Rust ABI, historical backend, locked Cargo closure and pinned SRS. No dependency,
compiler, primitive, protocol revision or optimization changes.

The references remain Gray Paper v0.7.1 at `1c979cb59bb800f92ffff083a2701004dfc6cd33`, its
[Bandersnatch appendix and Safrole ticket rules](../spec/bandersnatch.md), and JAMNP-S
[`simple.md` at `439c45aad135dc654b3de6f56d7d694fd02b7aa8`](https://github.com/zdave-parity/jam-np/blob/439c45aad135dc654b3de6f56d7d694fd02b7aa8/simple.md),
Encryption and handshake, Streams and CE 143. Public fixture inputs/output are checked against
the pinned official JAM tiny Safrole vector before building.

## Test application policy

CE 143 still carries kind 143, E4(32), an exact Blake2b-256 preimage key and FIN; the response is
E4(3), three preimage bytes and FIN. No RingVRF network schema or new CE kind is defined.

The test lookup for bytes `01 02 03` requires verification of an official tiny-ring ticket first.
The native worker supplies the explicit input `jam_ticket_seal || entropy || attempt` (48 bytes),
empty additional data, capacity six, 144-byte root and 784-byte proof; each successful result must
match the independent 32-byte official output. A separate lookup for `04 05 06` requires no crypto
and demonstrates healthy networking while workers are occupied. A lookup for `07 08 09` uses the
wrong ticket domain and must fail without a response. This is a bounded application scheduling
experiment, not a normative relationship between CE preimages and Safrole tickets.

Default peer builds create no workers and link no Bandersnatch Rust calls. Offload peers are
compiled separately with Nim `-d:offload` / Odin `-define:OFFLOAD=true`; the explicit listener mode
cannot silently fall back to synchronous I/O-thread verification.

## Ownership and scheduling

- Four fixed slots bound all queued, running and completed-but-uncollected jobs together. Two
  running jobs leave two additional slots; the queue does not grow with connections or streams.
- Admission copies fixed arrays into a slot, then overwrites its temporary source. Each worker
  takes its own fixed value copy. There are no ARC references, borrowed slices, mutable source
  buffers, native stream handles or TLS pointers in a cross-thread job.
- Each worker creates and destroys its own immutable Rust setup on that same thread. Nim uses ARC
  locally; Odin workers use their default allocator context, with no shared I/O tracking allocator.
  The two thread handles are created/released by the I/O owner.
- A mutex protects slot transitions and completion state. Rust runs outside that mutex. Queued
  cancellation frees its slot immediately. Running cancellation marks the original owner for
  discard; its bytes/slot remain retained until the synchronous verification batch returns.
- Nominal monotonically increasing generations identify jobs independently of reusable stream
  handles/slots. Only I/O collects tagged completion results, checks the matching live stream and
  enables response writes after verified success. Pending polls expose no completion metadata.
  Worker threads never call QUIC, perform UDP I/O or retain stream owners.
- Completion polling shares the existing bounded I/O tick, at most ten milliseconds, rather than
  creating a timer or notification thread. Transport deadlines, healthy lookups and peer expiry
  continue on that dispatcher.
- Shutdown stops native callbacks and cancels their jobs before pool release, stops admission,
  drops queued/completed jobs, releases test holds, joins both workers, and only then releases the
  synchronization/storage owners. Running Rust calls cannot be forcibly interrupted.

The local value copies, fixture bank and two setup owners are fixed additional storage beyond
four logical job slots. No claim is made that cancellation can reclaim an input while Rust still
borrows it, or that these language APIs enforce unique ownership in the compiler.

## Controlled workload and gates

Run `python3 interoperability/test_quic_offload.py --fetch` for a full native build, or
`python3 interoperability/test_quic_offload.py --reuse-native` after the existing pinned QUIC and
Bandersnatch builds. `--skip-build` explicitly reuses the labelled offload peers. Logs and JSON go
to ignored `build/offload`; only explicit diagnostics are included in Linux CI uploads.

Each language listener survives ten waves with mixed Nim/Odin one-query clients. A trusted
control file holds the workers before Rust to make two-running/two-queued capacity and
cancellation deterministic; that hold is explicitly excluded from crypto activity. Each wave:

1. Fill all four slots and reject a fifth request without harming other peers.
2. Complete both languages' cheap lookups while the pool is held and full.
3. Kill one queued and one held-running client; observe queued release and retained running input.
4. Admit a replacement with a new generation, release the hold, and complete cheap lookups during
   actual Rust verification batches. Every positive verification must match the official output.
5. Check the wrong-domain failure, then healthy lookup recovery.
6. Explicitly reset a further query during an actual verification batch; retain and then discard
   that running owner after the batch returns.
7. Require all connection/stream/job owners to retire before sampling the unchanged listener.

One valid job normally calls the primitive once. The controller selects 128 repeated real calls
per job to create a bounded compute window, with a hard trusted configuration limit of 256.
`busy` covers the verification batch, including tiny gaps between calls; it does not instrument
inside a Rust call. This is a responsiveness/lifetime gate, not a throughput benchmark or speed
optimization. The explicit offload listener alone permits a five-minute overall test deadline;
other proof modes retain their existing two-minute bound.

Focused selftests also keep four completed results uncollected and reject another admission,
check exactly-once tagged collection, and join two held workers with two queued jobs. The final
networked shutdown occurs with two actual verification batches running and two jobs queued,
checking that join waits for borrowed Rust input to retire.

The live service must have exactly three OS threads, RSS below 256 MiB and no admission above four
jobs. Eight post-warmup idle samples must vary by at most 16 MiB RSS, two descriptors and 64 KiB
language allocations. After transport destruction and worker join, Odin must have zero tracked
allocations/nbio operations; Nim must stay within 64 KiB of its initial ARC allocation counter.
These finite aggregate observations do not replace C/TLS/Rust allocator instrumentation or audits.

General job scheduling/fairness, consensus admission quotas, full-ring load sizing, independent
JAM interoperability and the remaining crypto audit/policy gates are separate work. See
[observed verification](../results/quic-offload.md). No language is selected by this increment.
