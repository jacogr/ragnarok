# Safrole basic state: chapter 4

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` T chapter **4**, `text/safrole.tex` basic state/key/slot-sealer definitions,
and `text/serialization.tex` C.2's `safroleticket` encoding. Exact chapter hashes and consumed
published fixture hashes are in [pins.json](pins.json). No dependency or toolchain changes.

## Exact schema and sources

`src/state_consensus.nim` provides `safroleStateEntry(source, config)` for C(4) and
`decodeSafroleState(input, config)` for one complete value prefix. Its serialization is:

```text
E(pending count) || pending[336 bytes each] || ring root[144] || schedule tag[1]
|| schedule[epochSlots entries, no count] || E(accumulator count) || accumulator[33 bytes each]
```

The pending roster reuses full validator records and the 6..3*cores, multiple-of-three population
policy from [state-safrole.md](state-safrole.md). It is not a header epoch-marker key-pair roster.
`StateRingRoot` owns exactly 144 opaque bytes and is distinct from a same-width validator BLS key,
trie root or entropy. Structural decoding does not establish a valid ring commitment.

The schedule source is a tagged `SealerSchedule`:

- Tag **0**: exactly `epochSlots` winning tickets, each identifier[32] followed by E1 attempt[1].
- Tag **1**: exactly `epochSlots` opaque Bandersnatch keys[32].

Every other tag is `InvalidTag`. Fixed schedules have no count prefix. The accumulator has its own
canonical general-natural count, at most `epochSlots`, then the same 33-byte tickets. Ticket IDs,
`TicketAttempt` and `EpochSlots` reuse the existing C.2/header domains. Proof-bearing 785-byte
extrinsic ticket records are a different schema and never appear here. All E1 attempts 0..255
remain structurally representable; dynamic attempt eligibility is outside this codec.

Sequence order is preserved. The codec does not apply the outside-in schedule permutation, sort
or select accumulator scores, reject repeated IDs as a state-transition condition, derive fallback
keys or check proofs. These are sequence encodings in T, not canonical-set encodings. Safrole
transition rules still require sorted/eligible accumulator contents in valid consensus state;
a structurally decoded arbitrary sequence is not evidence of that validity.

## Whole-parent preflight and ownership

`SafroleStateConfig` supplies the pending roster policy, positive fixed epoch length, caller
accumulator ceiling and complete chapter byte ceiling. No tiny/full profile is inferred. Epoch
size must fit native typed ticket storage before narrowing. The accumulator is bounded separately
by the chain epoch cardinality and caller resource policy. Every field, including both natural
prefixes, ring root, tag and schedule, contributes to the parent byte ceiling.

New allocation-free `stateValidatorSize` and `stateValidatorPrefixSize` helpers share the existing
roster policy; standalone roster decoding now delegates to the same prefix scan. Parent encoding
validates all source counts and complete byte extent before allocating its roster scratch or final
entry. Parent decoding validates every late field before allocating **any** child or parent owner.
Checked stride arithmetic precedes multiplication/addition; malformed huge counts never narrow
before population and host bounds. Roster and whole-parent byte ceilings remain independent.

On decoding, epoch configuration is checked first, followed by canonical roster framing, roster
population/resources and complete roster extent. Root/tag and fixed schedule extents are then
checked against parent policy before access; accumulator framing, population, policy and complete
payload follow. Invalid configurations, tags, count/byte limits and truncations expose no owner or
partial progress. Prefix success consumes only the complete component; unrelated suffixes remain
with the caller. Correct chain configuration is the caller's responsibility for fixed schedules.

`SafroleStateSnapshot` is a value handle to private acyclic ARC storage. It composes an immutable
pending-roster owner with private schedule and accumulator copies. `safroleInfo` returns fixed
copied metadata; `pendingValidatorAt`, `sealerTicketAt`, `sealerKeyAt` and `accumulatedTicketAt`
return fixed independent child values. Default handles and out-of-range nominal indices are typed
failures; schedule extraction through the inactive branch returns `WrongVariant`, never a default
key/ticket. Private sequences and foreign pointers are not exported.

All source arrays and decoder input are borrowed only during the synchronous call and must remain
stable during that call. Input destruction, mutation of an extracted value, source mutation after
encoding or replacing one owner handle cannot alter retained results. Returned entry bytes are
caller-owned and must stay stable during a subsequent trie call. Allocation exhaustion retains the
existing Nim fail-stop policy. No cryptographic verification or backend invocation occurs in this
codec; structural tests leave existing crypto gates unchanged.

## Evidence and reproduction

After `python3 tests/test_crypto.py`, run:

```sh
python3 tests/test_state_consensus_harness.py
python3 tests/test_state_consensus.py
python3 tests/test_state_safrole.py
```

Six literal oracle checks protect independent offsets, widths, ticket field order, prefix parsing,
policies and native bounds. **7,298** native requests compare independently constructed bytes,
fields/consumed counts or failure-only reasons: both schedule modes, all proper truncations of
representative parents, every reserved tag 2..255, every E1 attempt 0..255, 127/128 accumulator
count framing, late overlong/huge counts, exact/one-below byte policies, pending and accumulator
limits, fixed schedule cardinalities, zero/oversized epochs, arbitrary order/repeated values,
unrelated suffixes, randomized complete states and ten single-entry trie integrations. These
roots commit only C(4), not a complete JAM state. Native selftests verify private parent/child
retention, source/input mutation, copied values/handles, selected-variant/index errors and default/
failure guards. Two nominal compiler probes reject BLS-key-as-ring-root and validator-as-slot
substitutions; one privacy probe rejects access to parent storage.

Eight published sources come from both pre/post states of tiny/full
`enact-epoch-change-with-no-tickets-1.json` and `publish-tickets-with-mark-5.json` at vector revision
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. They supply named gamma_k/gamma_z/
gamma_s/gamma_a fields, including ticket and fallback schedules. SHA-256 pins are checked before
consumption. Encodings are explicitly derived component fixtures, not standalone published T
binaries or claims of passing those Safrole STFs. No generator is executed or vendor source changed.

Checked Nim 2.2.12 ARC/Clang LTO builds retain all runtime guards. The native tests verify the
64-bit int/33-byte ticket assumptions used for reference extent checks. Ignored
`build/state-consensus/` retains commands, request SHA-256, logs and results; Linux CI runs the suite
and uploads diagnostics. Local validation is macOS arm64; Linux results require CI after push.

M1 framing-baseline coverage remains distinct from full state serialization. Chapter 5 now has its
separate [dispute-state codec](state-disputes.md); chapter 3 has its
[recent-history codec](state-history.md). Next planned: chapters 14–15 ready and accumulated work.
Chapter 10 has its
[availability-state codec](state-availability.md).
The [M1 checklist](../docs/m1.md) records remaining state chapters and service entries;
this increment does not close them.
