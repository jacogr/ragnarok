# Guarantor assignments

## Current unreleased null-validator rule

The coordinated upgrade targets Gray Paper commit
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, `safrole.tex` nullvalkey.
Offender replacement keeps the Bandersnatch/BLS/metadata fields zero and sets
Ed25519 to02 followed by31 zero bytes. Planning and guarantor filtering share
that owned fixed constant. Authored witnesses inspect its exact bytes.
Release vector roster projections explicitly translate historical all-zero null
records into this current constant; they remain derived fixtures with original
source hashes, not claims of new official vectors. Historical evidence below
predates this rule.

## Historical release contract and evidence


`src/state/guarantors.nim` implements the read-only assignment foundation for guarantee admission.
It consumes completed posterior active/previous rosters, entropy, block slot and the posterior
canonical offender set. It neither verifies guarantee signatures nor publishes C(10).

## Normative basis

Gray Paper v0.8.0, commit `07f041dabd073f9018b418e9ee72e79dd2185401`:

- `text/utilities.tex`, Shuffling: four little-endian 32-bit words per half hash, eight per hash;
  draw `i` uses BLAKE2b-256(`entropy || E4(floor(i/8))`) at offset `4(i mod 8)`.
- `text/reporting_assurance.tex`, Guarantor Assignments: shuffle the repeated core labels
  `floor(i/3)`, then add `floor((slot mod epochSlots)/rotationSlots)` modulo population/3.
- The same section's previous-rotation equation selects posterior active/entropy[2] within an
  epoch, or posterior previous/entropy[3] across the epoch boundary.
- `text/safrole.tex`, `blacklistfilter`: null every field of an offending validator record while
  preserving the ordinal, population and assignment.
- `text/reporting_assurance.tex`, Work Report Guarantees: report slots may occupy the current
  rotation or its immediate predecessor, never a future slot.

The source hashes and the unchanged vector revision are recorded in [pins.json](pins.json).
`shuffleValidatorIndices` shuffles identity ordinals; dividing each result by three is exactly
shuffling the repeated labels because Fisher–Yates selection is independent of element values.
The helper is explicitly bounded to the protocol maximum of 1,023 validator ordinals and permits
an empty permutation for the published shuffle corpus. Actual assignment rosters must pass the
existing roster codec's minimum-six, divisible-by-three population and byte/resource policies.

The caller chooses the chain profile explicitly (full: 600/10 epoch/rotation slots; authored tiny
boundaries: 12/4). Zero periods and partial rotations per epoch are refused. Previous-rotation
subtraction occurs only when the absolute block slot is at least the rotation period: a pre-genesis
negative slot is never manufactured through unsigned wrapping. Different current/previous roster
populations are retained independently and checked only after choosing the report's rotation.

## Ownership and failures

Private acyclic ARC owners retain both complete assignment tables. Public access returns fixed
copies of a core and complete validator record; mutable source rosters, entropy and offender arrays
are never retained. Default owners, invalid ordinals, stale/future slots, invalid profiles, resource
refusals and backend failures return typed reasons. A partial shuffle or one completed rotation
cannot escape a failed plan. Result discriminators/payloads remain private and successful extraction
requires the supported checked-build contract.

These tables alone do not establish report acceptance. In particular a previous-rotation core may
no longer be active under the current population: guarantee validation must additionally check
that report core against the current population/3, signatures and all report-context constraints.

## Evidence

The eight unchanged `shuffle/shuffle_tests.json` vectors at davxy/jam-test-vectors commit
`d3c089c9a1d5352ad353626d7a2db8589f137b2a` cover lengths 0, 8, 16, 20, 50, 100, 200 and 341.
Python verifies the raw blob hash and transports supplied inputs/expected ordinals; the native
Hastur suite performs every algorithm assertion. There is no Python production implementation or
reference state-transition oracle.

Authored native tests cover rotation direction and epoch reset, three validators per core,
current/previous roster resize, historical entropy selection, inclusive previous-slot lower bound,
stale/future slots, maximum E4 time and 1,023 validators, complete offender nulling, mutation of
borrowed input after capture, invalid owners/configuration/budgets and hash-provider refusal.
A scoped 1,000-cycle alternating success/refusal workload requires equal live allocation occupancy.
Four compiler privacy rejections and two isolated default/refused result-access probes protect the
new public boundaries. This is bounded ownership evidence, not a general memory audit.

Reproduce with `make check-modules check-unit check-failures check-guards check-python`.

## Next bounded work

The [credential verifier](guarantee-credentials.md) now checks selected assignments, exact report
signatures, current-core/shard constraints and reporter identities. Authorization-pool and
service/code-hash/gas admission are next; history/anchor and dependency/package checks precede
atomic new C(10) assignment and block-coordinator integration.
