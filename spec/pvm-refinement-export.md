# Refinement export

Implement GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`pvm_invocations.tex` Refine Functions / Omega_E (host 8), and `definitions.tex`
CgasE=3521, Csegmentsize=4104, Cmaxpackageexports=3072. Preserve vector pin
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` and all dependency pins.

Scope: an immutable ordered export accumulator and one host response plus successor.
The caller supplies the package segment offset and dispatches host 8. This does not
certify a refinement invocation, attach outputs to a work report, construct availability
data, or change state composition/publication. Reuse the existing nominal FetchSegment
representation so export segments can become authenticated refinement inputs later.

Charge 3521 before any guest read. Underfunding returns exact terminal debt with prior
registers/memory/exports. Read min(r8,4104) bytes at r7; empty ranges permit every pointer.
Unreadable ranges panic before capacity checks, retaining r7 and the old export owner.
Only then return FULL (2^64-5) when offset+count>=3072. Compare by subtraction after
checking offset to avoid overflow, including full-width offsets. Otherwise append exactly
one independently owned zero-padded segment and return the old offset+count in r7.
All other registers and guest memory remain unchanged.

Local item/byte caps bound the complete successor before allocation. They are independent
of the fixed bounded guest read, apply only to a successful append, and cannot become
protocol FULL/panic. Default owners/results and refused results expose no payload.
Segment access returns a value copy; sequence metadata shares only immutable acyclic
segment owners. Old owners remain usable after append, response mutation or extraction.

Completion tests: independent segment contents and zero padding, clipping, zero lengths,
read-only/cross-page/missing/high pointers, gas edges, exact export indices, protocol-full
versus local caps, refusal precedence, detached/forked successors, genuine generic host-loop
integration, optimized result/owner/index guards, compiler privacy/nominal rejection and
fresh 1,000-cycle ARC release. Accumulation dispatch must keep host 8 unknown.

Local evidence: checked optimized native `pvm_refinement_export`,
`pvm_accumulation_dispatch` and `pvm_fetch_inputs` pass with fresh 1,000-cycle
unchanged ARC occupancy. Six runtime owner/result/index guards and four compiler
privacy/nominal rejections pass. Verification inventory, 19 inventory/provenance
Python tests and pinned formatting pass. These are local macOS results;
exact-head Linux CI remains independent.

Next: bounded refinement invocation/context assembly and remaining inner-machine hosts.
Complete refinement and whole-block parity remain open. M1 framing is complete;
full state serialization remains open. Existing specification gates remain unchanged.
