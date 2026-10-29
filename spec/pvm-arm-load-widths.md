# ARM guarded load width coverage

## Scope and authority

Independent lowering of Gray Paper indirect reads124..130, retaining the canonical
PVM checks and pinned PolkaVM as a compatibility oracle. Existing native reads
support unsigned64 only; the trial adds unsigned8/16/32 and signed8/16/32 forms.
No source, toolchain or upstream pins change.

Both first-read-plus-arithmetic and transactional multi-read spans reuse the same
invocation-owned readable descriptors, modulo32 address calculation, protected
prefix/top guards and conservative eight-byte region-extent proof. Narrow reads
near a region end may fall back even when canonical access would succeed. No check
is weakened. Any narrow/signed member disables the shared scaled64-bit window;
each read retains individual original guards. Successful complete spans publish
registers once; refusal leaves them unchanged before canonical replay. Stores,
headers, host calls and other observable boundaries still terminate spans.

No frame/cache fields, ownership, source prices, budgets, handler ABI, reservation
or public default changes. Existing130 encodings and word-window paths remain.
Native instruction selection is cold and closed over the seven validated opcodes.

## Qualification gate (pending)

Keep all existing opcode, source/gas/paid-prefix, memory permission/fragmentation,
host resume/remap, source snapshot, stream transfer, refusal and ownership checks.
Strengthen the existing124..130 source witness to require real native work for all
legal nonempty map cases. Extend mixed read spans across every later load width,
including derived address aliases, later faults and all three price policies.
Add24,843 independent native literal cases: all13x13 coordinates, seven widths,
seven sign/high-bit values and three descriptor regions, with all13 registers
compared. Old LDR64 direct/span/window matrices remain unchanged.

All native builds, execution and profiling are CI-only. Require the full seven
workload both-order public comparison against the exact paired-shift parent,
complete state/host/source checks, fresh private compiler caches/equal-image
controls and calibrated cold/reused profiles. Constructors/cold/reused scopes
remain separate. Keep only a useful measured gain without material regressions;
otherwise restore this isolated runtime and retain meaningful evidence. No timing
claim before qualification.
