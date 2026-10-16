# Last accumulation outputs state: chapter 16

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` T chapter **16**, `text/recent_history.tex` `eq:lastaccoutspec`,
`text/accumulation.tex` final accumulation outputs, and C.1 sequence/E4/fixed-octet framing.
`text/notation.tex` defines sequences as ordered independently of their values. Exact normative
source and fixture hashes are recorded in [pins.json](pins.json). No compiler, toolchain or
upstream revision changes.

## Exact schema and domains

`src/state_outputs.nim` provides `outputLogEntry(values, config)` for C(16) and
`decodeOutputLog(input, config)` for one complete sequence prefix:

```text
E(pair_count) || (E4(service_id) || commitment[32]) pairs in supplied sequence order
```

Every pair is exactly 36 bytes. There is one canonical natural outer count, including a zero
count for an empty sequence. There is no inner tuple/hash count, optional tag or natural service
encoding. All uint32 service IDs and all opaque commitment octets are preserved exactly.

`AccumulationOutput` pairs the existing `ServiceIndex` with a distinct `OutputCommitment`,
separate from trie/state roots. `OutputLogIndex` is a nominal sequence ordinal. `OutputLogConfig`
contains independent caller element and complete parent-byte ceilings; no protocol hardcoded
output count is invented.

The last-output state domain is a sequence and T traverses it with ordered membership. Its
codec preserves supplied order, repeated service IDs and duplicate pairs structurally. It does
not sort by service/hash or deduplicate the sequence. Deriving the canonical sequence from an
accumulation result set, checking one output per actually accumulated service or validating the
resulting output-log commitment belongs to the transition/import layer. Structural acceptance
does not certify that arbitrary duplicate/descending sources could arise from a valid block.

## Resource and ownership contract

Count framing errors are reported before resource policy. Caller element policy precedes native
wire/storage extent checks; checked subtraction/division prove count*36 + prefix and typed fixed
record allocation fit native addressing before narrowing. The complete byte ceiling includes
the count prefix even for an empty log. The decoder requires the **entire** announced payload,
including the final commitment byte, before allocating any owner or copying earlier pairs.
The encoder preflights the complete extent before allocating one fresh C(16) payload. Fixed
source fields already have their exact domains and need no payload-derived validation.

`OutputLogResult` defaults/failures carry only a reason. Prefix success binds a complete
`OutputLogSnapshot` to its consumed extent; suffix bytes remain with the caller. Complete entry
callers must additionally require consumed == supplied value length. Missing/default owners
and invalid indices return typed failures rather than fabricated empty sequences/commitments.

Snapshots are value handles retaining private immutable acyclic ARC storage. `outputLogCount`
returns a copied count and `outputLogAt` checks a nominal ordinal before narrowing and returns
an independent fixed pair. No mutable retained arrays, pointers or detached spans are public.
Caller input/source mutation, replacing one owner handle, parent scope exit and edits to extracted
pairs cannot affect retained data. Source/input stability is required only during synchronous
calls. Encoded entry bytes belong to the caller and stay stable during later [trie calls](state-trie.md).
Allocation exhaustion follows the existing Nim fail-stop policy.

This module does not execute accumulation, hash service output, build the accumulation belt,
validate service accounts, enforce eligibility or calculate state transitions. Opaque commitments
are serialized without cryptographic verification. Existing crypto and chapter-13 trace parity
gates remain unchanged.

## Evidence and reproduction

After `python3 tests/test_crypto.py`, run:

```sh
python3 tests/test_state_outputs_harness.py
python3 tests/test_state_outputs.py
python3 tests/test_spec.py
python3 tools/format.py --check
```

Six literal tests anchor empty framing, exact E4 service width/little-endian order, fixed commitment
width, sequence-order/duplicate preservation, canonical count 128, count/byte policy, native extent
overflow and late truncation. **1,901** native requests compare keys/bytes, copied logical service/
commitment fields, consumed extents or failure-only reasons against independent Python equations
computed before native execution. Source fields are decimal service IDs and literal commitments,
built without production decoding. Decode observations extract fixed values after destroying
original input rather than using native round trips as expected answers.

Cases include every proper truncation of a mixed three-pair log; every commitment octet; service
boundaries 0/1/127/128/255/256/65535/65536/2^24/uint32-max; canonical count boundaries
0/1/2/127/128/129/255/256/1024; empty logs; duplicates/descending services and arbitrary hash
order; exact/one-below count and byte ceilings; missing/overlong/huge count prefixes; native
capacity announcements; suffixes; 250 deterministic nontrivial sources with single-byte and raw
mutations; and **21 partial C(16) roots**. Supplementary native tests protect retained scope,
source/input/pair independence, owner replacement and default/index/result guards. Two negative
compiler probes reject trie-root-as-output-commitment and service-ID-as-sequence-index; one
rejects private storage access. Runtime checks remain enabled under ARC/Clang LTO.

At vector revision `d3c089c9a1d5352ad353626d7a2db8589f137b2a`, the four exact blobs
`traces/fuzzy/00000010.json`, `traces/storage/00000001.json`,
`traces/storage/00000002.json` and `traces/preimages/00000001.json` supply **eight unchanged
pre/post C(16) entries**. Each consumes completely and re-emits identically. All selected entries
are the single byte 00: this is published **empty-log evidence only**. Nonempty field/order/policy
coverage is explicitly authored; no nonempty published conformance is claimed. No fixture fields
are rewritten and no accumulation STF or upstream generator executes. Roots commit C(16) alone,
not a complete JAM state, accumulation log root or proof.

Every consumed Git blob is SHA-256 checked before parsing; partial clones may fetch exact
promised objects without source/checkout/gitlink changes. Ignored `build/state-outputs/` records
build commands, corpus SHA-256, native/type diagnostics and per-trace path/phase/hash/count verdicts.
Nim 2.2.12 ARC/Clang LTO retains assertions/bounds/range/field/overflow checks. Linux CI runs the
suite and retains diagnostic artifacts. Local validation is macOS arm64; Linux confirmation
requires CI after push.

State chapters **1–16** now have typed serializers to pinned-paper framing, with chapter 13's
trace key-width gate still open. **M1 state parity is not complete**: keyed service storage/
preimage/request entries and whole-state composition/root evidence remain. Next planned bounded
increment: **keyed service storage/preimage entries**. See the [M1 checklist](../docs/m1.md).
