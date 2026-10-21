# Metered memory fault, repair and retry cross-check

The primary Gray Paper0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`
charges a whole block before execution and preserves that charge across memory
fault/retry. Approved GP-PVM-001/002 exceptions select PolkaVM's final-page fault
and exclusive-end overflow behavior; see the [discrepancy register](graypaper-discrepancies.md).

The original literal program loads r8=11 over77, performs one direct scalar
load/store at0xffffffff, then returns through r0. All11 direct scalar memory
opcodes52..62 are exercised with RW and RO repairs. The independent GP pipeline
reference gives25 gas and28 cycles for each block; native replay checks25 and
the exact28/27 local cycle boundary.

Starting with32 gas and an absent final page executes the prefix, then faults
at0xfffff000/PC3 with seven gas and an already-paid block. Mapping the final
page with sentinel7 and retrying produces Panic at the same memory instruction,
retaining seven gas, the prefix write and every other register. The retry's zero
local gas-simulation budget proves native pricing is not repeated. Full page bytes,
permissions and original CPU/memory/fault aliases remain unchanged. GP recursive
panic PC0 and single-step memory panic PC3 are checked separately.

The [public checker](../tests/reference/polkavm_memory/src/bin/retry.rs) uses the
identical literal bytes with pristine pinned PolkaVM
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`: Interpreter/JamV1, dynamic4096-byte
pages, Sync metering and Full/L2Hit pricing. Public module pricing gives25;
execution faults after the prefix with seven gas. Host-side page mapping/protection
and a second run give Trap at3 with the same seven gas and all expected registers.
A double charge would exhaust the remaining seven gas before reaching that trap.

## Reproduction and evidence

```sh
make unit SUITE=pvm_metered_fault_retry_reference
rustup run 1.99.0 cargo run --release --locked --offline --manifest-path tests/reference/polkavm_memory/Cargo.toml --target-dir build/polkavm-memory-reference-target --bin retry
```

All22 native and public reference cases pass. No production semantic change,
private feature, upstream patch or dependency upgrade. This proves the selected
scalar overflow/fault retry and gas behavior, not full PVM equivalence. Local
checked-release macOS/ARC/Clang LTO and pinned Rust evidence; Linux CI is separate.
