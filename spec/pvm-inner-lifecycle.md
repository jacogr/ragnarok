# Refinement inner-machine lifecycle

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`pvm_invocations.tex` Omega_M/Omega_X and fnmemgas, `definitions.tex` M/X gas,
`pvm.tex` deblob; vectors `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.
No pin or established interpretation changes.

Scope: hosts 9 (machine) and 14 (expunge), a private immutable map of at most
63 inner machines, and dispatcher/invocation integration. Each run starts empty.
Creation charges 1862+ceil(112*length/1024) without overflowing, then checks FULL
before touching guest program memory. Read failures panic; invalid deblob/entry
returns HUH. Success uses the smallest absent natural identifier, empty inaccessible
zero memory, requested PC and uncharged flag. Expunge charges 335, returns WHO for
an absent full-width identifier, otherwise returns its PC and removes only that row.
Gas underfunding precedes mutations and keeps the exact terminal deficit.

Separate finite item, individual-program, retained-program-byte and jump policies
are local refusals. Empty inner RAM retains its page policy for future allocation;
creation itself materializes no pages. They never fabricate FULL/HUH/OOG or partial successors.
Program capture is bounded before scanning/copying; a policy refusal may precede
permission/deblob validation of oversized input. Protocol FULL still precedes all
program access and local program policies. Valid default zero policies permit no
creation, while default opaque map owners are invalid. Input/result bytes and
metadata cannot mutate saved snapshots. Explicit charged-response initialization
preserves the caller memory on present/absent deletion and OOG; fresh optimized
ARC loops check both owner release and the retained readable response bytes. Programs shared between map generations
remain immutable, acyclic ARC owners. Deletion releases retained byte accounting
and the lowest hole can be reused. No public mutable slot map is exposed.

Completion checks: original literal blobs and real guests; costs at memory-gas
rounding boundaries and maximum lengths, exact gas/debt; FULL/read/deblob priority;
all 63 slots, hole reuse and high identifiers; independent policies; immutable
snapshots, copied views, replay isolation and fresh 1,000-cycle ARC release;
optimized result-access guards and compiler privacy/nominal rejections. Regress
refinement dispatch, normalized invocation and their changed guard consumers.

Local evidence: checked optimized native `pvm_inner_lifecycle`, `pvm_inner_dispatch`,
`pvm_refinement_dispatch` and `pvm_refinement_outcome` pass, each with fresh
1,000-cycle unchanged ARC occupancy. Five new optimized runtime guards, fourteen
outcome regression guards and five exact compiler privacy/nominal rejections pass.
Verification inventory, nineteen inventory/provenance Python tests and pinned
formatting pass. These are local macOS results; exact-head Linux CI is independent.

Host 12 now follows [the page-management contract](pvm-inner-pages.md).
Hosts 10/11 now follow [the transfer contract](pvm-inner-transfer.md); invoke remains gated. No nested execution,
report construction, state composition or publication changes. Next: inner memory
transfer/page management, then invoke and work-package report integration.
M1 framing is complete; full state serialization and complete refinement remain open.
