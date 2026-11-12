# Cold preparation follow-up experiments

## Chunked execution metadata

Parent: `a40cb29adf4e0b20fa6cabf4b55c7b4053002154` (PR #2160).
Logical source ordinals and PC-map extents remain admitted up front. Physical fact and
map payloads now allocate on first write in 1024-element chunks. Unvisited entries read
as zero; quotas, backward branches and native adjacency proofs keep their existing indices.
Directories remain bounded by the validated program extent. This is unconditional.

The literal 2048-instruction isolated-block witness allocates no payload before resolution
and less than 65536 bytes after visiting a late block, versus 81920 bytes of dense payload.
The existing 22 selected native PVM suites pass, including cross-chunk execution, out-of-order
resolution, refusal boundaries and the fresh 1000-cycle ARC witness (460256 bytes before/after).
Returning a stream also tests the explicit move reset: the compiler-generated hook cleared the
sequence owner but left scalar extents behind in the initial prototype.

Local measurements use macOS ARM64, pinned Nimony `fd9742bf`, checked ARC/Clang release,
`--opt:speed` and ThinLTO, with the ARM backend compiled but interpreted policy selected.
Both roles use unchanged frozen inputs and canonical drivers with complete-state validation.
Six guest cases use 20 fresh processes per role; each DOOM phase uses ten per role.
Role order alternates. Each process performs thirteen calls; cold is call zero, reused is
the median of calls 3–12, followed by the median across processes. These are CPU microseconds,
not Linux qualification results or ratios against PolkaVM. All 3640 calls passed checks.

| Case | Parent cold | Chunked cold | Parent reused | Chunked reused |
|---|---:|---:|---:|---:|
| sieve-1000 | 965.50 | 973.00 | 41.25 | 40.50 |
| sieve-100000 | 6439.00 | 6534.50 | 3238.50 | 3212.75 |
| minimal-1000 | 122.00 | 125.00 | 49.25 | 49.75 |
| memset-1000 | 231.00 | 239.50 | 49.00 | 50.25 |
| minimal-100000 | 4788.50 | 4825.00 | 4712.00 | 4752.25 |
| memset-100000 | 3883.50 | 3910.00 | 3692.75 | 3702.00 |
| doom-init | 233629.50 | 233540.00 | 215317.00 | 214101.75 |
| doom-tick | 26414.50 | 26943.00 | 14805.50 | 14813.00 |

The final run did not reproduce an earlier 6% DOOM-tick cold reduction; the final change was
about 2% slower there. Small timing changes are unproven on this shared machine. The retained
hypothesis is lower allocation for untouched code, with a real extra lookup cost; native Linux
measurements must guide retention. A 256-element variant also passed correctness checks but
provided no consistent timing advantage, so the coarser chunks reduce directory/allocation work.

Full commands, binary identities, raw samples and logs are retained locally under
`build/cold-stack/`. The exact parent Linux ARM64/x86-64 baseline completed successfully in
[run 43255518474](https://github.com/jacogr/ragnarok/actions/runs/43255518474).
