# Typed state composition

Target: Gray Paper v0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/merklization.tex` T and trie equations, with the component-specific C.1/C.2 contracts linked
from [M1](../docs/m1.md). Source/vector identities remain those in [pins.json](pins.json).
Upstream pins and toolchains are unchanged. Dictionary widths now follow the supported migration;
statistics gas follows the [accepted compact policy](state-clarifications.md); request namespace
is the remaining parked state-parity question.

## Chapter capture and ownership

`src/codec/state_composition.nim` provides `captureStateChapter(chapter, bytes, profile, policy)` and
`composeState(chapters, services, limits, maxStorageKeyBytes)`.

`StateChapterId` names all sixteen required slots. Capturing dispatches to the existing typed
chapter decoder, requires its consumed extent to equal the entire supplied value, then retains
an independent byte copy in private acyclic ARC storage. A valid prefix followed by any suffix
returns `TrailingBytes`. Primitive truncation/noncanonical/policy/overflow failures remain
identifiable; child-specific schema errors map to `InvalidComponent`. Failed/default results
carry only their reason, never a snapshot, root or partial cursor.

`StateProfile` explicitly binds captures to cores, current/previous validator populations and epoch
length. The common profile requires 2..341 cores, supported current/previous populations (6..3*cores,
multiples of three) and a positive epoch length. Existing child codecs still enforce their own
exact shapes and typed extent checks. `StateChapterPolicy` supplies a conservative common item
ceiling for each child's existing item policies and an independent complete-value byte ceiling.
It is not an additional serialization discriminator. Captures made with different resource
ceilings can compose; captures with different profiles cannot.

Existing typed component encoders feed capture through their complete entry value. Captured
chapters are validated immutable serialization snapshots; the compositor retains their exact
bytes rather than extracting/re-encoding every logical field. There is no alternate-width decoder
or top-level raw-entry escape hatch for the sixteen mandatory slots. A default handle, misplaced
valid chapter or mixed profile fails before output mapping allocation.

## Whole mapping and service sources

`StateService` holds a service identity, fixed version-zero metadata and typed arrays of storage,
preimage and request records. Existing single-entry encoders derive every key and payload. Raw
storage/preimage values have no extra length framing; request histories preserve the tagged
0..3-slot union and full E4 length domain. Empty service arrays produce just the sixteen chapter
entries; an otherwise empty listed service still contributes its 89-byte metadata entry.

The optional `captured` list accepts the existing immutable service/key-bound opaque value handles,
supporting implementations that retain Merklization-ready keys without original storage keys.
Each handle must be valid and belong to the enclosing service. This path preserves already keyed
raw bytes; it cannot certify their original storage/preimage/request lookup identity or request
history framing. The published composition checks below label these values explicitly as opaque.

Before allocating the final mapping or deriving any service key, composition checks every chapter
and nested service descriptor against the parent's entry count, per-value and aggregate byte
ceilings. Subtraction-based charging prevents aggregate overflow; metadata and exact history sizes
are included. Raw storage key work has its own byte ceiling. Existing encoders then produce the
service entries, and the trie preflights complete key uniqueness/topology before commitment.
The node ceiling bounds nonempty leaf/branch hashing. Allocation exhaustion follows Nim's existing
fail-stop policy; no recoverable allocation-failure contract is added.

Duplicate identities always reject, including repeated services, repeated storage keys, chapter
collisions and both known request/preimage/storage namespace overlaps. No sorting, deduplication
or last-writer policy changes the source mappings. The input remains stable during the synchronous
call; no caller-owned mutable storage is retained.

`StateSnapshot` privately owns the completed mapping and copied commitment. `stateCommitment`
returns copied fixed root/count metadata; `stateEntryAt` takes a nominal `StateEntryIndex` and
returns a fresh independent entry copy. Mutating an extracted entry or replacing an owner handle
cannot alter retained entries or the commitment. No mutable snapshot bytes or detached spans are
public. Default owners and out-of-range indices return typed failures.

Profile association is a structural contract, not execution validation. Cross-component roster
relationships, referenced-account existence, privilege/gas eligibility, metadata footprint accuracy,
preimage hash/content validity and request chronology/reachability remain contextual state rules.
Opaque captures and successful roots do not turn these assertions into validated chain state.

## Evidence

Run after building the native crypto library:

```sh
python3 tests/test_state_composition_harness.py
python3 tests/test_state_composition.py
python3 tools/format.py --check
```

Seven literal harness checks anchor exact chapter extents, failure precedence, service metadata,
present-empty storage, complete parent accounting, opaque identities and both namespace overlaps.
**14,471** checked native requests compare exact capture verdicts, every complete key/value entry,
roots and entry/node counts against independent Python byte/list-partition/hashlib equations.
Cases include every proper truncation of all sixteen authored chapter shapes, suffixes, stricter
item/byte policies, invalid profiles, arbitrary raw inputs, independent parent ceilings, duplicate
sources, nonempty C12/C13 sources under the recorded interpretation, all request-history modes,
wide service IDs, multi-service permutations and varied raw values. Supplementary native checks
cover encoder-to-capture composition, input/output mutation, retained owners, profile/chapter
association, wrong-service opaque handles, missing/default owners, nominal indices and guarded
failure variants. Two negative compiler probes reject raw-entry-as-chapter and service-as-ordinal;
two further probes reject direct access to chapter and whole-state private storage.

The seven already-pinned trace blobs listed in [state-roots.md](state-roots.md) supply **224**
unchanged component observations (16 chapters times 14 states), with exact blob/value hashes:
**all 224 capture completely** after the dictionary-width migration. No decoder fallback or
fixture repair is installed. All fourteen complete mappings compose end to end and reproduce
their published roots (ten distinct roots). Metadata is decoded to fixed typed records and encoded
again; remaining keyed service values use explicitly labelled opaque service-bound captures.
Metadata identification checks the full C(255,service) equation, not just its first byte. No request
lookup identities or original storage keys are guessed from hashes. Selected raw C12 dictionaries
remain empty; nonempty C13 dictionaries now match E4 keys. Nonempty C12 framing is independently
covered by original STF binary spans and derived typed source cases.

Nim 2.2.12 ARC/Clang LTO retains assertions, bounds, range, field and overflow checks. Ignored
`build/state-composition/` records build commands, corpus hash, source observations, successful
published compositions and compiler/privacy diagnostics. Linux CI runs the same tests after
native crypto construction and retains these results. Local macOS arm64 results require Linux
confirmation after push. No timing, transition or valid-state correctness claim is made.

C13 gas follows the accepted vector-compatible compact policy, with no fallback. Two additional
exact capture probes accept a known compact-gas component and reject its fixed-gas alternative.
M1 state parity remains qualified by the [parked request-namespace question](state-clarifications.md).
Further implementation scope is selected separately; proofs/persistence, PVM and transitions
remain separate work.


## Nimony branch verification

The experimental branch ports this module to pristine Nimony 0.6.3 nightly `5b51edfed`, preserving
exact chapter consumption, profile association, parent budgets, source ordering and duplicate-key
rejection. `StateCompositionResult[T]` hides status/payload behind read-only reasons and a
success-only accessor. Explicitly nullable chapter/mapping references are checked through stable
retained locals. Fixed metadata and newly extracted entry bytes remain independent copies.

Use `StateChapters` for the sixteen source slots, indexed by `StateChapterId`; its private fixed
array avoids the nightly's unsupported default initialization of a nonzero enum-indexed array.
Nominal accessors retain the chapter domain. Capture rejects an invalid chapter enum; private
storage cannot be forged or rebound by applications. Explicit typed decoder/error adapters replace
unsupported template field resolution and generic enum-member probing, with no upstream patch or
private runtime hook. The existing duplicate-key selftest caught incorrect generic error translation
after compilation; the explicit adapters retain the expected typed failure.

Run `python3 tools/test_nimony.py --compiler build/nimony-trial/nimony/bin/nimony` with the pinned
trial compiler. It includes 14,471 unchanged composition requests, seven literal checks, 224 exact
published chapter captures and fourteen complete mappings reproducing ten distinct roots. A separate
154-request raw whole-map corpus preserves the existing root sensitivity and budget checks. No
original storage keys or request identities are guessed from opaque captures.

The private ownership suite verifies retained/replaced states, copied entries/commitments, complete
parent preflight, native descriptor/aggregate bounds, immediate and delayed backend refusal and
recovery. It returns public live occupancy from 35,920 to 35,920 bytes after 1,000 warmed cycles,
including its retained chapter baseline. Thirty-six isolated actual/default reads reject through
the exact success contract; fourteen private/read-only compiler probes protect result, owner and
slot storage, and three nominal probes protect owner and entry/chapter index domains.

Results are local macOS ARM64, checked ARC/Clang LTO. All production codec modules are ported.
Unchanged width-evidence and parked namespace-witness regressions now replay through this driver
in the Nimony runner. The five early primitive/composite independent corpora now pass too,
completing local M1 validation migration parity for the documented implemented scope. Linux
execution remains separate. Next: M2 assurance signing contexts and validator-key/parent verification.
No transition execution or new namespace rule is introduced. See the
[trial](../docs/nimony-trial.md) for cumulative evidence and remaining M2/M3 work.
