# Executed scalar-boundary memory reference fixtures

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

Ninety cases cross every direct scalar opcode52..62 with absent/read-write/read-only
final pages. Each width uses the last start whose exclusive end fits u32, the
paper's nominal final-fitting start, and0xffffffff when distinct. The original
twelve byte-load/store records remain first and byte-identical after the count header. Map with `zero_memory_with_memory_protection`, seed7 in
every byte, then apply read-only protection. A0 starts99. Ordinary `zero_memory`
requires existing writable memory and cannot create the reference mapping.

Binary layout: eight ASCII bytes `PVMMEM01`, u32 little-endian record count90,
then25-byte records: u64 address; u8 mapping(0 absent,1 RW,2 RO); u8 opcode(52..62);
u8 exit(0 Finished,1 Trap,2 Segfault); u32 fault page(0 for nonfault); u64 A0;
u8 penultimate-page byte; u8 last-page byte. Absent images use two zero placeholders.
The descriptor pins the complete2262-byte corpus SHA-256.

The Nim replay independently encodes the scalar operation and performs one prepaid
step. Finished corresponds to Continued before the reference's return instruction;
Trap/Fault are compared directly. Compare A0, every other register, exact fault
page, PC, retained gas/charge state, permissions, every page byte and source aliases.
This isolates memory behavior; it does not establish equality of engine-default gas
modes, full executions, negative signed-load values or indirect forms. The replay
independently expands successful multi-byte stores from the known register value,
checks all4096 bytes, and cross-checks both recorded tail bytes. Existing signed,
indirect and charged-gas matrices remain required. No full upstream Rust test suite run is claimed.

Require two byte-identical generator runs, native replay, fixture discovery,
source-pin checks, lockfile identity validation and both pinned formatters.
M1 framing remains complete; full state serialization, whole-block parity and
full chainspec equivalence remain open.

## Observed local evidence

Two public-API reference runs produce identical2262-byte corpora, SHA-256
`28ecf7688d0dbc915d238107012f173362351001be08781294777d888d9d9f74`.
All90 native rows pass. The provenance test reconstructs the original312-byte
corpus and requires its original hash
`9a27ed2322e3615c6cacceb63f1d10610c88866d25ac121f03e43e0efe684089`.
Every opcode/address/mapping tuple is covered once. The dependency-lock test retains
all upstream package identities/checksums. No production code, upstream revision or
dependency changes. Native evidence is local checked-release macOS/ARC/Clang LTO;
reference evidence uses pinned Rust release. Remote Linux CI and a full upstream
Rust suite run remain separate. Logs are under `build/pvm-scalar-boundary-*`.
