# Request-length namespace admissibility review

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`; source hashes are
in [pins.json](pins.json). This review reads `text/accounts.tex` service/request domains,
`eq:preimageconstraints` and `eq:deposits`; `text/definitions.tex` domains/deposit/gas constants;
`text/pvm_invocations.tex` Accumulate Functions gas wrapper, `solicit` (24), `write` (5) and
`provide` (27); `text/accumulation.tex` provision integration; and T in `text/merklization.tex`.
No dependency/toolchain pin or production behavior changes.

## Upstream disposition (2026-10-17)

Gray Paper [#542](https://github.com/gavofyork/graypaper/pull/542) is merged as
[07aee1e](https://github.com/gavofyork/graypaper/commit/07aee1ef23b63f93d0e2f29e53560cbc7c8c767c).
It excludes both marker lengths from the request domain. This supports the overlap finding below;
the fix has not been adopted into our pinned 0.8.0 target. Preserve the witnesses and current
behavior until the [release/vector checkpoint](state-clarifications.md). The analysis below is
about the pinned rules, not a claim that current upstream main still has this omission.

## Finding

The cited local rules do **not** exclude the two overlapping lengths. Two small, funded account
witnesses satisfy the checked account domains, preimage invariant and deposit equations, and the
fresh-request branch of solicit predicts OK. Their posterior T mappings contain duplicate keys
with **different values**. No multi-gigabyte preimage, allocated advertised-size buffer or Blake2b
collision is necessary. The current full E4 request domain and duplicate-key rejection remain
unchanged; this review does not invent a reserved-length rule.

These are **local-rule counterexamples**, not a proof of valid-block or genesis reachability.
A small test-only translation checks the cited predicates; Ragnarök does not execute a PVM in this
suite. Functional service code, complete invocation/implication state, funding history, every
cross-state invariant and complete block execution are not established. The result identifies a
missing exclusion in the inspected rules and a concrete clarification question, not a proven
network exploit or decoder defect.

## Common ingredients and deposit arithmetic

Use service 7, `h = Blake2b-256(b"p")`, zero gratis offset and readable 32-byte hash memory.
The register holding advertised length can represent either uint32 marker. The common accumulate
host wrapper requires sufficient gas; solicit's pinned constant cost is **2193**, with no
advertised-length memory read or linear length charge in that rule. The test assumes that gas
budget rather than executing instructions to reach the host call.

Account footprint and threshold use these pinned equations/constants:

```text
items  = 2 * request_count + storage_count
octets = sum(81 + advertised_length for request keys)
       + sum(34 + len(storage_key) + len(storage_value))
threshold = max(0, 100 + 10 * items + octets - gratis)
```

Footprint octets and balance use uint64 domains; items use uint32. A large advertised length
therefore produces a large integer deposit reservation, not a requirement to allocate its payload.
All computed fields and exact threshold balances below fit their stated domains, with gratis zero.

## Witness A: preimage overlap at 0xfffffffe

Predecessor maps:

```text
storage   = {}
preimages = { h: b"p" }
requests  = { (h, 1): [0] }
```

The small preimage hashes correctly and its actual length has an available history, satisfying
`eq:preimageconstraints`. Solicit `(h, 4294967294)` next. That **pair** is absent, even though the
hash already has a preimage and another length's history. The rule adds an empty requested history;
it does not inspect/reject an existing preimage under that hash. The invariant remains satisfied:
it requires the actual-length pair, not that every request length equal an existing preimage size.

Posterior items are **4**, octets **4294967457**, threshold/balance **4294967597**.
The two different mappings have the same full key:

```text
C(7, E4(4294967294) || h) -> b"p"   # preimage row
C(7, E4(4294967294) || h) -> b"\0"  # new requested-history row
```

Providing or allocating a 4294967294-byte blob is unnecessary. Later provisioning rules use the
actual supplied blob length and do not explain why this different-length request was forbidden.

## Witness B: storage overlap at 0xffffffff

Predecessor maps:

```text
storage   = { h: b"v" }
preimages = {}
requests  = {}
```

Solicit `(h, 4294967295)`. It is in the stated domain, absent from requests and fundable. The
preimage invariant holds vacuously. Posterior items are **3**, octets **4294967443** and
threshold/balance **4294967573**. The two different mappings share their full key:

```text
C(7, E4(4294967295) || h) -> b"v"   # storage row, raw key is the 32-byte h
C(7, E4(4294967295) || h) -> b"\0"  # new requested-history row
```

The stored value is one byte and its key is 32 bytes. No preimage is needed for this local witness.
The write rule also admits arbitrary readable storage keys subject to the deposit check, but this
suite uses the listed predecessor directly rather than claiming an executed write sequence.

## Reproducible checks and limits

```sh
make check
```

Six literal tests anchor exact footprint/threshold numbers, full-domain acceptance, correct
hash/content and actual-length history, tiny payload sizes and negative branches: unreadable hash,
duplicate empty history, one-below deposit and insufficient gas. The model covers fresh insertion;
restoration of a two-slot history explicitly raises an unsupported-case error instead of pretending
to implement that branch. It is test-only Python, not production account/PVM logic.

Seven checked native requests run the existing Nim composition API: one ownership selftest plus
three complete typed mappings per witness. Each predecessor and a control soliciting adjacent
non-marker length **0xfffffffd** reproduces its independent expected root and every entry byte.
Each overlapping posterior returns failure-only `DuplicateKey`. Metadata contains the derived
footprint and exact balance, and the preimage witness uses the real small blob/hash and its proper
available history. These improve on the earlier arbitrary-hash structural overlap checks.

Ignored `build/tests/runtime/results.json` records source identities/hashes, keys, local checks,
footprints, balances, successful roots, rejection verdicts, compiler flags and environment. Nim
2.2.12 ARC/Clang LTO retains all runtime guards. Linux CI runs the same checks and retains results;
local macOS arm64 validation does not claim Linux confirmation. No length-sized allocation occurs.

M1 parity remains qualified pending adoption of the upstream request-domain correction. The maintainer
has [parked the request-namespace question](state-clarifications.md) for Gray Paper 0.8.1/0.8.2 review. Preserve
current behavior and pending tests; no further clarification increment is scheduled against the
current pin. These witnesses remain local; the upstream correction is linked above. Nothing was posted externally
as part of this review.
