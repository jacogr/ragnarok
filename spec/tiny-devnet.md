# Tiny six-node devnet

## Contract and pins

The maintainer requested six local processes, one validator per process, producing and consuming
real blocks. Use the existing Tiny profile (two cores, six validators, twelve slots per epoch),
Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and the repository's unchanged
Bandersnatch and JAMNP-S pins. GP Safrole signing, entropy, marker, rotation and fallback
selection checks remain mandatory. An absent external `polkajam-fuzz` engine is independent
of this work.

The initial milestone uses empty extrinsics and an uncontested fallback chain. This is a bounded
local devnet, not a claim of complete validator lifecycle, ticket production, fork choice or
finality. Each process owns a distinct signing role and independent complete state. Authored
and received blocks must both pass ordinary current candidate validation before adoption.
No fuzz-only ancestry or admission authority may enter the node path.

## Completion evidence

Before calling the devnet operational, run six independent native processes over loopback,
observe real signed block production and remote validation, compare exact canonical block hashes
and complete state roots at all six nodes, cross an epoch boundary, and stop/restart one node
then verify catch-up. Bound run time, network input, retained history and process cleanup.
Include wrong-key, malformed block and stale-parent refusal controls. Preserve parent state
on failed authoring/admission. Record actual results and remaining limitations here.

## Status

The bounded empty-extrinsic six-node milestone is implemented and locally verified.
Ticket/work production and fork/finality behavior remain outside this increment.

## Implementation boundaries

`make devnet` owns build/launch and `make check-devnet` owns the independent acceptance run.
The application E2E group requires the two-block `application_tiny_devnet` smoke, retaining
all independent signatures, journals and whole-map comparisons. Full epoch/restart acceptance
remains available separately through `make check-devnet`. Native `tiny_block_author`
checks all six keys across fourteen blocks, exactly one eligible author per slot, wrong-key,
invalid-seal and stale/replayed-block refusals, parent preservation and unset finality.

The native initializer constructs all16 global chapters and the exact configured Tiny tuple.
Tiny overrides follow pinned `vendor/jamtestvectors/README.md`; the24-slot lookup age follows
pinned conformance Tiny ancestry guidance. Initial active/pending/staged/previous populations all
contain the six distinct public development identities. First-epoch keys cycle in roster order;
epoch transitions use the ordinary GP entropy-dependent fallback schedule. The genesis is a
configured trust anchor with a zero seal. No authenticated-child bypass is introduced.

The runtime serves/polls ascending CE128 one-child requests over identity-pinned loopback QUIC.
Every local/remote child is prepared through `prepareCurrentCandidate`, synchronized in the
per-node block journal, then installed. Complete-map snapshots are observations only; restart
re-executes journal blocks from genesis. Input, history and horizon are bounded to64 blocks.
Transport callback work is bounded, and all native engines/streams retire before owner destruction.
Production storage Services, RPC, ticket generation and fork/finality machinery remain separate.

The independent reference records the cryptographic genesis ring commitment as an attributed
input, independently checks all other original entries and computes every header, Thin signature,
complete successor map and checkpoint before any validator starts. Acceptance compares every
saved height and exact journal at all six processes, rather than accepting equal roots alone.

## Observed verification

Initial macOS ARM64 checked ARC/Clang ThinLTO run: six processes produced and remotely consumed
fourteen blocks, crossed slot12, stopped node5 after slot5, replayed/recovered it after slot8 and
converged at slot14. All90 complete-map observations and84 journaled block records matched the
independent reference. Every identity authored at least once; all six final validator processes exited successfully.
Final block hash `7eea4774dd71789d2fb1290d9b8a337d65e1bbd9c61ec4d0ad7c7aefe607eb00`,
complete state root `e92eaf84d90782d198d5af5b62239eb786450574504a791414b6818730b7ed15`.
Evidence: `build/state9-tiny-devnet/live-1/result.json` and its pre-launch `independent/plan.json`.
Final repeat through `make check-devnet` passed with the same block/root and all90 maps/84
journal records. Evidence: `build/tiny-devnet/check-20261026-083637/result.json`. The final Tiny policy includes the
24-slot lookup bound. Exact native binary and policy SHA256 identities are in that result.

Final local checks: `make unit SUITE=tiny_block_author`,445 production-module/entry semantic
checks, pinned Nim/Rust formatting, verification inventory,23 focused Python harness/control
tests and exact private-payload/owner-copy compiler refusals passed. The author suite also
refuses fuzz-only seeds, mismatched profiles and insufficient frame bounds. Ordinary `--help`
and `--version` entry smoke checks passed. These are macOS ARM64 results; Linux CI is separate.


## Short CI acceptance

The maintainer requested a couple of blocks on CI with checks. `make check-devnet-smoke` and
`application_tiny_devnet` run two ordinary six-second slots on all six native processes. They
freeze independent expected blocks/maps before launch and compare all18 complete maps and12
journaled block records after clean shutdown. Both eligible authors must be observed and every
node must remotely adopt blocks. This shorter horizon does not claim an epoch transition or
restart; the unchanged full target retains14 blocks and injected stop/replay/catch-up.

CI's existing E2E / Application matrix runs the smoke on Linux and macOS. Only scoped logs,
heads, result metadata and independent plan hashes are uploaded; TLS certificate/key directories
and binaries remain excluded. Default local `make devnet` still runs14 slots. The native host
accepts2..64 slots; the launcher refuses a restart run with fewer than13.

Observed final PR validation: the two-block smoke passed with18 full-map comparisons and12
journal records; the full14-block epoch/restart acceptance also passed again after adding the
short horizon.72 focused Python CI/harness/provenance tests, inventory, changed-command semantic
compilation/pinned formatting and workflow YAML parsing passed. Evidence:
- `build/tiny-devnet/check-20261026-085222/result.json`
- `build/tiny-devnet/check-20261026-085406/result.json`
