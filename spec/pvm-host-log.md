# JIP-1 debug log host call

## Scope and adopted contract

Implement host identifier 100 in authorization, refinement and accumulation using
[JIP-1 at 0bbe9dd4c61fbfea00e0a79ee57e4bd7f0406c92](https://github.com/polkadot-fellows/JIPs/blob/0bbe9dd4c61fbfea00e0a79ee57e4bd7f0406c92/JIP-1.md), Host-call specification.
The maintainer explicitly authorized its fixed **10 gas** cost. This differs from
the current unknown-host cost of 1000; the JIP's historical parenthetical equality
and its claim of identical behavior without implementation do not hold at our GP
pin `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`. Other unknown IDs retain 1000.

r7 supplies the level, r8/r9 the target pointer/length and r10/r11 the message
pointer/length. Target is absent only when both its registers are zero. Always
assign WHAT (`2^64-2`) to r7, including invalid memory and underfunding. Other
registers and guest memory remain unchanged. Gas subtraction follows the current
unsigned saturating model: under 10 gas terminates OutOfGas with zero credit and
no logging. Funded invalid reads continue with WHAT and no output or guest panic.

Operator output is one stderr line with numeric level and quoted byte fields.
Printable ASCII remains readable; other bytes, quotes and backslashes are escaped
byte-for-byte. An absent target prints `null`, distinct from an empty present
target. Suggested timestamp/core/service metadata is outside this increment.
The user-agent suppresses records exceeding 4096 bytes in either field, without
changing guest results. Check lengths before copying/scanning, validate both full
ranges before invoking the sink, and never emit a readable prefix from invalid memory. The sink is
best-effort synchronous diagnostic IO; output failure does not change guest state.
Records are diagnostic observations, including of execution later rolled back;
they are not committed state or telemetry.

## Completion checks

Native host witnesses cover levels, optional/empty targets, arbitrary byte escaping,
read-only/read-write/cross-page reads, invalid owners/pages/ranges and high pointers,
empty ranges, size policy, gas 0 through 11, no output on invalid memory or OOG,
unchanged registers/memory and real guest suspension/resumption. Consumer suites
exercise ID 100 in all three production dispatchers and preserve unknown-call cost.
Run `make unit SUITE=pvm_host_log`, the affected authorization/refinement/accumulation
suites, `make check-inventory` and `make format-check`.

## Local verification — 2026-10-26

On macOS arm64 with pinned Nimony `4724f66c2e01b17810c844f26575b2317995fda2`,
ARC, release and bounds checks, all five suites passed: `pvm_host_log`,
`pvm_authorization_invoke`, `pvm_refinement_dispatch`, `pvm_accumulation_dispatch`
and `pvm_host_gas`. The four existing suites retained unchanged occupied-byte
baselines across their 1000-cycle ARC checks. The authorization output contract
includes a genuine escaped guest message; accumulation includes both funded empty
records. Inventory, repository formatting, final changed-source formatting and
`git diff --check` passed. Logs are under `build/jip1-*.log` and
`build/tests/native/selected/`. The implementation started from master
`52b7d2976393dd335f16004198ec9d22d8c481ba`. Complete verification and Linux CI
are not claimed; no remote CI request was made.
