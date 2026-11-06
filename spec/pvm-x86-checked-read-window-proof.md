# x86 checked-read window experiment

This source checkpoint is based on the qualified checked-read port at
`5fcf16e945df649f9a0c537a09ec374c226d7684`. It keeps the shared source certificate, arena entry,
Ready owner and paid checked replay. The selected x86 leaf checks one contiguous extent for
multiple reads whose common base is absent from the complete body write mask. The selector
counts aliasing load destinations as writes. Unselected reads retain the original byte emitter.

The extent guard forms the window start with the original wrapping 32-bit addition. It accepts
only a whole clipped readable extent. The frame's stack, writable and read-only allocations are
disjoint. Every grouped displacement and width fits the accepted hull, and the clipped hull
cannot wrap again. The leaf keeps the accepted host pointer in caller-saved R9. The guest
register file is written only in the success epilogue. Window or subsequent guard misses use
the existing refusal exit. A split-readable layout can complete under checked replay while
losing native coverage for that visit.

The pinned DOOM tick block at PC 530594 has five U64 loads from unchanged r1 in a 40-byte hull.
The reported 1,330-byte baseline matches the source byte ledger. The candidate's 810-byte size
is a static estimate pending a native byte dump. [Exact base qualification](https://github.com/jacogr/ragnarok/actions/runs/42275413634/job/128090377643)

Pinned semantic checks passed for the x86 witness, ARM64 witness, unsupported x86 selector
and x86 Ready-owner arbitration. Native link and execution are pending.

## Resume qualification

Use the existing `ci.yml` entry with `suite=bench-doom` and `pvm_architecture=x86_64` after the
exact branch and qualification scope are reviewed. Its native qualification runs before DOOM
sampling. Compare the branch's checked-read base with the settled integration before dispatch.

- The x86 qualifier compiles the direct witness with the pinned compiler and production
  Linux x86-64 selector. It uses `RAGNAROK_PVM_CHECKED_READ_BODY_DUMP=1` to check the independent
  509-byte golden from carrier `c43b7ad1a9e83ab9f6ba779117b8251d091f9be6`. Its SHA-256 is
  `6f3ac88b10342f2d11cda040aec4f7555d3c8e15f67442303f19aff078f396d2`. The value
  `window` dumps the 525-byte mixed-width fixture. Both receipts precede native entry and
  retain the exact bytes and linked binary digest.
  [Independent golden source](https://github.com/jacogr/ragnarok/blob/c43b7ad1a9e83ab9f6ba779117b8251d091f9be6/.github/qualification/x86-checked-read-golden.s)
- Run the normal witness for wrapped address formation, the exact clipped edge, the
  one-byte-short refusal, split-readable memory, and a late independent guard miss followed
  by recovery. Verify all registers and memory in the direct and interpreter oracles.
- Check the recorded hot DOOM image size and compare baseline and candidate on a matching
  runner CPU model with equal input, output, compiler, reference and measurement identities.
  Separate cold init, cold tick and reused tick by process order. Compare native calls and
  operations before interpreting ratios. A coverage change is a separate result from timing.
