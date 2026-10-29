# State-key and trie-node layout foundation

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, state
merklization chapter `text/merklization.tex`, state-key functions C, node encodings B/L and node
identification within M. The complete chapter hash is now in [pins.json](pins.json). This is
separate from C.1/C.2 block framing and from the chapter's general binary Merkle trees. No upstream
revision, primitive backend or toolchain changes.

## Scope and state keys

`src/codec/state/layout.nim` implements fixed state-key/node layout and node hashing. It does **not**
construct a trie/root from entries, serialize state components T(state), derive service storage
namespace prefixes automatically, build proofs, execute transitions or implement persistence.
Root construction is now covered separately in [state-trie.md](state-trie.md); the other
responsibilities remain future increments. In particular, hashing a zero-filled branch node is not
the empty-trie's zero identity rule; empty-trie handling belongs to trie construction.

`StateKey` owns exactly 31 bytes. `StateChapter` is a nominal octet, and service identifiers reuse
the existing E4 `ServiceIndex` domain. Constructors follow the three exact C alternatives:

- `chapterKey(i)`: chapter byte i, followed by thirty zero bytes.
- `chapterServiceKey(i,s)`: chapter i, then E4 service bytes n0,n1,n2,n3 at offsets 1,3,5,7;
  all other offsets are zero.
- `hashedServiceKey(s,h,limit)`: Blake2b-256 hashes the **exact raw h** without a new length/domain
  prefix. Service bytes alternate with digest bytes a0..a3 at offsets 0..7; digest bytes a4..a26
  occupy offsets 8..30. Digest bytes a27..a31 are omitted. An explicit byte ceiling is checked
  before hashing borrowed input. Actual storage/preimage/request namespace preimages from T
  remain the caller's responsibility; this helper does not guess the correct namespace.

All constructors return independent fixed values. Input to hashing remains stable only for the
synchronous call; no caller pointer or detached span is retained. Fixed chapter/service sources
cannot overflow their wire domains. Backend failure publishes no constructed key.

## Canonical 64-byte nodes

`EncodedStateNode` owns a complete 64-byte representation. Node discriminator bits use the
chapter's **most-significant-first** `bits` notation, not C.1's least-significant-first packed
Boolean-sequence codec. There is no general-tree `$node` domain prefix on these state trie nodes.

`encodeStateBranch(left,right)` implements B: clear only the most-significant bit of the full
32-byte left child hash, then append all 32 right bytes. Two left hashes differing solely in
that bit have the same B representation, intentionally. Decoding therefore returns a nominal
`LeftChildCommitment` with exactly the retained **255 bits**, high bit zero; it cannot be passed
implicitly where a complete `StateNodeHash` is required. The decoder does not invent the lost bit.
Future traversal/proof code must compare or resolve the truncated commitment accordingly.

`encodeStateLeaf(key,value,limit)` implements L:

- Value length 0..32: header `80 | length`, all 31 key bytes, exact value and zero padding through
  the final 32-byte half. Header `a0` is the valid 32-byte embedded boundary.
- Value length greater than 32: header exactly `c0`, the same key and Blake2b-256(value).
  The regular leaf contains no value-length discriminator or original value bytes.

The explicit raw-value byte ceiling precedes copying/hashing. The current backend is used only
for the primitive; keys, headers, padding and domains remain Nim code. No input-derived heap
snapshot is needed because every output/metadata field has a fixed copied extent.

`decodeStateNode` first requires all 64 bytes, then accepts branch headers 00..7f, embedded
headers 80..a0 with **zero unused padding**, or regular header c0. Embedded lengths 33..63 and
regular headers c1..ff are `NonCanonical`. A success consumes exactly 64 bytes and leaves unrelated
suffixes with the caller. The tagged `StateNodeInfo` copies only the selected fields; regular
leaves expose a distinct `StateValueHash`, not a fabricated original value or child-node identity.
Regular-leaf checks establish flags/layout, not existence or length of a corresponding preimage.

`encodeStateNode(info)` re-emits copied metadata, validating partial-left high bit, inline length
and all inline padding before success. It can re-emit a regular leaf from its committed hash
without claiming the long value is available. `hashStateNode(encoded)` validates canonical
layout, then returns raw Blake2b-256 of those exact 64 bytes as a distinct `StateNodeHash`.
Manually constructing a nominal encoding cannot bypass header/padding checks before hashing.

