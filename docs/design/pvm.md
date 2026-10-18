# Polkadot virtual machine

[Design overview](../design.md). Detailed feature contracts live in `spec/`; routine increments
update their feature contract rather than appending progress here.

`src/pvm/program.nim` now validates GP 0.8.0 program blobs and decodes all operand
formats into copied values backed by an immutable program owner. See
[the program decoding contract](../../spec/pvm-program.md). This is the first PVM
increment. `src/pvm/machine.nim` adds immutable CPU snapshots and sparse paged memory
with atomic scalar stores; see [the machine/memory contract](../../spec/pvm-machine.md),
including its explicit wrapping-access specification gate. `src/pvm/registers.nim`
evaluates all 85 register-only instruction mutations against a copied register file;
see [the register semantics contract](../../spec/pvm-registers.md). `src/pvm/gas.nim`
calculates whole-block pipeline costs with bounded storage and a local cycle limit;
[the gas contract](../../spec/pvm-gas.md) records independent witnesses and the negative
branch-target specification gate. `src/pvm/step.nim` now charges whole blocks and
executes register-only steps into immutable machine snapshots, preserving the full
state on out-of-gas; see [the stepping contract](../../spec/pvm-step.md). Control flow,
terminal outcomes, memory-instruction integration and host calls remain open.
