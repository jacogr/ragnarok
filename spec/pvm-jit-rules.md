# Shared native opcode rules

`src/pvm/internal/jit_rules.nim` contains value-only GP 0.8 opcode descriptions and the scalar
subset currently lowered by both native architectures. It owns no source, execution state,
allocation, backend selection or machine encoding.

`indirectMemoryAccess` requires an opcode in `120..130`; callers establish family membership
before converting to that range. Its descriptor names the byte width and store, unsigned-load
or signed-load semantics. ARM mixed individual/window emitters and their cold group planner
consume this shared description. Their encoding switches, conservative memory guards and
admission limits retain their existing behavior.

`supportedScalarOpcode` holds the previously identical non-exiting arithmetic whitelist.
`supportedArmOpcode` and `supportedX86Opcode` remain architecture entry points forwarding to
that common subset. Future capability differences belong explicitly in those wrappers.
Source structural seals, native receipts, arena policy and machine layout remain separately owned.

`make unit SUITE=pvm_jit_memory_rules` checks every indirect store/load width pairing with
independent literal register results and full-page byte expectations. Two aliased store/load
pairs use either one base register for grouped windows or separate bases for individual guards
in the first pair. The second pair retains an anchor window in both modes, preserving existing
admission's requirement for at least one window. Separate destinations check both loads.
On a supported ARM host, positive mixed publication/completion and window counters establish
actual native use. Complete CPU/gas/attempt bookkeeping also matches forced interpretation.
Existing arithmetic, guarded-memory and refusal witnesses retain their independent references.
