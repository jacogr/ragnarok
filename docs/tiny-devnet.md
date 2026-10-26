# Six-node Tiny devnet

Run six native Ragnarök processes, each with its own validator key, complete state, QUIC listener
and durable block journal:

```sh
make devnet
```

The default run produces fourteen blocks using real six-second slots, crosses the twelve-slot
epoch boundary and stops once all six nodes agree on the same canonical block hash and complete
state root. Each validator authors eligible slots and consumes other validators' blocks through
ordinary GP candidate validation. Expect approximately ninety seconds after compilation.

Run the acceptance test with independent signatures and complete-map expectations, including a
stopped node that replays its journal and catches up over QUIC:

```sh
make check-devnet
```

For a short local smoke with the same independent checks:

```sh
make check-devnet-smoke
```

This runs two blocks on all six nodes, checks18 complete maps and12 journal records, and verifies
convergence and clean shutdown. It retains GP's six-second slot duration. It does not claim epoch
crossing or restart coverage; use the full acceptance target for those cases.

All targets provision/build through Make. A dedicated **E2E / Testnet** CI matrix job runs the full
fourteen-block epoch/restart acceptance on Linux and macOS, separate from Application. It retains
per-node logs, observed heads, result metadata and the independent plan hashes. PRs request the E2E group with the existing `ci:e2e` label. Native authoring/refusal tests are available with `make unit SUITE=tiny_block_author`.

Run only the standalone Testnet E2E group locally with:

```sh
E2E_GROUP=testnet make check-e2e
```

## Inspect or extend a run

Logs and data remain under a fresh directory inside `build/tiny-devnet/`. Each `node-N/` contains:

- `stdout.log` with actual local/remote block adoption, hash and root observations.
- `stderr.log` with explicit refusals or runtime failures.
- `head.json`, the current observed canonical hash, slot and complete state root.
- `blocks.bin`, a bounded journal of exact validated blocks, atomically synchronized before adoption.
- `state.bin` and `state-SLOT.bin`, complete-map checkpoint observations.
- The process's development TLS certificate and key.

`result.json` records process outcomes and convergence. Acceptance runs also write the independent
expected blocks, complete maps and hashes under `independent/` **before any validator starts**.
The genesis ring commitment is an attributed cryptographic input; it is not an independent
Ring/KZG calculation. All successor maps and Thin credentials are independently calculated.

After building, choose a fresh directory and a bounded run (2 through64 slots; restart requires at least13):

```sh
python3 tools/tiny_devnet.py --directory build/my-devnet --slots 24 --restart
```

The launcher constructs genesis through the native executable, creates six matching TLS
certificates, reserves loopback ports, starts six processes and reaps them on success or failure.
`--restart` stops node5 after slot5 and restarts it after the other five nodes reach slot8.
Its block journal is retained and every replayed/downloaded child undergoes ordinary validation.
The native command accepts explicit directories, ports and clock origin; use the launcher for
routine operation and keep one process per node directory.

## Current scope

This is an uncontested, empty-extrinsic development chain using six public deterministic validator
identities. GP fallback schedule selection, epoch markers, entropy proofs, seals, state transitions
and full-state commitments remain checked. Block transfer uses authenticated JAMNP-S CE128
one-child requests; peers discover progress by polling their canonical parent's successor.

The runtime retains at most64 blocks and uses an explicit common development clock origin.
Restart authority is the synchronized block journal; checkpoint files are observations and are
never accepted as trusted successor state. Finality remains unset. This increment does not supply
ticket production, work-package generation/refinement, persistent UP0 announcements/grid topology,
fork choice, finality or production key management. The separate external `polkajam-fuzz` campaign engine is not required for this devnet.
