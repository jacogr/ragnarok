# Direct complete-map construction

Scope: `newFullStateTrie` in `src/storage/full_state_trie.nim`. This changes private construction
and scratch ownership; public APIs, complete-map semantics, protocol bytes and mutation ceilings
remain unchanged. Authority is pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`text/merklization.tex` M/B/L, through the existing state-layout primitives and independent
complete-map calculator. No state/application implementation or light-state integration changes.

## Construction and refusal contract

The constructor previously copied each input into an owning `seq[TrieWrite]` before handing it to
the shared mutation preflight. Checked generated C shows a fresh payload allocation for this
adapter. The initial topology builder now borrows `StateEntry` directly, sorts fixed key/source
indices and copies raw bytes only into final immutable leaves. Ordinary mutations retain their
existing shared-path merge. No generic structural typing or compiler/allocator change is required.

Complete-map item/native extents precede payload validation. Per-value and aggregate bytes are
checked by subtraction before addition, before allocating sorted indices or leaf payloads. Duplicate
full keys refuse after payload checks. Native count and conservative cached-node arithmetic bounds
precede topology construction; the exact topology ceiling still precedes hashing. Empty maps make
zero primitive calls. Backend refusal exposes only its typed error and retires unpublished owners.
The completed revision retains the original caller policy, including zero mutation count/byte
ceilings; construction remains governed by complete-map ceilings independently of those ceilings.

## Local measurement

Baseline `ca3433f6`, measured implementation `eb4a2034`, macOS ARM64, pinned Nimony
`5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`, ARC, Clang, checked release speed and ThinLTO.
Two fixed maps contain 65,536 entries with either zero-byte or 256-byte values. Keys use leading
big-endian two-byte ordinals followed by zeroes; value byte `j` of entry `i` is `(i+j) & 255`.
Independent `stateTrieRoot` producer processes finish before fresh constructor consumers begin.
Both baseline and candidate producers return identical complete roots and exact 131,071-node
maps. Inputs stay live throughout construction and are mutated afterward to check copied leaves.

Each map/build has ten fresh native consumers, five in each paired build order, for 40 consumers.
The maintained `tools/storage_limit_child.py` captures whole-child peak RSS. That scope includes
flat input creation and construction, excludes reference producer/Python observer memory, and
is not an in-call allocator peak. Every consumer checks identical retained graph bytes, exact
hash attempts, complete root/counts and exact ARC retirement to the still-live input baseline,
then to its initial occupied heap. No subtraction of process peaks is used.

| Value bytes | Baseline median peak RSS | Direct median peak RSS | Reduction | Retained graph, both |
| --- | ---: | ---: | ---: | ---: |
| 0 | 22.671875 MiB | 19.656250 MiB | 13.3% | 12,582,880 bytes |
| 256 | 73.937500 MiB | 53.828125 MiB | 27.2% | 29,360,096 bytes |

The zero-value RSS ranges are 22.671875–22.687500 MiB and 19.656250–19.671875 MiB;
256-byte ranges are constant at the listed values. Hash attempts remain 131,071 and 196,607.
Roots are `232b05e1f1616537f9caf513267e8f5a51a17ab11dfd7f84a5136e67a57dc938`
and `884c68114a09a0d3efb4e9f8d0613ce1c1be32e8ee707212aeaed5eb6fd390ed` respectively.

Native monotonic timers bracket construction alone. Empty-value medians are 31.282/30.909 ms,
with ranges 24.749–41.473/26.808–64.524 ms; 256-byte medians are 82.936/68.489 ms, with ranges
55.154–211.503/49.000–116.737 ms. Other host work causes broad overlap: these observations do
not establish a latency improvement. Hyperfine/Valgrind are unavailable on this local host.
The accepted improvement is reduced temporary storage, with unchanged retained graph and hashes.
Ignored reproducibility records are `build/storage-db23-measure.json`,
`build/storage-db23-construction-workload.nim.txt`, `build/storage-db23-observe.py` and
`build/storage-db23-measure/{builds,observations}.json`; they record source/compiler/library/binary
SHA-256 identities, flags and every resource receipt.

## Verification and limits

`make unit SUITE=full_state_trie_construction` checks independent complete-map roots over empty,
singleton and unsorted 2/17/65-entry shared-prefix maps, empty/32/33/256-byte payloads, caller
mutation, retained zero mutation ceilings, combined-error precedence, exact/short topology,
zero-hash preflight, actual provider refusal/recovery and 1,000 exact ARC retirement cycles.
Affected existing trie, replay, footprint, export, repository and StateStore consumers supply
regression coverage. Local checked macOS evidence remains distinct from exact-head Linux CI.

Full/light startup, authenticated partial state, production power-loss/scale qualification and
whole-block JAM parity remain open. Documented M1 framing is complete; this change adds no
complete-state serialization claim. A separately scoped light-state proof/trust contract is needed
before partial reads or persistence can be introduced.
