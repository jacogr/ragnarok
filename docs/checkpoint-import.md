# Import a trusted full-state checkpoint

Ragnarök can start its complete in-memory application state from an explicitly
selected application checkpoint. The operator supplies the trusted starting
identity and exact sealed header independently of the checkpoint being inspected.
Startup verifies their binding and the complete map, then retains one selected
head with finality unset. Further checkpoint exports remain explicit.

This is available through the existing `server`, `client`, `mesh` and `download`
startup paths. The executable remains a bounded development peer; its normal
positional arguments, timeout and mode behavior still apply.

## Required inputs

| Input | Required content |
| --- | --- |
| Chain configuration | The full protocol parameter tuple matching the trusted anchor. |
| Application checkpoint | Canonical RAGNAROK-APP-V1 metadata followed by one RAGNAROK-FULL-V1 complete-map checkpoint. |
| Independent trusted identity | Exactly 238 canonical metadata bytes identifying the sealed block hash, complete posterior state root, slot and full parameter tuple. |
| Independent trusted header | Exact sealed header bytes matching the trusted block hash and slot, within the existing 256 KiB header ceiling. |

Obtain the identity and header from an independently trusted source. A checksum
checks local byte integrity; the operator supplies authority for the starting
head. Metadata extracted from the checkpoint under inspection cannot authenticate
that same checkpoint. The expected root is the complete **posterior** map root;
the header's prior-state-root field names the parent state.

The format is a local application envelope. A standalone full-map checkpoint
needs its application context before it can use this import path. See the
[application checkpoint contract](../spec/application-checkpoint.md) for exact
encoding and the [recovery contract](../spec/application-recovery.md) for binding
and refusal behavior.

## Select import startup explicitly

Append all four recovery controls to an ordinary state-enabled command:

```sh
--with-state --chain chain.json \
--state-writes 1000 --state-write-bytes 1048576 \
--state-checkpoint checkpoint.bin \
--state-trust trusted-identity.bin \
--state-header trusted-header.bin \
--state-checkpoint-bytes 8388608
```

For example, supply your existing certificate/key paths and set
`configured_alpn` to your configured peer ALPN before running this bounded peer:

```sh
./build/ragnarok server --net-port 4000 \
  --net-cert node.cert.pem --net-key node.key.pem --net-peer-key - \
  --net-alpn "$configured_alpn" --net-timeout-ms 30000 --net-mode service \
  --with-state --chain chain.json \
  --state-writes 1000 --state-write-bytes 1048576 \
  --state-checkpoint checkpoint.bin \
  --state-trust trusted-identity.bin \
  --state-header trusted-header.bin \
  --state-checkpoint-bytes 8388608
```

Omitted mutation ceilings default independently to 1,000 writes and 100,000 written value bytes.
The example flags override those defaults; explicit zero remains a readonly/refusal policy. `--state-writes` bounds
one mutation batch and `--state-write-bytes` bounds its written value bytes. Override
either for your workload; zero/zero selects readonly state. The checkpoint-byte
ceiling covers the entire application envelope, including its identity prefix.
It is independent of mutation policy and the fixed trust-input/header ceilings.
Other full-state capture limits still apply.

All four recovery controls are mandatory together, along with `--with-state`,
`--chain`. Mutation ceilings may use their defaults. Partial groups, duplicates, malformed decimal
limits and uint64 overflow refuse atomically. An explicit zero checkpoint-byte
limit is accepted as policy and refuses a nonempty checkpoint. Recovery does not
implicitly enable RPC, UI or telemetry.

## Observe the selected head

Enable ordinary RPC explicitly with `--with-rpc --rpc-port 19800` if needed.
`bestBlock`, `stateRoot` and `ragnarok_header` expose the imported head, posterior
root and exact sealed bytes. A best-block subscription begins from that head.
The provider initially retains one block: parent lookup and finalized-block
queries/subscriptions are unavailable. Serialized C(3) history remains part of the
complete map and does not create retained provider snapshots or a finality claim.
Genuine later child adoption grows ordinary retained history.

Startup reads the selected files and compares complete context and configured
parameters before listeners start. Missing, corrupt, over-budget or mismatched
inputs refuse without selecting configured genesis, scanning alternatives or
repairing files. Fix the selected inputs or policy explicitly before retrying.
Local database restart has its own durable-head/history contract; external imports
keep the one-head/unfinalized contract described here.

## Component APIs

[`loadCheckpointTrust`](../src/app/checkpoint_trust.nim) captures independent bounded
identity/header files in one private immutable owner.
[`loadTrustedCheckpoint`](../src/app/checkpoint_trust.nim) restores the selected
complete map under explicit `StateStoreLimits` and byte policy, then checks its
sealed-header binding. [`Services.startRecovered`](../src/app/services.nim)
installs only a successful opaque recovery result and compares the full chain
profile before listeners open. The normal `Services.start` overloads perform this
same dispatch from parsed recovery options.

Typed refusal results preserve native, identity, context and checkpoint causes;
only guarded success accessors expose recovered owners. Recovered snapshots keep
their selected resource policy and immutable fork/value lifetimes. Native
preparation and detached checkpoint I/O retain their existing independent lease
and shutdown-acknowledgement contracts.

M1 framing is complete. Full T(state) serialization and whole-block JAM/STF parity
remain open; trusted checkpoint startup supplies no consensus, ancestry or
finality proof.
