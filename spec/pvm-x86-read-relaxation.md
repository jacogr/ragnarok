<!-- Copyright (c) 2026 Ragnarök contributors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# x86 connected Read branch layout

The connected Read lowerer shares the metadata sealer with mixed loops. The
[sealer](../src/pvm/internal/x86_local_edges.nim) documents complete local-edge
metadata, disjoint instructions, boundary labels and the finite monotone contraction.
Each caller rejects an oversized original image before sealing. Read renderer retries
therefore retain their original ordering and conservative 4096-byte ceiling.

Contraction preserves every nonbranch byte, entry zero, branch condition and target.
The [Read lowerer](../src/pvm/internal/x86_jit.nim) retains its register saves, stack
frame, prepaid initial Read, seven-role gas/attempt ledger, dirty-page checks and
checked-header return ABI. Source admission and publication remain unchanged.

The frozen DOOM Read at source PC530594 emits 3830 original bytes and 3350 sealed
bytes. Its 199 recorded edges match the independently disassembled graph; 133 edges
contract in two passes. The sealed bytes have SHA256
`5fb808b63c53974b19eadb1a85cff3267e100142a3f710355f6a50194870c49b`.
The same source-derived IR and stream headers reproduce the retained original image
exactly. Existing mixed-loop and read-only encodings remain byte-identical.

The maintained [layout suite](../tests/unit/codec/test_pvm_x86_mixed_loop_layout.nim)
covers all sixteen Jcc conditions and JMP, signed limits and neighboring misses,
scalar-byte preservation, a multi-pass cascade, and label255 through the general
label view. [Read execution](../tests/support/pvm_read_cycle_execution.nim) owns
the native ABI, role, budget, fault, dirty-page and register-overlap checks. The
[readiness witness](../tests/support/pvm_connected_read_readiness.nim) expects the
new x86 extent while retaining every original work and lifecycle assertion.

ARM lowering is unchanged. This change only packs the existing Read leaf; it does
not combine its context or checked-header dispatcher with the mixed-loop receipt
ABI. A Read3350 plus read-only278 layout would occupy3638 bytes at sixteen-byte
alignment, but no heterogeneous arena is implemented or qualified here. No timing
improvement is claimed.
