# Gray Paper 0.8.1 qualification

The authorized release is [v0.8.1](https://github.com/gavofyork/graypaper/releases/tag/v0.8.1),
immutable commit `b7044addaf48a09f235531f6188c5e7418bed410`. It supersedes
`dc9a3bf79acd044ac004f756cff88a8acc9c416d`. `spec/pins.json` records the exact
consumed source hashes, version and release context; the submodule and primitive
source references agree. The README links this current release qualification.

The complete old-pin-to-release diff changes four files: `text/definitions.tex`,
`text/pvm.tex`, `VERSION` and `context.tex`. The latter two declare the released
version and remove draft presentation. All other source chapters, including
serialization, host functions, erasure coding and Bandersnatch, are byte-identical.

| Full ceiling | Previous | v0.8.1 |
| --- | ---: | ---: |
| Report accumulation | 10,000,000 | 47,000,000 |
| Package authorization | 50,000,000 | 235,000,000 |
| Package refinement | 5,000,000,000 | 23,500,000,000 |
| Block accumulation | 3,500,000,000 | 16,450,000,000 |

`src/chain/presets.nim` owns the complete configured tuple. Tiny keeps its explicit
1,000,000,000 refinement and 20,000,000 block settings; Fuzz keeps 1,250,000,000 and
875,000,000. Both inherit the new report/auth allowances. These alternate-profile
overrides remain separately sourced; this release does not supply replacements.
The accumulation scheduler continues to use the specified maximum of the configured
block setting and report allowance times core count plus always-accumulate gas.
In particular Tiny's effective empty-allowance budget is now 94,000,000.

`src/codec/work/package.nim` admits inclusive Full package gas totals;
`src/state/report/policy.nim` checks inclusive per-report accumulation and refinement
and fixed authorization load. `src/state/authorization/invocation.nim` executes with
the configured authorization allowance, exposes that tuple to fetch and calculates
consumed gas from the same allowance. Bounds precede unsigned additions/subtraction;
local resource limits and typed refusals retain their existing meaning.

Recursive Psi halt/panic clears the paid-block flag with PC zero. The recursive runner in
`src/pvm/internal/handler_stream.nim` and the foreign cross-check adapter apply this rule; raw Psi_1
and Fault/Host/OOG semantics retain their existing contracts. Repeated terminal
restarts prove a fresh entry-block charge. No PVM optimization is part of this upgrade.

Existing protocol exceptions remain scoped, including memory ordering and compact
statistics gas. Vector, JAMNP-S, gp-next, primitive backend and compiler pins do not
change. Historical vector projections keep their explicit old gas profiles and
verdicts. Current Full/Fuzz parameter witnesses and Tiny devnet expectations follow
the release; attributed cryptographic inputs and their transitive provenance hashes
are refreshed without changing cryptographic bytes or independently calculated
block/checkpoint results.

Completion checks cover exact/+1 package and signed report limits, E8 block-budget
scheduling, configured authorizer gas, selector-zero bytes and terminal restarts.
The pin/source and fixture-provenance checks remain strict. Local qualification and
published-head Smoke results are recorded in the upgrade PR; this does not claim a
complete JAM implementation or a full Linux replay qualification.

## Master CI consumer repair

The first full master run exposed stale test expectations beyond the scoped unit
qualification: performance single-step adapters, real/synthetic guest drivers,
lazy admission and pricing ownership, the managed Tiny work-guarantee fixture and a historical-adoption
release-status assertion. Performance adapters now normalize terminal paid credit
when projecting Psi_1 traces into recursive expectations. Host/Fault/OOG and raw
single-step credit checks remain distinct; complete CPU, gas, memory, output and
intentional refusal checks remain strict. The managed guarantee policy uses the
same 47M report allowance as its current Tiny Parameters. Production behavior and
all source/dependency pins are unchanged by this test repair.

The repair qualifies both ISA performance and backend jobs on its published head,
plus the affected native units and Python tooling. Exact run links and observed
results belong to the repair PR.
