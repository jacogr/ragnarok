# Boolean and general bitstring codecs

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, Appendix C.1.1
natural encoding, C.1.3 discriminator encoding and C.1.4 bit sequence encoding. The notation
chapter's Boolean-to-bit equivalence maps false to 0 and true to 1. Both complete chapter hashes
are already recorded in [pins.json](pins.json); no dependency or source pin changes are needed.

## Wire and public APIs

`decodeBoolean` / `encodeBoolean` handle one standalone Boolean as exactly `00` or `01`.
Any first octet from 2 through 255 is `NonCanonical`, not an alternative true value. A successful
decoder consumes one octet; trailing bytes belong to a subsequent field.

`encodeBits` / `decodeBits` handle variable-length bitstrings. A canonical general natural gives
the number of **logical bits**, followed by `ceil(count/8)` packed octets. Within each octet,
the first logical bit has weight 1, the second weight 2, and so on. The last partial octet has
zero unused high bits. This is the encoder's image and therefore the accepted inverse; nonzero
padding is `NonCanonical`. It is consistent with existing assurance bitfield padding policy.
The notation helper `bits(blob)` uses most-significant-first ordering for its separate purpose;
it does not override Appendix C.1.4's serialization order.

`encodeFixedBits` / `decodeFixedBits` omit the count prefix and require an explicit `BitCount`.
Fixed encoding requires the source sequence length to equal that count. Logical source bits
are ordinary typed Nim `bool` values; the encoder does not accept unvalidated packed padding.
`BitCount` and `BitLimit` are distinct uint64 domains, incompatible with raw counts and byte
budgets. Both fixed and variable operations enforce the explicit logical-bit resource limit.
Zero fixed bits encode to no bytes; zero variable bits encode as one zero count octet. Decoders
consume one prefix; callers must require full consumption when suffixes are prohibited.

Example: logical bits `100000011` serialize as `81 01` when fixed, or `09 81 01` when variable.
The first `1` is the low bit of `81`; the ninth bit is the low bit of the second payload octet.

## Validation, atomicity and ownership

Variable decoding validates natural framing/canonicality first. Fixed decoding starts with the
caller count. Both then check bit policy, complete packed input extent and final padding before
any input-derived allocation or count narrowing. Packed-byte ceiling arithmetic uses division
and remainder, never the overflowing uint64 expression `count+7`. Input extent is compared while
still uint64, proving host-int conversion and subsequent offsets safe. Huge declared counts
with insufficient bytes return `Truncated`; counts above policy return `LimitExceeded` first.
There is no unpacked count-sized Boolean allocation during decoding.

Success creates `OwnedBits`: a private acyclic ARC snapshot of the exact validated packed payload
and logical count. It retains no caller pointer or length prefix, and never exports mutable
packed storage or detached spans. Input must remain stable during the synchronous decode, then
may be changed/released. Last-owner destruction releases the snapshot. Allocation exhaustion
retains Nim's existing fail-stop behavior rather than promising recoverable allocation failure.

`bitsInfo` copies count/packed-byte metadata; `bitAt` copies one Boolean through its matching
owner. Invalid/default owners and signed negative/out-of-range indices fail normally. An empty
validated owner is distinct from a default handle. `encodeOwnedBits` and `encodeOwnedFixedBits`
can reframe either capture, because the underlying logical string is independent of framing;
a fixed re-emission must still match the exact stored count. A stricter new bit limit is always
checked, even on previously validated owners. Capturing copies packed bytes once; indexed reads
and re-emission allocate no new payload. These APIs do not alter existing specialized assurance
or dispute codecs.

Borrowed encoding checks exact fixed cardinality, logical policy, complete capacity, typed
source byte extent and source/destination aliases before writing anything. Source bool storage
must remain stable for that synchronous call. Whole written destination overlap is rejected,
including a prefix that would overwrite a later source bit. Owner re-emission protects every
immutable packed byte against the whole written destination. Empty ranges require no element
address. Success preserves spare suffix capacity; any failure leaves the entire output unchanged.
Standalone Boolean encoding copies its value and requires one output octet.

`BitResult[T]` publishes a value only in its `None` alternative; failures/defaults carry only
their reason, with no Boolean, owner, consumed count or written extent. Checked optimized builds
retain all variant field guards. Fixed count mismatch precedes policy/capacity; owner operations
check ownership before accessing count. Decoding never exposes partial bits or progress.

## Verification

Run `python3 tests/test_bits_harness.py` and `python3 tests/test_bits.py` with Nim 2.2.12, ARC and
checked Clang LTO. Six literal known-answer tests protect the independent Python mathematical
reference. The native corpus contains **11,274** deterministic requests: all 256 standalone
Boolean octets, all 256 final-byte patterns for logical lengths 1..8 under both framings, natural
count-width/packed-byte boundaries, empty/exact/short/spare buffers, every small truncation,
noncanonical counts/padding, strict resource policies, maximum uint64 claims and arbitrary bytes.
Encoder inputs are independently constructed logical sequences; decoder observations compare
each bit, packed prefix, count, consumed extent and both owner framing forms against the oracle.

The pinned published corpus has no dedicated general-bitstring/Boolean fixture family. Tests
therefore also verify the existing tiny/full assurance bitfields and distinct dispute Boolean
values through the new primitive APIs, after frozen JSON hashes are checked. These field checks
do not reinterpret or claim structural acceptance of an otherwise invalid full dispute sample.
Native regressions cover caller mutation/release, retained handles, copied output independence,
stricter owner policy, defaults, indexed bounds, failure atomicity, borrowed/private-wire aliases
and inaccessible failed-result alternatives. Two nominal and one privacy compiler rejection
protect the public boundary. Private-wire alias tests include only this project's own module;
no production backing pointer or compiler/private-runtime API is introduced. Linux CI runs the
same checks and retains build diagnostics, compiler rejection logs and a request digest/result
manifest under ignored `build/bits/`. This is codec coverage, not state/cryptographic validation.
