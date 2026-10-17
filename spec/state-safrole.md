# Safrole-related state components: entropy, rosters and time

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`:
`text/merklization.tex`, serialization T chapters **6, 7, 8, 9, 11**; `text/safrole.tex`,
validator keys/populations (`eq:validatorkeys`, `eq:valcount`) and entropy composition
(`eq:entropycomposition`). Chapter hashes and consumed vector identities are in [pins.json](pins.json).
No upstream, toolchain or primitive upgrade is involved.

## Implemented component group

`src/codec/state_safrole.nim` serializes one related group of top-level state components:

| Entry | Source | Exact raw value |
| --- | --- | --- |
| C(6) | Entropy accumulator/history | Four ordered 32-byte words, 128 bytes total; no count prefix. |
| C(7) | Staging validator roster | Canonical general-natural count, then ordered 336-byte records. |
| C(8) | Active validator roster | Same value schema, distinct chapter key. |
| C(9) | Previous validator roster | Same value schema, distinct chapter key. |
| C(11) | Most recent block timeslot | Exactly four little-endian bytes (E4), including leading zeroes. |

`entropyEntry`, `validatorEntry` and `timeEntry` return independent `StateEntry` payloads for the
existing [trie-root API](state-trie.md). Fixed entropy/time encoding has a small fixed allocation;
variable roster encoding applies caller resource ceilings before allocating. Input source arrays
are borrowed synchronously, must remain stable for the call, and are never retained. Returned entry
payloads are caller-owned mutable bytes; they must remain stable during a subsequent trie-root call.

Each validator record is `bandersnatch[32] || ed25519[32] || bls[144] || metadata[128]`, with
nominal field types. It is **336 bytes**, not the 64-byte Bandersnatch/Ed25519 pair used in header
epoch markers. Metadata is opaque bytes, with no text encoding or trimming. Roster order defines
indices; it is never sorted or deduplicated. Null and repeated records remain representable.
Structural encoding does not validate curve points, possession, metadata meaning or eligibility.

The chapter enum accepts staging/active/previous only. Pending keys belong to the multi-field
chapter-4 Safrole state and are deliberately excluded from this module; its separate
[chapter-4 codec](state-consensus.md) now covers them. This increment also excludes tickets,
sealer schedules, ring roots, epoch transitions and full Safrole execution. Other chapters and
service-account entries remain separate serialization increments. A root over these five entries
is a partial-mapping commitment, **not a complete JAM state root**.

## Decoding, limits and ownership

Fixed decoders return independent values and consumed counts of 128 or 4, respectively; incomplete
input is `Truncated`. Roster decoding accepts a canonical natural count followed by the complete
record payload. Unrelated suffix bytes stay with the caller, and consumed counts exist only on
success. Reserved/overlong natural forms return `NonCanonical` through the existing primitive.

`ValidatorStateConfig` supplies an explicit core count, element ceiling and complete encoded byte
ceiling. At least two cores are required. Population must be a multiple of three from **6 through
3 × cores**, as specified by `valcount`. The implementation compares `count div 3` to cores rather
than multiplying an untrusted configuration. Population constraints are independent of stricter
caller limits; no tiny/full profile is silently selected. The byte ceiling includes the natural
count prefix. Native wire and typed-storage extents are checked before multiplication/narrowing.

For typed roster entry sources, an invalid chapter representation is rejected first as InvalidTag.
The remaining error precedence is: invalid configuration, malformed count framing, invalid protocol population,
element ceiling, native extent overflow, byte ceiling, then incomplete payload. The full wire extent
is proved before decoder allocation. Allocation exhaustion retains the project's existing Nim
fail-stop policy; this API does not promise recoverable OOM.

`ValidatorStateSnapshot` is a value handle to private acyclic ARC storage of copied records. No
mutable sequence or foreign pointer is exported. `validatorCount` checks private storage presence; `validatorAt` checks the
nominal ordinal before conversion and returns a fixed independent record copy. Input destruction,
mutation of an extracted copy and caller reference reassignment cannot mutate retained state.
`StateComponentResult` default/failure variants contain only a reason, never a value, owner or
partial progress. Default handles and out-of-range ordinals return typed errors.

## Evidence and reproduction

Current reproduction uses the pinned toolchain and prepares native dependencies automatically:

```sh
make check
```

Six literal harness tests protect the independent byte/count reference. **3,068** native requests
cover exact entry keys and payloads, fixed-value endianness/history order, all proper entropy/time
truncations, every truncation of a six-record roster, selected larger record/prefix boundaries,
canonical natural transitions, populations through 1,023 and beyond, invalid cardinalities,
zero/one-core policies, per-count/complete-byte limits, massive counts/native overflow, overlong
and random malformed input, unrelated suffixes and three five-entry trie integrations. Independent
Python byte construction supplies expectations; trie integration uses the separate list-partition
oracle. The historical baseline used Nim 2.2.12, ARC, Clang LTO and every runtime guard.

Published inputs are taken from both pre/post states of tiny/full
`stf/safrole/*/enact-epoch-change-with-no-tickets-1.json` at vector commit
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Both JSON file hashes are frozen before
consumption. These four state sources provide named eta/tau/iota/kappa/lambda values. Their encodings
are **derived component fixtures**, not standalone published T(state) binary vectors or a claim of
passing the Safrole STF. No upstream generator is executed or source modified.

Native supplementary checks cover immutable snapshot retention, destructive wire/source mutation,
extracted-copy and handle independence, default-owner/index errors and default/failure variant guards. Two negative
compilation probes reject entropy-as-time and Ed25519-as-Bandersnatch substitution; a separate
privacy probe rejects access to retained roster storage.

Linux CI runs this suite after crypto/trie construction and retains logs, compiler commands,
request SHA-256 and results under ignored `build/tests/runtime/`. Local verification is macOS arm64;
Linux results require CI after push. Existing crypto parity gates remain unchanged.

The allocation-free `stateValidatorSize` and `stateValidatorPrefixSize` APIs share this roster
policy for chapter-4 whole-parent preflight. The standalone decoder uses the same prefix scan;
its framing and error precedence remain unchanged. The shared result family also names chapter-4
`InvalidTag` and `WrongVariant` errors; standalone roster wire framing has no tag or variant.
On the Nimony branch, InvalidTag also rejects invalid typed source chapters before entry creation.

## Nimony branch port

The [nightly trial](../docs/nimony-trial.md#nineteenth-increment-entropy-validator-rosters-and-timeslot-state)
verifies the same chapter 6–9/11 component contract with checked ARC/Clang LTO on macOS ARM64.
`StateComponentResult[T]` hides status/payload behind read-only error and success-precondition value
access. This guards fixed values, copied entries/records, sizes, retained owners and progress.
Private roster storage uses nullable acyclic ARC references and stable checked locals. Input remains
stable during synchronous scans/decoding; retained snapshots copy every field and export no mutable
storage. Returned `StateEntry` bytes remain caller-owned mutable payloads.

Run `make runtime`. It retains all
3,068 independent requests, six literal harness checks, four hash-checked derived state sources
and three partial five-entry trie integrations. It separately rejects default/failed value/owner/
record/progress reads and private/read-only storage bypasses, preserving both original nominal
checks. Maximum uint64 populations return LengthOverflow before multiplication or allocation.
The nightly permits unchecked integer-to-enum conversion, so entry construction explicitly checks
chapter 7–9 membership and returns InvalidTag for every other underlying byte representation; all
256 chapter bytes are tested without changing accepted roster encodings.
Chapter-4 tag/variant behavior now passes its separate [Nimony port](state-consensus.md#nimony-branch-port),
whose chapter-local result wrapper preserves the shared error vocabulary and private child results.

The native suite retains callee-local roster snapshots across source retirement, replaces owners
while aliases survive, mutates independent record/fixed copies and checks missing/high-index
errors. After warmup, 1,000 scoped ownership/fixed-value/error cycles return live allocator occupancy
to baseline. This is workload-specific ARC evidence, not general leak freedom or recoverable
allocation-failure support. Full M1, Safrole execution, broader crypto and Linux parity remain
separate gates; no dependency/compiler source patch or alternate wire representation is used.

## Execution progression

The fixed codecs remain separate from the [entropy/time execution slice](entropy-transition.md),
which implements the accumulator/history equations and atomic C(6)/C(11) updates. It does not
rotate validator sets, authenticate VRFs or execute the complete Safrole state transition.
