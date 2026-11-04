# Private x86 resident register-access proof

This default-off ISA checkpoint requires `pvmX86ResidentProof`. It changes no source admission,
window preflight, gas/attempt ledger, handler, cache pool, owner, publication quota or public API.
Those semantics remain in the existing engine. This checkpoint establishes register access and
SysV preservation; trace planning and memory preflight require separate work. The pinned GP
register semantics remain unchanged.

`emitX86Operation` and `emitX86Branch` retain their existing signatures and canonical bytes.
Their single opcode switches use overloaded register accessors, expanded through a cold template.
The empty canonical access policy preserves original array loads/stores. The private resident policy
maps at most six guest lanes in ascending order to RBX/RBP/R12/R13/R14/R15. Unmapped lanes retain
canonical array access. Both operand values are consumed before an aliased destination changes.
The same scalar/branch implementations therefore cover shifts, signed low-word results, high
multiplication and aliasing; the resident backend has no second opcode semantics switch.

The private entry saves all six SysV GPRs (48 bytes), allocates40 context bytes and retains four
incoming pointer arguments at offsets0/8/16/24. The native entry's RSP modulo16 is8; the body RSP
modulo16 is0. Slot32 is reserved scratch. Every mapped guest lane is loaded once, including lanes
used only by a later body. A common exit flushes every initialized mapped lane without changing
RAX, releases40 bytes and restores all six saved GPRs. The owning publisher appends RET. There are
no internal calls and no retained invocation pointers. A future trace compiler must route all of
its exits through that exit and choose when preflights/debits may occur; this layer grants none of
that authority. It deliberately does not claim dirty-only spill optimization or completed trace
semantics.

`pvm_x86_resident_access_proof` is a private C test probe. Six live fixed-register sentinels
surround
an actual call to published bytes using four pointer arguments. A positive context control copies
the saved pointers/alignment into proof output, and a generated negative image deliberately
clobbers RBX after restoration. Its independent high-word invocation tag is produced by C, not by
the generated code. None of these controls is included by an ordinary build.

`make unit SUITE=pvm_x86_resident_access` owns the literal controls. Genuine decoded instructions
supply operand coordinates; no fabricated Frame/plan or PC-specific source installer is used.
The Linux x86 profile compares11,448 scalar cases with the portable evaluator and3,456 branch
cases with canonical lowering across six alias encodings, six masks and six full-width seeds.
The sequential mapped write/compare control also preserves untouched later-lane sentinels and
checks incoming argument slots, stack alignment and six preserved machine registers. Non-x86
hosts exercise construction only, without claiming native invocation. The opt-in cold image output
supports an artifact-only comparison of414 canonical scalar/branch encodings with the
isolated6ba47573 baseline.
Actual native ABI proof uses checked ARC/Clang ThinLTO in Linux amd64; emulation qualifies
correctness, not speed. Application guests, discovery, observer policy and performance work remain
outside this checkpoint.
