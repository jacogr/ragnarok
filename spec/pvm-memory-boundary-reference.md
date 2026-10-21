# Executed final-byte memory reference fixtures

The Gray Paper remains primary. GP-PVM-002 in the
[discrepancy register](graypaper-discrepancies.md) records the specific accepted
last-byte compatibility exception. This layer adds executed cross-check evidence,
not production behavior or a Rust runtime dependency.

## Source and reproducibility

The optional [reference generator](../tests/reference/polkavm_memory/src/main.rs)
uses only public PolkaVM APIs at pinned revision
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`. It selects the interpreter, JamV1,
dynamic paging and4096-byte pages, with no gas metering. Every registry dependency
identity/version/checksum matches upstream Cargo.lock; retain the checked-in reduced
lockfile and use `--locked`. No private hooks, source patches or pin upgrades.
The generator and lockfile are test tooling; ordinary native replay only reads frozen bytes.

From the repository root, with pinned sources/toolchain provisioned:

```sh
rustup run 1.99.0 cargo fetch --locked --manifest-path tests/reference/polkavm_memory/Cargo.toml
rustup run 1.99.0 cargo run --release --locked --offline --manifest-path tests/reference/polkavm_memory/Cargo.toml --target-dir build/polkavm-memory-reference-target -- build/pvm-memory-boundary.bin
cmp build/pvm-memory-boundary.bin tests/fixtures/pvm-memory-boundary.bin
make unit SUITE=pvm_memory_boundary_reference
rustup run 1.99.0 cargo fmt --manifest-path tests/reference/polkavm_memory/Cargo.toml -- --check
```

## Fixture and completion contract

Twelve cases cross byte load/store at0xfffffffe/0xffffffff with absent/read-write/
read-only final pages. Map with `zero_memory_with_memory_protection`, seed7 in
every byte, then apply read-only protection. A0 starts99. Ordinary `zero_memory`
requires existing writable memory and cannot create the reference mapping.

Binary layout: eight ASCII bytes `PVMMEM01`, u32 little-endian record count12,
then25-byte records: u64 address; u8 mapping(0 absent,1 RW,2 RO); u8 opcode(52/59);
u8 exit(0 Finished,1 Trap,2 Segfault); u32 fault page(0 for nonfault); u64 A0;
u8 penultimate-page byte; u8 last-page byte. Absent images use two zero placeholders.
The descriptor pins the complete312-byte corpus SHA-256.

The Nim replay independently encodes the byte operation and performs one prepaid
step. Finished corresponds to Continued before the reference's return instruction;
Trap/Fault are compared directly. Compare A0, every other register, exact fault
page, PC, retained gas/charge state, permissions, every page byte and source aliases.
This isolates memory behavior; it does not establish equality of engine-default gas
modes, full executions or other scalar widths. Existing all-width and charged-gas
matrices remain required. No full upstream Rust test suite run is claimed.

Require two byte-identical generator runs, native replay, fixture discovery,
source-pin checks, lockfile identity validation and both pinned formatters.
M1 framing remains complete; full state serialization, whole-block parity and
full chainspec equivalence remain open.

## Observed local evidence

Two public-API reference runs produce identical312-byte corpora, SHA-256
`9a27ed2322e3615c6cacceb63f1d10610c88866d25ac121f03e43e0efe684089`.
All12 native rows pass. The dependency-lock test passes; specification tests pass3
with the existing unrelated Bandersnatch parity skip. Inventory passes219 failure
families/2562 probes/339 native suites; pinned formatting passes2583 Nim sources,
the existing Rust crate and the optional reference crate's explicit format check.
No production code, upstream source or revision changes. Native evidence is local
checked-release macOS/ARC/Clang LTO; reference evidence uses the pinned Rust release
profile. Remote Linux CI and full upstream Rust suite execution are separate.
Logs remain under `build/pvm-memory-reference-*` and
`build/pvm-memory-boundary-*`.
