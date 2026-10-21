# Metered two-stage cross-page fault repair

## Scope and independent expectations

Gray Paper 0.8.0 at `07f041dabd073f9018b418e9ee72e79dd2185401` remains primary;
PolkaVM at `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` supplies the public
Interpreter/JamV1, Sync/Full/L2Hit cross-check. The
[GP-PVM-008 presence-priority exception](pvm-memory-access-reference.md) is already
implemented. This increment changes tests and documentation only.

The independent reference composes the existing memory equations with the GP gas
model. Each of 48 records retains its original paper fault (`0x10000`) and the
original CPU/code, then includes the successful store bytes for repaired writable
pages and an independently calculated block price of 25 gas / 28 cycles. Expected
values do not come from either engine. Public/native consumers explicitly apply the
known reference priority (`0x11000` first) while preserving the paper witness.

All 12 multi-byte scalar store forms participate: direct/indirect, immediate/register,
widths 2/4/8, distinct/aliased/saturated operands, upper base bits and signed offsets.
The corpus reuses the complete memory matrix's boundary positions and unequal byte
patterns. Its `PVMCRY01` framing uses a 250-byte header (the memory header plus u64 gas
and cycle fields), then the original blob. SHA-256 is
`6c1172c4ba06b7f3c0603b932bdb1d924620d826f0d7436eff00b0b3a7f545d1`.

## Sequence and observable state

| Stage | Expected observation |
| --- | --- |
| Initial 24 gas | OutOfGas/NotEnoughGas before memory inspection; gas and source state retained |
| Fund with 25 or 32 gas | Fault on missing `0x11000`; one 25-gas block charge |
| Map and seed higher page | Fault on read-only `0x10000`; no repeated block charge or partial store |
| Make lower page writable | Store completes with exactly the frozen bytes; registers unchanged |
| Following trap | Panic/Trap with 0 or 7 remaining gas; no repeated charge |

Both implementations execute the two-stage repair in the same instance/snapshot
lineage, rather than rebuilding a fresh funded machine at each fault. The public
checker verifies fault protection flags, causing PCs, complete registers and all
mapped bytes. Native checks additionally verify the charged flag, original immutable
owners at every stage, all 8192 bytes including retained inaccessible images,
single-step success at the following trap and recursive panic normalization to PC0.
Public Trap exposes the causing trap PC; this established representation mapping
remains explicit. The local 27-cycle refusal is checked independently of the public
25-gas block price; local cycles are not claimed as a PolkaVM API.

Two budgets produce 96 funded repair sequences. The native suite checks underfunding
once per input; the public probe repeats that control in each fresh budget instance.
No new semantic discrepancy or expectation adjustment was required.

## Verification

```sh
make unit SUITE=pvm_metered_cross_page_retry
rustup run 1.99.0 cargo run --release --locked --offline --manifest-path tests/reference/polkavm_memory/Cargo.toml --target-dir build/polkavm-memory-reference-target --bin cross_retry -- tests/fixtures/pvm-cross-page-retry.bin
```

Both consumers pass all 48 inputs / 96 funded repair sequences locally. The independent
fixture/provenance and runner discovery controls pass, as do inventory and pinned
formatting. Both replay consumers reject altered successful store bytes and an
incorrect frozen gas price. The source-owned declaration adds this pair to the existing reference
runner/Linux job without maintaining a second CI case list. Current evidence is
macOS checked Nimony ARC/Clang LTO and pinned Rust release; no remote CI, benchmark,
full upstream test or fuzz run is claimed.
