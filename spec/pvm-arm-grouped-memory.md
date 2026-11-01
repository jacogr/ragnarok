# Preserved ARM64 grouped-memory prototype

**Performance hold.** This draft preserves correctness-tested machinery. No
grouped-memory speedup is established, and Linux performance qualification was
not requested. Reuse requires a new measured candidate.

## Scope and authority

Accepted parent: `a0997ac1469113ba1f65b4f4bdde9c9462cf138e`. GP0.8.0 and the
existing memory-ordering, gas and source-attempt contracts remain authoritative.
Pinned Nimony `63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`, ARC, checked release,
Clang and ThinLTO remain unchanged. The held byte-loop PR1877 is not a dependency.
Public defaults and x86 lowering are unchanged.

An opt-in ARM body covers one complete charged source suffix, bounded to16 source
operations/16 memory operations, ending in a positively cached conditional.
Interiors contain indirect memory opcodes120–130 and supported pure arithmetic.
Hosts, dynamic jumps and unsupported instructions retain accepted workers.
At least one load, store and shared window are required. A zero-window candidate
keeps accepted execution.

Header discovery checks the ordinary charge handler, exact sealed source span
and ordered emitted facts. Folded opcode2 consumes source attempts without an
executable node. A mixed-specific probe initializes only nonexecutable records,
including earlier ordinary refusal, and preserves unavailable-storage and
262,144-coordinate bounds. Eight eligible unpaid, full-gas/full-budget visits
after branch certification justify publication. These are visits, not a claimed
count of observed backedges.

## Execution and ownership

Canonical `flatReserve` charges gas and reserves the full source span before
native entry. Partial budgets, insufficient gas, barriers and prepaid entry use
the original header. Native code does not manage gas or quota.

The ordinary five-word context contains exit kind, descriptor pointer, bitmap
word count, bitmap pointer and completed lowered operations. Kind1 completes
the conditional, returns a certified target and clears paid state. Kind2 returns
the exact first unexecuted memory operation, publishing only completed-prefix
register writes. Its wrapper retains paid state/tagged reservation and invokes
the sealed fact's canonical one-operation worker. Earlier stores are never
replayed. Existing attempted-exit refund restores only the unattempted tail.

Prefix masks precede the current load's write registration. A later failed load
to an already-written destination retains the earlier value. Future writes and
uninitialized physical registers never spill. Constant prefix counts in exit
stubs avoid per-operation runtime accounting.

Cold planning records every write event, including repeated assignments. Up to
two groups each contain at least two accesses through a base unchanged between
first and last access. The first member proves a nonwrapping bounded window,
canonical address range and complete descriptor. Descriptor `len-7` is checked
before span subtraction. Write groups additionally require a writable window
within one already-dirty guest page. Failure returns to that first operation;
checked execution determines later faults in source order.

Pointers occupy distinct x4–x16 lanes absent from all source operands, including
branch operands. Cache writes never enter guest spill masks. Loads/stores retain
their original order and alias behavior. Ungroupable accesses within a grouped
body retain individual guards; wide stores prove every touched dirty-page bit.

No invocation pointer is retained. Arena ownership, twelve-byte entry records,
one-MiB storage and ordinary1,023-publication ceiling stay unchanged; connected
execution keeps its reserved slot. Oversized emission refuses normally. Optional
receipt builds add two instrumentation lanes; those lanes and updates compile
out of ordinary timing builds. No runtime attribution switch is preserved.

## Verification

Final-source native, forced-storage-refusal and interpreted witnesses pass
locally. Ordinary and receipt-instrumented native variants are covered. The
original ARM witness remains intact. Added literal/checked-machine cases cover:

- Aliasing store/read/store, unused guest-slot preservation and repeated base
  writes that must refuse grouping.
- Earlier native stores surviving a later group decline; future invalid memory
  returning to the first group operation without an early guest fault.
- Clean/read-only/missing pages, page63→64 bitmap-word boundary, and short
  descriptors refusing without subtraction underflow.
- Mapped highest-page accesses at0xfffffff8, with the store page predirtied so
  it exercises the address guard. Reserved-byte access produces Panic/PC0.
- Leading-noop14-operation/10-memory execution, two published windows and exact
  paid/gas/partial-budget accounting.
- A source-built15-memory body emitting1,053 ordinary words, refusing publication
  above the existing limit and retaining checked behavior.

## Measurement record

The baseline census has10,122,320 checked memory attempts over ten DOOM ticks;
twenty sites account for45.523%. The11-operation/eight-memory block has stable
132-byte and32-byte windows. The preserved extension also admits the audited
14-operation/10-memory block. Corrected untimed13-call validation confirms both
windows publish and DOOM output matches. The extension records102 windows,
2,820,537 attempts and2,753,789 passes. Census byte PCs are `fact.pc`, not
`f.sites` instruction ordinals; production admission contains no guest PC.

Comparisons fix input, compiler and flags and use one canonical source/output/
cache coordinate, saving binaries after builds. Earlier per-operation-body,
bitmap, borrow and admission variants remain preserved with their losing or weak
receipts. Removing a proven retain/release cost did not improve timing.

The best cross-binary screen appeared about1.2–1.4% faster. A final private
same-executable preparation-only on/off comparison does not attribute that gain:

| DOOM tick, same executable | Mixed off | Mixed on |
| --- | ---: | ---: |
| Mean of six steady process medians | 18.6343 ms | 18.6555 ms |
| Median of six steady process medians | 18.5605 ms | 18.6270 ms |

Each process runs13 fully checked calls, excluding samples0–2. Three balanced
ABBA changes are -0.493%, +0.622% and +0.221%; overall mean change is+0.114%.
The same-image interpreted control validates output at24.76ms with zero native
activity. All runs match DOOM output.

Off mode exactly matches accepted activity:910 fragments/16,066,627 native calls/
152,738,024 lowered operations/175,428 bytes. On mode records954 fragments/
15,854,488 calls/158,456,891 operations/206,428 bytes, including1,599,740 mixed
calls,1,566,389 complete bodies and33,351 declines. More native coverage and
fewer transitions did not demonstrate a CPU gain.

The preserved extension also screens flat/slower:18.4795/18.5125ms flanking
baselines versus18.586ms candidate. It is distinct from the final on/off
experiment's16-source/8-memory policy; the draft includes its tested16-memory/
folded-noop/resource-refusal machinery for reuse.

Attribution executable SHA-256:
`81a48b05f2e23dd76978d24f9f5762aeb42621e04cd8280b9baebeb117fc9d93`.
Input SHA-256:
`574821fb1c5f9dc94cae96a28859f513128233e9a3a8833e7ad201b135d8653e`.
The private attribution switch is absent from this draft. Full per-sample data
and identities are in ignored
`build/pvm-mixed-memory/evidence/attribution-summary.json`; peer preservation
manifests bind both ordinary source variants to final-source witness logs.

Keep draft, with no readiness labels, review request or targeted CI. Reuse the
paid-interior and window machinery only with fresh correctness and whole-DOOM
measurements. These results establish neither a Linux win nor a candidate
ours/PolkaVM-interpreted ratio. The next bounded lead is memory entry/checkpoint
cost.
