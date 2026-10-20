# Refinement result and gas normalization

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, `pvm.tex`
Argument Invocation R/Psi_M and block gas affordability, `pvm_invocations.tex`
refinvocation/Psi_R, and vector pin `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.
Pins, grow_heap adoptions and existing specification gates remain unchanged.

Run only an opaque prepared bootstrap, using its own host capture and declared gas.
No public normalizer accepts caller-supplied CPU/outcome/export/gas tuples. BAD/BIG
bootstrap selections return the matching WorkKind, empty exports and zero gas use
before examining trace/input tables or execution/output policies. Default bootstrap
owners are local refusals, not BAD.

For Ready, capture the original environment and run the bounded dispatcher internally.
Only complete execution is normalized. Halt yields Success with the existing Psi_M
return-buffer rule: a wholly readable natural r7/r8 interval yields its bytes; any
unreadable byte yields successful empty output. Empty intervals ignore the pointer.
The output cap is a local policy, applied only after readability; exhaustion exposes
no partial result. Halt retains that run's export sequence, including on empty output.
Panic and physical page fault both yield Panic; OutOfGas yields OutOfGas. All three
retain empty exports and no success byte payload.

Compute gas used as original allowance minus max(final gas,0), using the machine's
canonical nonnegative credit plus terminal deficit representation. Check remaining
credit<=allowance before subtraction. Host debt adds no extra consumption beyond the
allowance. Underfunded block pricing retains its prior positive credit, so an entry
block can yield OutOfGas with zero consumed gas. Adopted grow_heap zero-deficit OOG
still consumes its drained credit. Do not assume every OutOfGas consumes all gas.

Return one immutable acyclic final owner containing source bootstrap, result kind,
used gas, success-only copied bytes and selected immutable exports. Copied metadata
or extracted/mutated byte arrays cannot rebind the retained source or result. Local
capture, host and engine refusals keep their exact typed reason alternatives, without
partial CPU, exports, output or gas-usage metadata.

Scope ends at the Psi_R result tuple for implemented host execution. Malformed
metadata/envelope/program bootstrap gates remain local. Work-package I's Oversize,
BadExports and zero-segment replacement belong to report construction, not this
normalizer. No report publication, input/state-freshness authentication, light-state
support or state composition change is implied. Inner-machine lifecycle hosts 9/14
now run with explicit local policies; hosts 10–13 remain gated. See
[the lifecycle contract](pvm-inner-lifecycle.md).

Completion: real bound guests for halt/readability/empty/panic/page-fault/host and
instruction OOG; exact/capped gas, export retention/discard, BAD/BIG short-circuit,
independent local budgets and typed failure details, immutable/detached/replay
ownership, optimized result/reason/access guards, compiler privacy/nominal rejection,
and fresh 1,000-cycle ARC release. Regress the bootstrap and output components.

Local evidence: checked optimized native `pvm_refinement_outcome`,
`pvm_refinement_bootstrap` and `pvm_output` pass, each with fresh 1,000-cycle
unchanged ARC occupancy. Fourteen optimized runtime alternative/access guards,
nine compiler privacy/nominal/source rejections, verification inventory,
19 inventory/provenance Python tests and pinned formatting pass. These are local
macOS results; exact-head Linux CI remains independent.

Next: remaining inner-machine hosts and work-package/report result integration.
M1 framing is complete; full state serialization, complete refinement and whole-block
parity remain open.
