# x86 checked-read resident staging checkpoint

This prototype is based on #2008 at `76c008f121c160206adea50f426016ab55129488`.
On Linux x86-64 the existing `pvmX86ResidentProof` selector activates it in a
`pvmX86Jit` build. The candidate shares the existing certified guard loop and
scalar emitter. It uses the original stack emitter when more than six guest
registers are dirty. The standard production selectors still choose stack
staging.

The resident leaf borrows the register file in RDI and the existing extent table
in R10. It saves only the mapped SysV GPRs and loads only resident slots whose
first access is a read. Read-only slots use the borrowed file. Existing loads
consume the old low 32-bit base before assigning an aliased destination. Every
miss targets an exit past guest-file publication. Success publishes the dirty
set once. Both exits restore the same saved registers.

## Scope of the direct oracle

Build `tests/performance/pvm_checked_read_resident_witness.nim` with the pinned
Linux x86-64 Nimony toolchain, checked release ARC/Clang ThinLTO, and
`-d:pvmX86Jit -d:pvmX86ResidentProof`. Success requires the exact output line
`PVM_CHECKED_READ_RESIDENT_OK`. Both published images are checked through the
real two-borrow ABI with all six SysV GPR sentinels. The candidate also enters
through the standard checked-read bridge. Every guest register and the source
memory bytes are compared on success, final-load refusal and recovery. The
three-dirty fixture has a mapped load-base read before its first write and a
wrapped self-aliasing load. The six-dirty fixture adds a mapped scalar read
before first write and uses R15. The seven-dirty fixture compares its selected
bytes to the original stack emitter.

The witness can dump raw bytes with `RAGNAROK_PVM_CHECKED_READ_RESIDENT_DUMP` set
to `stack`, `resident`, `six` or `seven`. The stack fixture should match the
independently qualified 509-byte reference with SHA-256
`6f3ac88b10342f2d11cda040aec4f7555d3c8e15f67442303f19aff078f396d2`.
A static relocation of that golden predicts a 474-byte resident fixture with
SHA-256 `2f16ca51b7ff9998cd74bffded51edd7c92458d0e0fd95e811e299413a1534b0`.
It preserves the 30 guard branches and directs each all-extent miss to the
restore-only return. This is an independent byte model. Native compile, emission
and execution qualification are pending.

For the pinned DOOM tick leaf at PC 530594, live-ins are r0, r1 and r12, while
dirty slots are r3, r6, r9, r10 and r11. With no overlap, the modeled resident
leaf needs zero mapped preloads and zero guest spills. Static register-file,
stage and host-save memory accesses go from 87 to 22 per successful leaf.
The 22 include seven borrowed-file reads, five publication stores and all ten
host save and restore accesses. The estimated 1,259-byte image retains the
original seven checked loads. These counts give no CPU estimate.
