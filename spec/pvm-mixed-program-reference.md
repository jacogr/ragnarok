# Combined memory, host and loop execution

## Normative scope

Gray Paper 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401` remains primary;
PolkaVM `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` is the public
Interpreter/JamV1 Sync/Full/L2Hit cross-check. No production behavior or pins change.
The independent reference encodes original guest bytes and calculates complete
register/memory outcomes, callback counts and block prices from paper equations.

The test environment supplies two deliberately simple custom host callbacks. They
exercise the VM host boundary, not the JAM semantics associated with those numeric
host identifiers. Host13 increments the value loaded in r7; the guest stores it;
host14 reads the already-committed value and adds it to r8. The guest increments r10
and conditionally branches back until the specified number of iterations completes,
then halts through r0. Both callbacks preserve gas and memory ownership.

## Consolidated matrix

| Dimension | Coverage |
| --- | --- |
| Guest code | Load-indirect u64, host, store-indirect u64, host, add-immediate32, backward conditional branch, dynamic halt |
| Iterations | 1, 2, 7, 31 |
| Initial scalar | Zero, uint64 maximum, int64 maximum bit pattern, int64 minimum bit pattern |
| Address | `0x10000` and cross-page `0x10fff`; nonzero upper bits in the base register |
| Gas | Full cost +7, exact full cost, full cost −1, first-block cost −1 |
| Observations | Every host PC, host order, gas at each callback, complete registers, both pages and native source aliases |

There are 32 programs and 128 gas scenarios. The first block costs 103 gas /106
local cycles; the final halt block costs 22 gas /25 cycles. The independently
calculated complete cost is `iterations * 103 + 22`. A final-block shortage retains
all completed loop/host/memory effects and refuses at PC20; first-block shortage
refuses at PC0 without a host call or mutation. Public Sync metering retains
nonnegative unspent gas at both refusals.

The oracle uses mathematical modular arithmetic: final memory/r7 is initial plus
iterations modulo 2^64; r8 is the sum of all stored values modulo 2^64; r10 is the
iteration count. Untouched registers and memory remain sentinel values. Literal
carry/triangular-sum controls independently protect those equations.

## Fixture and execution boundary

`PVMMIX01` framing contains a u32 program count, then 268-byte headers and bounded
raw blobs. Each header owns blob length, iteration count, address, initial/final
scalar, both gas/cycle prices, 13 input registers and 13 expected final registers.
The fixture descriptor pins exact bytes and SHA-256. No reference assembler or
production decoder generates expected code or outcomes.

The public checker bounds host iterations and uses finite guest gas. The native
checker sets exact guest-step and host-callback budgets and compares immutable source
snapshots after execution. Native successful halt normalizes PC0; the reference
reports Finished. Local cycle limits are native policy rather than a claimed public
PolkaVM cycle-counter API. All memory/host replies are deterministic test inputs.

## Completion and evidence

```sh
make unit SUITE=pvm_mixed_program_reference
rustup run 1.99.0 cargo run --release --locked --offline --manifest-path tests/reference/polkavm_memory/Cargo.toml --target-dir build/polkavm-memory-reference-target --bin mixed -- tests/fixtures/pvm-mixed-program.bin
```

Both consumers pass all 32 programs /128 gas scenarios. Altered expected final
registers and body prices fail both consumers. Independent fixture/oracle and runner
discovery tests pass, along with inventory and pinned formatting. Source declarations
add this pair to the existing differential job and Actions table automatically.
Evidence is local macOS checked release Nimony ARC/Clang LTO and pinned Rust release;
no remote Linux, performance, complete upstream test or fuzz result is claimed.
This supplies a representative combined guest boundary; it does not establish
complete JAM invocation or whole-block state-transition parity.
