# Refinement code and argument bootstrap

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`pvm_invocations.tex` refinvocation, `accounts.tex` historicallookup/I,
`pvm.tex` standard initialization, and vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Pins and existing gates remain unchanged.

Bind one immutable complete-state snapshot, owned package, current item, configured core
and parameters. Resolve the work item's code hash at the package's lookup-anchor slot,
not the account's current code hash. Share the account/history lookup equation with host 7.
Missing account, preimage or historical availability selects BAD. Available preimages
larger than 4,000,000 bytes select BIG before materializing their payload, including the
metadata prefix in this size gate. These selections do not publish a CPU or arguments.

For eligible code, bound the complete preimage copy/hash, verify Blake2b-256 against the
item's code hash, and decode a canonical length-prefixed metadata blob followed by the
JAM envelope. Malformed code/framing/programs remain typed local preparation gates;
this layer does not invent BAD/panic normalization for these cases. A mismatched hash
is invalid supplied state. Existing preimage/request inconsistency is a local refusal.

Hash exactly the owned package's canonical consumed encoding. Build arguments as
compact core, compact item, compact service, compact payload length, payload bytes,
then the raw 32-byte package hash. Measure all fixed/variable extents before allocation.
Initialize only the resolved envelope at entry zero with the selected item's refinement
gas and these arguments. Derive heap geometry from the same envelope using the adopted
#538 zone reservation. There is no caller-provided replacement code/arguments/CPU/heap.

The ready owner supplies that exact CPU, state/package/current selection and parameters
to bounded host capture. Trace/extrinsic/import authentication and state freshness versus
the lookup-anchor block remain caller obligations. This verifies code commitments against
the supplied complete map; it does not authenticate a block, a light proof, state freshness,
or external input commitments. No state writes, composition or publication changes.

Completion: independent argument bytes/package-hash oracle, selected item/service/code
history, whole-preimage size boundaries, malformed metadata/envelopes/programs, separate
copy/hash/argument/package/page caps, default/invalid selection, backend failures,
immutable extraction/detached ownership, real execution via the bound host adapter,
private/nominal/result guards and fresh 1,000-cycle ARC release. Regress host 7 and dispatch.

Local evidence: checked optimized native `pvm_refinement_bootstrap`,
`pvm_historical_lookup` and `pvm_refinement_dispatch` pass, each with fresh 1,000-cycle
unchanged ARC occupancy. Independent frozen code/package-hash oracles and nonzero
envelope heap/stack witnesses pass. Eight optimized runtime guards, six compiler
privacy/core-domain rejections, verification inventory, 19 inventory/provenance Python
tests and pinned formatting pass. These are local macOS results; exact-head Linux CI
remains independent.

Next: outer refinement result/gas normalization and remaining inner-machine hosts.
M1 framing is complete; full state serialization, full refinement and whole-block parity
remain open.
