# Gas blocks remain independent of branch targets

Gray Paper0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
[Basic Blocks](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L106-L138),
defines starts at entry0 and immediately after terminators. A later branch target
does not create a new block in the middle of existing instructions.

This regression follows sorpaas/Grey's closed
[issue155](https://github.com/alleyos/alley/issues/155) and merged
[PR154](https://github.com/alleyos/alley/pull/154). Grey reported interpreter/
recompiler partition differences hidden by transpiler-inserted fallthroughs. This
is implementation context, not a new Gray Paper contradiction or imported code.

Original raw fixtures place load r7=7 at0, a byte store at3, trap at8 and an
unreachable static jump at9. Its target varies across0/1/2/3/4/8/9/100. PC3 is
marked but is not a basic-block start, even when targeted by the later jump.
The complete first block costs26 gas and29 simulation cycles. Exact29 cycles
succeed;28 refuses locally. Gas25 returns OutOfGas before either load or store,
preserving r7=99 and memory byte11. Gas26 executes the prefix/store and trap,
retaining r7=7, stored7 and zero gas. CPU and memory source aliases stay unchanged.

The independent GP-derived corpus appends eight variants, including relocated
entry blocks. All1776 original records after the count header remain byte-identical.
All1784 native prices and exact/one-less/maximum cycle bounds pass, and the pinned
public JamV1/L2Hit simulator agrees on all1784 prices. Six Python provenance/model
checks pass. The corpus SHA-256 is `9c048aa7dbe706ce8072047473203a45e6db16900a4330dc0c4127ecf1ec1797`.
Formatting and inventory remain required. This is local checked-release macOS/
ARC/Clang LTO and pinned Rust evidence, not a full upstream suite or Linux CI run.
