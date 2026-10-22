# Using bounded encoded-record admission

The [contract](storage-bounded-admission.md) preserves physical formats and strict complete graph
admission. Encoded repository image restore and publication now transfer freshly decoded payload
owners into private immutable cells, avoiding a complete detached transport batch beside those
cells. Existing mutable `TrieExport`/`RecordCollection` APIs keep independent validation and copies.

## Choose the required authority

| Operation | Successful result establishes | Caller responsibility |
| --- | --- | --- |
| `inspectOrderedRecordCollection` / `inspectTrieExport` | Complete structural extents, canonical fields, limits and uniqueness; scalar metadata | No hash or graph authority; input must be checked again when consumed |
| `visitOrderedRecordCollection` / `visitTrieExport` | Every delivered record passed local integrity; complete delivery only on success | Keep input stable, stage effects privately, validate any complete graph separately |
| `decodeRepositoryImage` | Every retained complete root, routes, counts, root inventory and absence of orphan records under inherited policies | Retain successful owner/view as needed; inspect typed refusal before extraction |
| `NodeRepository.publishEncoded` | A successful private staged publication installed the validated next head | Supply the expected repository view and respect typed stale/base/quota/conflict failures |

Ordered collection delivery requires strict physical address order. Target-bearing trie exports
preserve serialized order and preflight duplicate addresses using bounded address-only scratch.
The public detached decoders remain available for callers that actually need a complete mutable
transport. A successful inspection result is never a reusable trusted token.

Both visitors accept either `(input, limits, state, consume)` or
`(input, limits, state, prepare, consume)`. `RecordPreparation[T]` and `RecordConsumer[T]` are nonnil
synchronous `nimcall` procedures with explicit `var T` state. Preparation receives
`RecordCollectionInfo(records, valueBytes)` after the entire structural/duplicate preflight and
before crypto, including for empty input. Use it only to reserve bounded private capacity.
Consumption receives one detached `var TrieRecord`; a caller may transfer its owned payload.
Returning false produces `RecordError.ConsumerRefused` and stops delivery. There is no callback
for malformed structural input. A later hash/backend failure can follow successful preparation
and a delivered prefix. Discard staged effects on any refusal; callback effects are not rolled back.

Do not mutate or free borrowed encoded bytes during any synchronous visitor, including from a
callback. Successful repository admission retains no input borrow. It publishes privately staged
cells only after complete integrity and graph validation; neither metadata nor callbacks may
install partial repository state. Public mutable raw inputs never enter the private decoded-cell
factory. Independent held views remain valid after owner close or a failed subsequent admission.

Encoded publication preserves full-codec validation before base/generation/physical-policy
checks, followed by quota before conflict and then graph/orphan checks. It continues record
integrity checks after an earlier staged quota/conflict so a later hash/backend refusal retains
its existing precedence. Raw publication retains its established earlier raw-policy checks;
these two error orders are intentionally different.

## Reproduce paired fresh-process observations

Use `make bench-storage-fresh-reopen` on a clean baseline and again on the clean candidate.
Each run builds the maintained checked ARC/Clang/LTO native consumer, creates the existing four
workloads and emits `build/tests/storage-fresh-reopen/results.json`, `reopen-native` and logs.
Before the next run, copy that report and executable into separate, uniquely named directories
under this checkout's ignored `build/`. Preserve the executable permission and all raw receipts.
The frozen report's original build/run commands are evidence only; copying does not edit them.
Keep compiler/provider builds and other benchmarks stopped during the subsequent pair.

Author an explicit local configuration, for example `build/reopen-pair-config.json`:

```json
{
  "schema_version": 1,
  "baseline": {
    "report": "build/before/results.json",
    "binary": "build/before/reopen-native"
  },
  "candidate": {
    "report": "build/after/results.json",
    "binary": "build/after/reopen-native"
  },
  "allow_sources": [
    "Makefile",
    "src/storage/node_repository.nim",
    "src/storage/record_codec.nim"
  ]
}
```

Approve only the intended content differences. Inventory additions/removals, changed native
workloads/counters, toolchains, interpreters, providers and environmental geometry refuse even
when source changes are listed. Select only local binaries you built and trust; hash agreement
with a report is not independent proof that an arbitrary downloaded binary is safe to execute.
Selections must be regular files below `build/`, without symlink aliases, and executables must
have native ELF/Mach-O headers and the recorded SHA-256 identity.

```sh
make inspect-storage-reopen-pair REOPEN_PAIR_CONFIG=build/reopen-pair-config.json
make bench-storage-reopen-pair REOPEN_PAIR_CONFIG=build/reopen-pair-config.json \
  REOPEN_PAIR_OUTPUT=build/reopen-pair-run1
make summary-storage-reopen-pair REOPEN_PAIR_REPORT=build/reopen-pair-run1/results.json
```

Inspection and summary execute no imported commands or binaries. Collection is an explicit
execution action: Make supplies `--execute-local-builds`. It constructs fixed native argument
vectors from maintained source, uses an exclusive new output directory, runs two reversed case
and binary orders, checks both producer directions and observes 16 fresh consumers on eight
producer-owned namespaces. Both readers must preserve the exact same selected bytes, expected
roots, complete maps, physical counts and full allocator release. Temporary namespaces retire
on failure; partial/failure reports remain inspectable without a successful summary.

Read-only summary validation reparses all native witnesses and requires exact 24-command coverage,
case/order/namespace identity, selected bytes, binary identities and stable host/environment
receipts. Imported command/path fields remain inert metadata. It expects the recorded checkout
path convention used by the existing fresh-reopen validator. Preserve report and binary hashes
when transporting evidence; self-described JSON alone does not authenticate a remote run.

These optional targets do not join default Perf Storage, Perf Storage Growth or routine unit jobs.
RSS is a whole-child high-water observation. Live Nim allocation describes retained repository
owners separately. Cache policy is ordinary host behavior without eviction; no timing speedup,
cold-cache, ambient-pressure isolation or out-of-core claim follows. Linux resident-pressure
qualification is a separate explicit scoped workflow with timeout and local OOM outcomes recorded
independently. See the final qualification and status records for actual limits and next work.
