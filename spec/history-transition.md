# Recent-history state transitions

This increment implements Gray Paper **0.8.0**, revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/recent_history.tex`
(`correctlaststateroot`, `accoutbeltdef`, `recenthistorydef`) and
`text/merklization.tex` (`merklenode`, `simplemerkleroot`, `mmrappend`, `mmrsuperpeak`).
The existing [C(3) codec](state-history.md) and [C(16) output codec](state-outputs.md) are reused.
Source identities and consumed published blobs are recorded in [pins.json](pins.json).

## Stage contracts

`src/state/history.nim` exposes three bounded operations:

- `correctHistoryParent` copies an immutable history snapshot and corrects its newest record's
  state root from the current header's parent-state root. Empty genesis history stays empty.
  Accumulation and report-context validation need this corrected view before completing the block.
- `accumulationRoot` derives the well-balanced Keccak root of the **ordered** accumulation-output
  pairs, encoded as E4 service identifier followed by the raw 32-byte commitment. Empty input
  yields zero; a singleton hashes its 36-byte leaf once. Internal nodes retain raw singleton
  children, split at ceil(length/2), and use the ASCII `node` prefix. No sorting or leaf prehashing.
- `advanceHistory` consumes the completed accumulation root and validated header/guarantee
  projections. It corrects the parent record, appends the root to the Merkle belt, computes the
  super-peak, and appends the current record with a zero state root. It retains the newest eight
  records, their dictionaries, slots and prior commitments. Package projections are sorted by
  hash into canonical dictionary order; duplicate keys reject. It does not reorder output pairs.

The final stage safely repeats parent correction, allowing either the original or already corrected
snapshot. No API infers an absent C(3) entry to mean empty genesis. The parent root correction is
not the current block's resulting state root. The current zero placeholder is corrected by its child.

`advanceHistoryState` reads and exactly decodes C(3), computes the complete replacement privately,
and publishes a single atomic write through the full-state store. Unrelated entries and retained
historical snapshots remain unchanged. A future block executor must provide a private working
store and publish only after **all** block stages succeed. The explicit parent-correction entry can
be applied to that working store before accumulation. No whole-block atomicity is claimed here.

Header hashing/validation, guarantee validity and package uniqueness, accumulation execution,
C(16) production, PVM, chronology checks, proofs and complete block import remain separate work.
The precomputed `AccumulationRoot` boundary matches the published history STF schema. Its
separate derivation API covers the preceding output-tree equation without executing accumulation.

## Hash-token notation and upstream disposition

The pinned 0.8.0 text spells the super-peak prefix `$peak`. The pinned tiny/full
`progress_blocks_history-4.json` expected super-peaks instead reproduce with ASCII `peak`.
For the tiny case, present peaks are:

```
a983417440b618f29ed0b7fa65212fce2d363cb2b2c18871a05c4f67217290b0
658b919f734bd39262c10589aa1afc657471d902a6a361c044f78de17d660bc6
```

Keccak(`peak` || first || second) is the published
`ebdb6db060afceaa2a99a499a84476847444ffc3787f6a4786e713f5362dbf4d`;
Keccak(`$peak` || first || second) is
`dd489e9c79a72b8c4a992c5b7f28dad95c1ecfc6099f831befb7bea42aefb433`.
[Closed issue #509](https://github.com/gavofyork/graypaper/issues/509), especially its
[clarification](https://github.com/gavofyork/graypaper/issues/509#issuecomment-3706909013),
explains that the dollar sign is binary-string notation rather than a token byte, and applies
this interpretation to `node` and `leaf` too. This module therefore uses exactly ASCII `peak`
and `node`, without `$`, count framing or a null terminator. This resolves the history mismatch;
there is no alternate-domain fallback. The independent integer Keccak oracle reproduces the
published super-peak under that interpretation. The subsequent [signing-domain audit](signing-domains.md) corrects both implemented Ed25519
transcript domains using external published credentials.

The published family supplies precomputed accumulation roots, so it provides no direct output-tree
verdict. Authored tree checks exercise the 0.8.0 equations with the clarified `node` token.
[Open PR #549](https://github.com/gavofyork/graypaper/pull/549) proposes further domain separation
and Merklization changes; it is not adopted before a compatible specification/vector upgrade.

## Ownership, failures and limits

Inputs are immutable retained codec snapshots and synchronous stable borrowed output/projection
arrays. Scratch records/dictionaries/peaks are independent copies. Returned serialized entries are
caller-owned; committed snapshots retain private immutable store data. Owners are acyclic ARC.
Default/failed results carry only a reason. Checked success extraction is required for entry,
accumulation-root and committed-snapshot payloads; callers cannot retag results or read raw fields.

`HistoryConfig` bounds input/output blocks, per-block/aggregate packages, peaks and full encoded
bytes. Native copy extents and growth are checked before input-derived allocation/narrowing.
The complete prospective output is encoded/preflighted before belt hashing. Optional absent peaks,
present zero hashes and trailing holes remain distinct. Carry grows the belt only when required;
there is no implicit 32/64-peak limit or normalization. `OutputLogConfig` independently bounds tree
work and exact count-prefixed source bytes. Store map/node/write budgets still apply separately.
Missing/malformed/suffixed C(3), policy refusal and failed Keccak/Blake2b calls never publish partial
state. Allocation failure remains fail-stop rather than a recoverable protocol failure.

## Verification

All eight tiny/full `stf/history/*/progress_blocks_history-{1,2,3,4}.json` cases at vector revision
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` are consumed unchanged, including empty, growing,
filled and evicted histories. The helper verifies exact Git blob SHA-256 values, transports the
supplied pre/post C(3) bytes and records provenance; it contains no history-transition oracle.

The native success profile checks exact published bytes, canonical package reordering, immutable
sources, parent-stage composition, stored/unrelated entries and historical snapshots. Eleven
separate output-tree cases use the existing independent integer Keccak oracle and appendix
recursion; these are authored checks, not published output-root vectors. Boundaries include maximum
uint32 slot, duplicate packages, exact byte budgets, invalid/default inputs, optional holes,
present zero peaks, and a 128-position carry extending to 129 positions under explicit policy.

The observer profile checks Keccak carry/bag/tree refusal, immediate/delayed trie refusal,
rollback/recovery, missing/truncated/suffixed state and zero-write/precopy policies. After warmup,
1,000 scoped cycles must return to identical live allocator occupancy; this is workload-specific
ARC evidence. Six dynamic misuse probes require intended precondition failures, and three compiler
probes reject private payload access, result retagging and accumulation roots used as state roots.

Run `make check-modules check-python check-unit check-guards`; reports and source/ARC evidence
are generated under `build/tests/`. Networking behavior and the M1 checkpoints in
[state-clarifications.md](state-clarifications.md) remain unchanged.

The signing-domain follow-up is complete in this PR; see [the audit](signing-domains.md).
Next suggested bounded state-execution slice: entropy/timeslot progression with pinned evidence.
