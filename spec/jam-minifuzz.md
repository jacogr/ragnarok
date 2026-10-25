# Pinned upstream minifuzz interoperability

Scope: execute the unchanged minifuzz script from conformance commit
`acd4b2da310ff25226c4d41b918712578483fd2c` against actual `serve-fuzz`
with independently calculated whole-map traces under GP
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`. GP, VRF, vectors, historical
fixtures and the conformance pin remain unchanged. This is fixed-trace upstream
tool interoperability, not a generated campaign or cross-client STF comparison.

`jam-minifuzz-pins.json` binds upstream jam-types-py0.8 source, its codec and
pure-Python dependency wheels by exact revisions/archive hashes. Preparation runs
no upstream installer, package build or global pip operation. Pristine bounded
source trees and exact wheels enter only the subprocess PYTHONPATH; `python -S`
and disabled bytecode/user-site imports isolate the upstream process. Warm source
changes, injected files, unsafe archive members or checksum changes refuse setup.
Make's `minifuzz-tools` and the owning E2E setup provide these dependencies.

Independent guest, sibling, mismatched-clock seed and checkpoint references author
35 sessions,130 signed imports and415 complete request/reply pairs before startup.
All full State responses, roots, exact headers, original-last sibling maps and
retained seeds remain independently calculated. A bounded socket proxy observes
the real minifuzz process and forwards exact bytes to the actual native target.
Every planned request/reply must match, with complete frame/process termination.
No target response constructs an expected file or repairs a later input.

The upstream runner can exit0 after a comparison mismatch. A real negative control
corrupts its last returned State value, requires upstream's decoded mismatch and
zero status, and requires the strict wrapper to fail. CI requires every exchange
plus this control; outer success flags or upstream exit status alone cannot pass.
The source-owned E2E workload and Fuzz / JAM entry include this lane. Logs, trace
pairs, independent hashes and observed frame hashes remain under ignored build/.
Compatible live-engine generated campaign validation remains pending.

Complex-effect interoperability retains all transfer, funded/incarnation,
privileged/allowance, supervised namespace and deferred scheduling sibling groups.
Every chain carries its explicit frozen deposit/code Parameters before startup;
each distinct profile owns a separate actual target process and immutable config.
Complete marker-aware header identities select GetState after epoch rotations.
All raw exchanges, complete maps, sibling queries and original-last continuations
remain strict upstream comparisons. Each host profile has its own real zero-exit
false-success control and cleanup evidence; missing, duplicate or partial profile
results fail the JAM aggregate. The finite test policy admits known4096-byte
code/queue envelopes while preserving GP code-size and deposit checks.

Observed complex replay:242 sessions,1652 signed imports,4494 exact exchanges
across three host profiles; each profile passed its own false-success control.

Epoch-spanning replay additionally covers retained dependency work, skipped-slot
expiry, request/provision lifecycle and mixed supervised/privileged/funded account
composition. Explicit original case bindings supply each deposit/code profile;
marker-bearing headers retain their entire sealed identity for state queries.
Both whole-map sibling replay and actual upstream process replay preserve GP
checks across rotations, skipped epochs and original-last continuation.

Observed epoch-effect replay:43 additional sessions,461 signed imports and1137
exact exchanges across three host profiles, each with its own mismatch control.
