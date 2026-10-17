# Last accumulation outputs state: chapter 16

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` T chapter **16**, `text/recent_history.tex` `eq:lastaccoutspec`,
`text/accumulation.tex` final accumulation outputs, and C.1 sequence/E4/fixed-octet framing.
`text/notation.tex` defines sequences as ordered independently of their values. Exact normative
source and fixture hashes are recorded in [pins.json](pins.json). No compiler, toolchain or
upstream revision changes.

## Exact schema and domains

`src/codec/state_outputs.nim` provides `outputLogEntry(values, config)` for C(16) and
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
are serialized without cryptographic verification. Existing crypto parity gates remain unchanged.

## Evidence and reproduction

Run the complete checks; Make prepares native dependencies:

```sh
make check
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
promised objects without source/checkout/gitlink changes. Ignored `build/tests/runtime/` records
build commands, corpus SHA-256, native/type diagnostics and per-trace path/phase/hash/count verdicts.
The historical Nim 2.2.12 ARC/Clang LTO retained assertions/bounds/range/field/overflow checks.
Linux CI runs the
suite and retained diagnostic artifacts. Local validation is macOS arm64; Linux confirmation
requires CI after push.

State chapters **1–16** now have typed serializers to pinned-paper framing. Chapter 13 follows
the accepted compact gas and numeric service-key policy; no alternate-width fallback is supported. **M1 state parity is not complete**: keyed service storage/
preimage/request entries and whole-state composition/root evidence remain. Next planned bounded
increment: **whole-state composition/root evidence and parity review**. See the [M1 checklist](../docs/m1.md).


## Compiler-port evidence

The numerical/compiler observations below record the original migration increment; see
[testing](../docs/testing.md) for current cumulative coverage and revision-specific CI results.

The experimental branch ports this family to pristine Nimony 0.6.3 nightly `5b51edfed`, preserving
its wire format, resource policies, sequence semantics and failure precedence. `OutputLogResult[T]`
hides status/payload behind a read-only reason and a success-only accessor, including internal
extent proofs. Nullable owner storage is checked through stable retained locals; extracted fixed
pairs remain independent copies. No upstream patches or private runtime hooks are used.

Run `make runtime` with the pinned
compiler; Make installs it as needed. The runner includes the original 1,901-request corpus, six
literal checks, eight
exact published empty-log components and 21 partial C(16) roots. Two native suites also exercise
retained/replaced owners, escaped fixed pairs, copied fields and explicit native arithmetic
boundaries. Thirty-two isolated actual/default payload reads reject through the exact success
contract, ten private/read-only compiler probes reject bypasses, and two nominal probes reject
root/commitment and service/index substitutions. The scoped 1,000-cycle lifetime workload returns
public live occupancy from 192 to 192 bytes on local macOS ARM64, checked ARC/Clang LTO.

Linux confirmation remains CI work. Typed chapters 1–16 are ported, but full M1 migration still
requires service-keyed state and whole-state composition. The next bounded Nimony family is
C(255, service) account metadata. See the [trial](../docs/nimony-trial.md) for cumulative totals
and remaining gates; no accumulation transition or output-log commitment parity is claimed here.
