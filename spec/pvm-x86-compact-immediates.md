# Compact x86 immediate operands

## Bounded trial

This isolated layer removes scratch constant loads for full64 wrapping ADD/AND/OR/XOR
and immediate comparisons only when signed8 or signed32 extension reproduces every
original constant bit. Other bit patterns retain the original MOVabs form. Guest
register aliases, checked register storage, all source/gas/quota/PC/exit conventions,
branch selector tails, native admission and ownership remain unchanged. No optional
CPU instruction set, new memory guest opcode or ARM runtime change is introduced.

Independent native literals cover16 complete64 constants around both signed width
boundaries, nine source values, distinct/self/high-register arithmetic aliases and
all ten immediate comparison predicates:3,168 complete-register/return checks.
Existing source prefixes, regions, host boundaries, refused builds and actual owner
lowering controls remain. All native work is CI-only with pinned October28 Nimony.

## Decision gate

No speed claim before exact-head full-state paired measurements and calibrated
profiles. Keep only useful same-runner benefit without material regressions. If
rejected, restore only this emitter delta and retain useful literals and evidence.
Separate constructors/cold/reused/core and reference lifecycle, both process orders;
never interpret simulated branch misses as hardware measurements.

The first CI attempt40756924671 stopped during semantic compilation before native
execution: `compactWidth` returned an unconstrained int, so the caller could not
prove the narrowing to1..4. The helper now declares its actual0..4 result range;
the existing nonzero guards preserve the lower bound. No assertion, range or
bounds check was disabled. The failed receipt is retained locally.
