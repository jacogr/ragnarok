# Computed guest gas exhaustion selects exceptional storage

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
pvm_invocations.tex exceptional selection, write (5) precharge and checkpoint
(18); vectors `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Author the real original work item with accumulation gas3500 before its first
execution/report, root, signing or source binding. Refinement credit remains
10000. The accumulation body writes three bytes, optionally checkpoints, then
attempts the same-key two-byte overwrite. Credit covers the prepaid instruction block, first write and
checkpoint, but the second host precharge exhausts it before mutation.

Completion: actual termination OutOfGas/Exceptional; historical report reservation
and consumed gas both3500; no-checkpoint storage absent, checkpoint storage the
first three bytes with38-byte footprint. Selected outcome, finalized/composed
state and canonical store/head agree; source parents remain unchanged. Existing
halt/panic/deposit/budget controls and gas/activity/finality/replay/ownership
checks remain covered. Independent runner limits are unchanged.

Next: exercise actual computed report availability in a subsequent authenticated
block, so new pending work can enter accumulation through maintained assurances
and queues. M1 framing complete; full serialization, whole-block parity and full
chainspec equivalence remain open.

Observed local evidence: both authored 3500-credit programs genuinely terminate
OutOfGas/Exceptional and consume exactly3500, matching their historical report
reservation. Without checkpoint the selected row is absent; with checkpoint
key[11]/value[21,22,23] and38-byte footprint survive selected context, stopped
finalization, composition, canonical store and best-head state. The later write
is refused before mutation. Existing funded halt, panic, underfunding, checkpoint
halt/panic and local-resource controls remain covered.

The seven-mode suite passes1000 ownership cycles (7000 prepared child
publications) with ARC2933856/2933856 bytes. The default chain suite also passes
1000 cycles (1079904/1079904 bytes), together with28 optimized chain guards,
inventory and pinned formatting. Prior compiler checks remain valid for1703
unchanged production/native/compiler-fixture/toolchain inputs. Tooling and
registrations are unchanged. These are local macOS checked-release results; no
remote CI was requested.