## Results and lifetimes

These APIs return new fixed values rather than writing caller buffers, so source/destination
alias management and mutable backing-buffer ownership are unnecessary. Changing caller input,
a returned copy or another copied metadata object cannot alter earlier results. Source values
are stable during the call. No metadata pointer, partial hash upgraded to full identity, borrowed
span, allocator handle or secret material is exported.

`StateLayoutResult[T]` carries data/progress only in `None`; every failure/default carries its
reason alone. Node metadata is independently tagged, retaining runtime guards for inactive
branch/embedded/hashed fields. Blake2b failure maps to `BackendFailure` without a default digest.
The exceptional-point Ed25519/Bandersnatch gates are unaffected by this layout increment.

## Evidence and reproduction

Run `make check` for current reproduction. The original baseline used Nim 2.2.12, ARC and
checked Clang LTO; its numerical observations remain a record of that increment.
Python's independent `hashlib.blake2b(digest_size=32)` and direct byte equations supply expectations.

Six literal harness checks protect **12,233** deterministic native requests: all chapter octets,
E4 index boundaries/interleaving, raw preimage limits, all 256 node headers, every embedded length
source byte, every unused padding position with low/high/all-bit pollution, 32/33-byte leaf boundary,
cryptographic input boundaries, all node truncations, unrelated suffixes, malformed arbitrary bytes,
metadata source rejection, regular metadata re-emission and canonical raw-node hashing. Native
checks additionally cover destructive caller mutation, fixed-copy independence, intended left-bit
loss and selected/default result/node guards. Three nominal compilation probes reject state keys,
partial commitments and value hashes in full child-node hash positions.

The vector repository at pinned `d3c089c9a1d5352ad353626d7a2db8589f137b2a` contains historical
`trie/trie.json` with **32-byte input keys**, unlike current C's 31-byte key domain. Tests freeze
that exact Git blob's SHA-256 without changing sparse checkout or executing its generator. Only
five **singleton** cases are used: explicitly discard their last legacy key octet, construct the
current 31-byte-key leaf, and compare its node hash with the recorded root. These are labelled
historical projected compatibility checks, not unmodified 0.8.0 input conformance or multi-entry
trie verification. Modern byte/field behavior is governed by the pinned paper and independent
reference. No full trie root or proof is claimed by these passing tests.

CI runs this suite after the native primitive library is built, retaining build commands, logs,
compiler diagnostics and request digest/results under ignored `build/tests/runtime/`. Provenance
checks read the frozen historical blob directly at its recorded Git revision; partial clones may
materialize that promised data object through Git. Source files and gitlinks remain unchanged.
Local verification is macOS arm64; Linux x86-64 validation occurs in CI after push. Root
construction over serialized entries has its separate [contract](state-trie.md) and test suite.

## Nimony branch port

The [nightly trial](../docs/nimony-trial.md#seventeenth-increment-state-keys-and-fixed-node-layouthashing)
verifies this same layout contract with checked ARC/Clang LTO on macOS ARM64. Results hide their
status/payload behind read-only error and success-precondition value access. `StateNodeInfo` hides
its tag and alternative fields; kind is read-only and every copied field requires its own selected
alternative. Nimony raw variant fields are not relied upon for access protection.

Source metadata is constructed with `branchNodeInfo`, `embeddedNodeInfo` and `hashedNodeInfo`.
These copy exact fields and select the tag together. Canonicality remains checked by
`encodeStateNode`, so intentionally invalid source lengths, partial commitments and padding still
return NonCanonical rather than being normalized. Default metadata remains an all-zero branch;
default results remain Uninitialized. Caller input and returned/copied fields remain independent.

`make runtime` builds pristine
native primitives, runs all 12,233 preserved independent requests and six literal harness checks,
and checks default/failed result reads, every wrong metadata alternative, private/read-only fields
and the three existing nominal-domain probes. The three hash compositions also reject injected
native refusals without exposing a default key/node/hash. Fault injection is linked only into
separate test processes; the independent corpus uses the production bridge. Historical singleton
projections retain their limited provenance described above. Trie roots, remaining M1 state codecs
and Linux parity are separate migration gates.
